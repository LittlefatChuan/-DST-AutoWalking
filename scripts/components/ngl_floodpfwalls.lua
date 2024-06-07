
local function OnIsPathFindingDirty_ClientOnly(inst)
    local self = inst.components.ngl_floodpfwalls
    if self.ispathfinding == true then
        self:ApplyPathfinderWalls()
    elseif self.pftable ~= nil and next(self.pftable) then
        self:RemovePathfinderWalls()
    end
    --print("OnIsPathFindingDirty", inst)
end


local flood_no_tags = {"flying", "flood_immune", "playerghost"}
local function IgnoreFloodSlowDown(player)
	if player == nil then return false end
	return player:HasOneOfTags(flood_no_tags)
end

local function UpdatePathfindState_ClientOnly(inst)
    local self = inst.components.ngl_floodpfwalls
	local cur_ispathfinding = not IgnoreFloodSlowDown(ThePlayer)

    if cur_ispathfinding ~= self.ispathfinding then
        self.ispathfinding = cur_ispathfinding
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
    self.max_scale = 8 -- see 1467214795\scripts\prefabs\flood.lua
    self.always_apply_pathfinding = false

    self.on_world_pf_change = function(world, data)
        if self.always_apply_pathfinding or (data and data.enabled) then -- temporary/ always apply pathfinding cells and put into shared walls
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
            self.inst:RemoveComponent("ngl_floodpfwalls")
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

-- by V2C in nightmarerock.lua
local function AddSharedWall(pathfinder, x, z, inst)
    local id = tostring(x)..","..tostring(z)
    if NGL_PFWALLS_CLIENTONLY_SHARED[id] == nil then
        NGL_PFWALLS_CLIENTONLY_SHARED[id] = { [inst] = true }
        pathfinder:AddWall(x, 0, z)
        -- dont show it in Dedicated Server
        if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
		    SpawnDebugWall(x, 0, z)
        end
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
    if TheNet and not TheNet:IsDedicated() and PFWALL_CLIENTONLY_DEBUG_MODE then
	    DeSpawnDebugWall(x, 0, z)
    end
    --print("RemoveWall",x,z)
end

function PFWalls:ApplyPathfinderWalls()
    if self.pftable and next(self.pftable) ~= nil then
        -- clear the old walls
        self:RemovePathfinderWalls()
    end
    local flooding = TheWorld.components.flooding
    if flooding == nil or flooding.IsFloodTileAtPoint == nil then return end

    self.pftable = {}
    local pathfinder = TheWorld.Pathfinder
    local x, y, z = self.inst.Transform:GetWorldPosition()
    local DIMS = self.max_scale * 2
    local start_x, start_z = x - (DIMS - 1) / 2, z - (DIMS - 1) / 2

    -- copy from vito's support pilar code, again
    for i = 0, DIMS -1 do
        local x1 = start_x + i
        for j = 0, DIMS -1 do
            local z1 = start_z + j
            if flooding:IsFloodTileAtPoint(x1, 0, z1) then -- make it fittable to physics area with a larger number
                AddSharedWall(pathfinder, x1, z1, self.inst)
                table.insert(self.pftable, { x1, z1 })
            end
        end
    end
    --print("add walls:", self.inst)
end

function PFWalls:RemovePathfinderWalls()
    local pathfinder = TheWorld.Pathfinder
    for i, v in ipairs(self.pftable) do
        RemoveSharedWall(pathfinder, v[1], v[2], self.inst)
    end
    self.pftable = nil
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

