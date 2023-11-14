
-- the status of pathsearch
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

local Pathfinder = Class(function(self, inst)
	self.inst = inst
	
	self.handle = nil
end)

function Pathfinder:SubmitSearch(startPos, endPos, pathcaps)
	self.handle = TheWorld.Pathfinder:SubmitSearch(startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, pathcaps)
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
	return self.handle and TheWorld.Pathfinder:GetSearchResult(self.handle)
end

function Pathfinder:KillSearch()
	if self.handle then
		TheWorld.Pathfinder:KillSearch(self.handle)
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
-- the result of C side IsClear is without bypassing blood, so dont check point on flood at this.
function Pathfinder:IsPassableAtPoint(point, pathcaps)
-- walkable of one point(on ocean land tile, creep, walls, flood)
	pathcaps = pathcaps or {allowocean = false, ignoreLand = false, ignorewalls = false, ignorecreep = false, ignoreflood = false}

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

	-- the result of C side IsClear is without bypassing blood, so dont check point on flood at this.
	-- check the flood
	--if not pathcaps.ignoreflood then
	--	local is_onflood = TheWorld.components.flooding ~= nil and TheWorld.components.flooding.OnFlood and
	--							TheWorld.components.flooding:OnFlood(point:Get())
	--	if is_onflood then
	--		return false
	--	end
	--end

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
	if ThePlayer then
		local p = ThePlayer:GetPosition()
		return self:IsPassableAtPoint(p, pathcaps)
	end
end

return Pathfinder