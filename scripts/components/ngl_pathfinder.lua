
-- the status of pathsearch
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

local Pathfinder = Class(function(self, inst)
	self.inst = inst
	self.handle = nil
end)

local IsOverhangAtPoint = function(x, y, z)
	if type(x) == "table" and x.IsVector3 ~= nil and x:IsVector3() then
		x, y, z = x:Get()
	end
	return not TheWorld.Map:IsAboveGroundAtPoint(x, y, z) and TheWorld.Map:IsVisualGroundAtPoint(x, y, z)
end

local HasAnyWallAtTileOfPoint = function(x, y, z)
	if type(x) == "table" and x.IsVector3 ~= nil and x:IsVector3() then
		x, y, z = x:Get()
	end
	local cx, _, cz = TheWorld.Map:GetTileCenterPoint(x, y, z)
	for dx = -1.5 , 1.5 do
		for dz = -1.5, 1.5 do
			if TheWorld.Pathfinder:HasWall(cx+dx, 0, cz+dz) then
				return true
			end
		end
	end
	return false
end

function Pathfinder:TempAddWall(x, y, z)
	if type(x) == "table" and x.IsVector3 ~= nil and x:IsVector3() then
		x, y, z = x:Get()
	end
	if not TheWorld.Pathfinder:HasWall(x, 0, z) then
		TheWorld.Pathfinder:AddWall(x, 0, z)
		if self.temp_addedwalls == nil then
			self.temp_addedwalls = {}
		end
		table.insert(self.temp_addedwalls, {x = x, y = 0, z = z})
	end
end

function Pathfinder:TempRemoveWall(x, y, z)
	if type(x) == "table" and x.IsVector3 ~= nil and x:IsVector3() then
		x, y, z = x:Get()
	end
	if TheWorld.Pathfinder:HasWall(x, 0, z) then
		TheWorld.Pathfinder:RemoveWall(x, 0, z)
		if self.temp_removedwalls == nil then
			self.temp_removedwalls = {}
		end
		table.insert(self.temp_removedwalls, {x = x, y = 0, z = z})
	end
end

function Pathfinder:CancelAllTempWalls()
	if self.temp_addedwalls ~= nil then
		for _, pt in ipairs(self.temp_addedwalls) do
			TheWorld.Pathfinder:RemoveWall(pt.x, 0, pt.z)
		end
		self.temp_addedwalls = {}
	end
	if self.temp_removedwalls ~= nil then
		for _, pt in ipairs(self.temp_removedwalls) do
			TheWorld.Pathfinder:AddWall(pt.x, 0, pt.z)
		end
		self.temp_removedwalls = {}
	end
end

function Pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps)
	-- 一种保底的方法来绕开蜘蛛网，内部处理一下
	-- 总的来说依然还是：pathcaps.ignorecreep = false 表示 “不能”过蜘蛛网，groundcaps.speed_on_creep = ASTAR_SPEED_SLOWER 表示 “最好不”过蜘蛛网
	-- 官方的寻路绕蜘蛛网不太好用，斜对角方向可能会直接穿过蜘蛛网
	-- another way to avoid creep via offical C pathfinder
	local avoidcreep_pathcaps = shallowcopy(pathcaps)
	if groundcaps and groundcaps.speed_on_creep == ASTAR_SPEED_SLOWER then
		avoidcreep_pathcaps.ignorecreep = false
		-- print("redirect CPP pathfinder's pathcaps to avoid creep")
	end

	-- fix wrong pathfinding result when working as tile search and startpos/endpos is at overhang
	-- 手动修复overhang区域以地皮搜索路径导致的小问题
	if IsOverhangAtPoint(startPos) and not HasAnyWallAtTileOfPoint(startPos) then
		local cx, _, cz = TheWorld.Map:GetTileCenterPoint(startPos:Get())
		self:TempAddWall(cx, 0, cz)
	end
	if IsOverhangAtPoint(endPos) and not HasAnyWallAtTileOfPoint(endPos) then
		local cx, _, cz = TheWorld.Map:GetTileCenterPoint(endPos:Get())
		self:TempAddWall(cx, 0, cz)
	end

	self.handle = TheWorld.Pathfinder:SubmitSearch(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, avoidcreep_pathcaps)
	self.search_start_time = GetTime()
end


function Pathfinder:GetSearchStatus()
	 -- set the time limit (fake)
	if self.process_maxtime and self.search_start_time and GetTime() > self.search_start_time + self.process_maxtime then
		return STATUS_NOPATH
	else
		return self.handle and TheWorld.Pathfinder:GetSearchStatus(self.handle)
	end
end

function Pathfinder:GetSearchResult()
	self:CancelAllTempWalls()
	return self.handle and TheWorld.Pathfinder:GetSearchResult(self.handle)
end

function Pathfinder:KillSearch()
	if self.handle then
		TheWorld.Pathfinder:KillSearch(self.handle)
		self:CancelAllTempWalls()
	end
end

function Pathfinder:SetMaxTime(time)
	self.process_maxtime = time
end

function Pathfinder:IsClear(p1, p2, pathcaps)
	return TheWorld.Pathfinder:IsClear(p1.x, 0, p1.z, p2.x, 0, p2.z, pathcaps)
end

function Pathfinder:TestClear(pathcaps)
	if ThePlayer and TheInput then
		local p1 = ThePlayer:GetPosition()
		local p2 = TheInput:GetWorldPosition()
		print(self:IsClear(p1, p2, pathcaps) and "hasLOS" or "noLOS")
	end
end

-- copy from astar_util:IsWalkablePoint
function Pathfinder:IsPassableAtPoint(point, pathcaps)
-- walkable of one point(on ocean land tile, creep, walls, flood)
	pathcaps = pathcaps or {allowocean = false, ignoreLand = false, ignorewalls = false, ignorecreep = false}

	-- check ocean and Land
	if not pathcaps.allowocean or pathcaps.ignoreLand then
		local is_onland = TheWorld.Map:IsVisualGroundAtPoint(point:Get())
		if not pathcaps.allowocean and not is_onland then -- not allow ocean but actually on ocean
			return false
		end
		if pathcaps.ignoreLand and is_onland then -- not allow land but actually on land
			return false
		end
	end
	-- check the creep
	if not pathcaps.ignorecreep then
		local is_oncreep = TheWorld.GroundCreep:OnCreep(point:Get())
		if is_oncreep then
			return false
		end
	end

	-- check the walls
	if not pathcaps.ignorewalls then
		local has_wall = TheWorld.Pathfinder:HasWall(point:Get())
		if has_wall then
			return false
		end
	end

	return true
end

function Pathfinder:TestPassable(pathcaps)
	-- if ThePlayer then
	-- 	local p = ThePlayer:GetPosition()
	-- 	return self:IsPassableAtPoint(p, pathcaps)
	-- end

	if TheInput then
		local pt = TheInput:GetWorldPosition()
		return self:IsPassableAtPoint(pt, pathcaps)
	end
end

return Pathfinder