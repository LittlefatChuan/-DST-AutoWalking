
local function OnIsPathFindingDirty_ClientOnly(inst)
    local self = inst.components.ngl_custompfwalls
    if self.ispathfinding == true then
        self:ApplyPathfinderWalls()
    elseif self.pftable ~= nil and next(self.pftable) then
        self:RemovePathfinderWalls()
    end
    --print("OnIsPathFindingDirty", inst)
end

local function UpdatePathfindState_ClientOnly(inst)
    local self = inst.components.ngl_custompfwalls
	local cur_ispathfinding = self.enable_fn == nil or self.enable_fn(inst)
    local cur_rad = self.radius_fn ~= nil and self.radius_fn(inst) or 0.5
	local cur_pos = inst:GetPosition() or Vector3(0,0,0)
	local pos_changed = cur_pos ~= self.last_pos
	local rad_changed = cur_rad ~= self.last_rad

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

-- virtual pathfinding walls , and no more relatived to physics radius, it be set only for avoiding danger
local PFWalls = Class(function(self, inst)
    self.inst = inst
    self.pftable = nil
    self.ispathfinding = false
    self.last_pos = nil
    self.last_rad = nil
    self.radius_fn = nil
	self.enable_fn = nil
	 
	-- the prefabs that has registered pathfinding cell in game, eg: walls, support_pillar, nightmarerock
    self.always_apply_pathfinding = false

    self.on_world_pf_change = function(world, data)
        if self.always_apply_pathfinding or (data and data.enabled) then -- temporary/always apply pathfinding cells and put into shared walls
            UpdatePathfindState_ClientOnly(inst)
        elseif self.pftable ~= nil and next(self.pftable) then -- autowalking is over , cancel the temporary record(if always_apply_pathfinding = false)
            self:RemovePathfinderWalls()
            self.ispathfinding = false
        end
    end

    self.inst:DoTaskInTime(0, function()
        if self.inst.Transform then -- physics component is not necessary any more
            InitializePathFinding_ClientOnly(self.inst, self)
        else
            self.inst:RemoveComponent("ngl_custompfwalls")
        end
    end)

end)

-- global variable
NGL_PFWALLS_CLIENTONLY_SHARED =  {}

PFWALL_CLIENTONLY_DEBUG_MODE = false
local function SpawnDebugWall(x,y,z)
    local wall = SpawnPrefab("wall_stone_2_item_placer")
    wall:AddTag("ignorewalkableplatforms") -- cant be carried by boat
    wall:RemoveTag("CLASSIFIED")
    wall.Transform:SetPosition(x,y,z)
    wall.AnimState:OverrideMultColour(0.6,0.6,0,.4) -- in yellow
end
local function DeSpawnDebugWall(x,y,z)
    local ents = TheSim:FindEntities(x,y,z,.1,{"placer"})
    for k,v in ipairs(ents) do
        v:Remove()
    end
end

function PFWalls:SpawnAllDebugWalls()
	-- use a circle helper instead, otherwise spawning too many walls could make game freeze 
	local function spawnhelper(x, y, z, rad)
		local inst = CreateEntity()
		inst.persists = false
		local tran = inst.entity:AddTransform()
		tran:SetPosition(x, y, z)
		local scale = math.sqrt(rad * 300 / 1900)
		tran:SetScale(scale, scale, scale)
		local anim = inst.entity:AddAnimState()
		anim:SetBank("firefighter_placement")
		anim:SetBuild("firefighter_placement")
		anim:PlayAnimation("idle")
		anim:SetOrientation(ANIM_ORIENTATION.OnGround)
		anim:SetLayer(LAYER_BACKGROUND)
		anim:SetAddColour(0.6,0.6,0,0) -- yellow
		anim:SetLightOverride(1)
		anim:SetSortOrder(1)
		inst:AddTag("FX")
		return inst
	end

	local pos = self.last_pos
	local rad = self.last_rad
	if pos and rad then
		if self.debugwalls == nil then
			self.debugwalls = {}
		end
		table.insert(self.debugwalls, spawnhelper(pos.x, 0, pos.z, rad))
	end
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
    local rad = self.last_rad or 0.5
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

