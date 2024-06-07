
local function OnIsPathFindingDirty_ClientOnly(inst)
    local self = inst.components.ngl_obstaclepfwalls
    if self.ispathfinding == true then
        self:ApplyPathfinderWalls()
    elseif self.pftable ~= nil and next(self.pftable) then
        self:RemovePathfinderWalls()
    end
    --print("OnIsPathFindingDirty", inst)
end

local function UpdatePathfindState_ClientOnly(inst)
    local self = inst.components.ngl_obstaclepfwalls
    local is_on_pathfinding_platform = inst.Transform and inst:IsOnValidGround() and inst:GetCurrentPlatform() == nil
	local is_active = inst.Physics:IsActive()   --physics active changed
	local can_collide_player = self:CanCollideWith(COLLISION.CHARACTERS) --physics collision changed
	local cur_ispathfinding = is_on_pathfinding_platform and is_active and can_collide_player or false
    local cur_rad = inst.Physics:GetRadius() or 0
    local cur_pos = inst:GetPosition() or Vector3(0,0,0)
	local pos_changed = cur_pos ~= self.last_pos
    local rad_changed = cur_rad ~= self.last_rad --physics radius changed
    
    if cur_ispathfinding ~= self.ispathfinding or (cur_ispathfinding and (rad_changed or pos_changed)) then
        self.ispathfinding = cur_ispathfinding
        self.last_pos = cur_pos
        self.last_rad = cur_rad
        OnIsPathFindingDirty_ClientOnly(inst)
    end
end


local function InitializePathFinding_ClientOnly(inst, self)
    -- update the pfwalls only when accepted change event(we should push this event before everytime start to autowalk)
    --inst:ListenForEvent("ngl_update_pathfinderwalls", function() UpdatePathfindState_ClientOnly(inst) end, TheWorld)
    inst:ListenForEvent("ngl_pathfinding_change", self.on_world_pf_change , TheWorld)
    self.listening_pfwalls_change = true
    self.on_world_pf_change(TheWorld,{enabled = TheWorld.ngl_ispathfinding})
end

-- CLIENT_ONLY VERSION OF PFWALLS COMPONENT, SEE workshop-2866542075 "components/ngl_pfwalls.lua" for server version
-- restore the points of the pathfinder wall we added
-- the walls are virtual and not the prefab, it's just added via TheWorld.Pathfinder:AddWall and for registering pathfinding cell
-- creatures will walk around the pathfinding cell area
local PFWalls = Class(function(self, inst)
    self.inst = inst
    self.pftable = nil
    self.ispathfinding = false
    self.last_pos = nil
    self.last_rad = nil

    -- the prefabs that has registered pathfinding cell in game, eg: walls, support_pillar, nightmarerock
    self.always_apply_pathfinding = false

    self.on_world_pf_change = function(world, data)
        if self.always_apply_pathfinding or (data and data.enabled) then -- temporary apply pathfinding cells and put into shared walls
            UpdatePathfindState_ClientOnly(inst)
        elseif self.pftable ~= nil and next(self.pftable) then -- autowalking is over , cancel the temporary record(if always_apply_pathfinding = false)
            self:RemovePathfinderWalls()
            self.ispathfinding = false
        end
    end

    self.inst:DoTaskInTime(0, function()
        if self.inst.Physics and self.inst.Transform then
            InitializePathFinding_ClientOnly(self.inst, self)
        else
            self.inst:RemoveComponent("ngl_obstaclepfwalls")
        end
    end)

end)

-- global variable
NGL_PFWALLS_CLIENTONLY_SHARED = {}

-- BitAND by 老王
-- 位运算，按位与
local function BitAND(a, b)
    local p, c = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then
            c = c + p
        end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end
-- a function return can player collide with other
-- for example: if we can cross the ocean and land ,then it return false with COLLISION.LAND_OCEAN_LIMITS
function PFWalls:CanCollideWith(COLLISION_TYPE)
-- | COLLISION_TYPE    | MASK_VALUE | BIN_VALUE           |
-- | ----------------- | ---------- | ------------------- |
-- | GROUND            | 32         | 0000 0000 0010 0000 |
-- | BOAT_LIMITS       | 64         | 0000 0000 0100 0000 |
-- | LAND_OCEAN_LIMITS | 128        | 0000 0000 1000 0000 |
-- | LIMITS            | 192        | 0000 0000 1100 0000 |
-- | WORLD             | 224        | 0000 0000 1110 0000 |
-- | ITEMS             | 256        | 0000 0001 0000 0000 |
-- | OBSTACLES         | 512        | 0000 0010 0000 0000 |
-- | CHARACTERS        | 1024       | 0000 0100 0000 0000 |
-- | FLYERS            | 2048       | 0000 1000 0000 0000 |
-- | SANITY            | 4096       | 0001 0000 0000 0000 |
-- | SMALLOBSTACLES    | 8192       | 0010 0000 0000 0000 |
-- | GIANTS            | 16384      | 0100 0000 0000 0000 |

    local collision_mask = self.inst.Physics:GetCollisionMask()
    return collision_mask and BitAND(collision_mask,COLLISION_TYPE) == COLLISION_TYPE
end


PFWALL_CLIENTONLY_DEBUG_MODE = false
local function SpawnDebugWall(x,y,z)
    local wall = SpawnPrefab("wall_stone_2_item_placer")
    wall:AddTag("ignorewalkableplatforms") -- cant be carried by boat
    wall:RemoveTag("CLASSIFIED")
    wall.Transform:SetPosition(x,y,z)
    wall.AnimState:OverrideMultColour(0.8,0,0,.4) -- in red
end
local function DeSpawnDebugWall(x,y,z)
    local ents = TheSim:FindEntities(x,y,z,.1,{"placer"})
    for k,v in ipairs(ents) do
        v:Remove()
    end
end

function PFWalls:SpawnAllDebugWalls()
	local function spawnwall(x,y,z)
		local wall = SpawnPrefab("wall_stone_2_item_placer")
		wall:AddTag("ignorewalkableplatforms") -- cant be carried by boat
		wall.Transform:SetPosition(x, y, z)
		wall.AnimState:OverrideMultColour(0.8,0,0,.4) -- in yellow
		return wall
    end
    self.inst.debugwalls_task = self.inst:DoPeriodicTask(FRAMES, function()
		if self.debugwalls == nil then
			self.debugwalls = {}
		end
		for i = 1, 2 do  -- spawn 2 walls per-frame to make game performance better
			local index = #(self.debugwalls)+1
			local pt = self.pftable and self.pftable[index] or nil
			if pt ~= nil then
				table.insert(self.debugwalls, spawnwall(pt[1],0,pt[2]))
			else
				if self.inst.debugwalls_task then
					self.inst.debugwalls_task:Cancel()
					self.inst.debugwalls_task = nil
				end
				break
			end
		end
    end)
end
function PFWalls:DeSpawnAllDebugWalls()
	if self.debugwalls ~= nil and next(self.debugwalls) ~= nil then
		for _, wall in ipairs(self.debugwalls) do 
			wall:Remove()
		end
		self.debugwalls = {}
	end
end

-- by V2C in nightmarerock.lua
local function AddSharedWall(pathfinder, x, z, inst)
    local id = tostring(x)..","..tostring(z)
    if NGL_PFWALLS_CLIENTONLY_SHARED[id] == nil then
        NGL_PFWALLS_CLIENTONLY_SHARED[id] = { [inst] = true }
        pathfinder:AddWall(x, 0, z)
        -- dont show it in Dedicated Server
--        if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
--		    SpawnDebugWall(x, 0, z)
--        end
        --print("AddWall",x,z)
    else
        NGL_PFWALLS_CLIENTONLY_SHARED[id][inst] = true
    end
end

local function RemoveSharedWall(pathfinder, x, z, inst)
    local id = tostring(x)..","..tostring(z)
    if NGL_PFWALLS_CLIENTONLY_SHARED[id] ~= nil then
        NGL_PFWALLS_CLIENTONLY_SHARED[id][inst] = nil
        if next(NGL_PFWALLS_CLIENTONLY_SHARED[id]) ~= nil then
            return
        end
        NGL_PFWALLS_CLIENTONLY_SHARED[id] = nil
    end
    pathfinder:RemoveWall(x, 0, z)
--    if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
--	    DeSpawnDebugWall(x, 0, z)
--    end
    --print("RemoveWall",x,z)
end

-- should make it better 
-- it seems will be useful: https://www.redblobgames.com/grids/circle-drawing/
function PFWalls:ApplyPathfinderWalls()
    if self.pftable and next(self.pftable) ~= nil then
        -- clear the old walls
        self:RemovePathfinderWalls()
    end
    self.pftable = {}
    local pathfinder = TheWorld.Pathfinder
    local x, y, z = self.inst.Transform:GetWorldPosition()
    -- we should normalize the coord before Pathfinder:AddWall
    local normalized_x = math.floor(x) + .5
    local normalized_z = math.floor(z) + .5
    local rad = self.inst.Physics:GetRadius() or 0
    local offset = math.ceil(rad) + 1 -- must be an int
    for dx = -(offset), (offset) do
        local x1 = normalized_x + dx
        for dz = -(offset), (offset) do
            local z1 = normalized_z + dz
            if VecUtil_DistSq(x1, z1, x, z) <= (rad+.45)*(rad+.45) then -- make it fittable to physics area with a larger number
                AddSharedWall(pathfinder, x1, z1, self.inst)
                table.insert(self.pftable, { x1, z1 })
            end
        end
    end
	if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
	    self:SpawnAllDebugWalls()
    end
    --print("add walls:", self.inst)
end

function PFWalls:RemovePathfinderWalls()
    local pathfinder = TheWorld.Pathfinder
    for i, v in ipairs(self.pftable) do
        RemoveSharedWall(pathfinder, v[1], v[2], self.inst)
    end
    self.pftable = nil
	if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
	    self:DeSpawnAllDebugWalls()
    end
	--print("remove walls:", self.inst)
end

-- called via inst:RemoveComponent
function PFWalls:OnRemoveFromEntity()
    
    if self.listening_pfwalls_change then
        self.inst:RemoveEventCallback("ngl_pathfinding_change", self.on_world_pf_change, TheWorld)
    end

    if self.pftable and next(self.pftable) then
        self:RemovePathfinderWalls()
        --print("delete succ")
    else
        --print("delete faile")
    end
end

-- called via inst:Remove()
function PFWalls:OnRemoveEntity()
	self:OnRemoveFromEntity()
end

return PFWalls

