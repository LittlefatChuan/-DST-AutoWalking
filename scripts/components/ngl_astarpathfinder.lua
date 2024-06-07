--local AStarUtil = require("utils/astar_util") -- AStar
local AStarUtil = require("utils/bidir_astar_util") -- Bi-directional AStar
require("utils/step_util")

-- the status of pathsearch
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

local TURF_SPEED_UP = 1
local TURF_SPEED_DOWN = -1

local Pathfinder = Class(function(self, inst)
	self.inst = inst

	-- use for astar pathfind
	self.path = nil
	
	self.search_data = nil
	self.search_status = nil
	self.search_process = nil
	
	self.process_period = FRAMES
	self.process_time_per_round =  0.8*FRAMES --sec
	self.process_maxtime = 2 --sec
end)

function Pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps)
	self:KillSearch()
	self.search_data = AStarUtil.requestSearch(startPos,
											endPos, 
											pathcaps,
											groundcaps
										  ) 
	self.search_status = STATUS_CALCULATING	-- Initialize as in calculating
	self.search_start_time = GetTime()
	self.search_process = self.inst:DoPeriodicTask(self.process_period,
						function()
							if AStarUtil.processSearch(self.search_data, self.process_time_per_round, self.process_maxtime)  then -- pathsearch finished
								if self.search_data and IsValidPath(self.search_data.path) then 
									self.search_status = STATUS_FOUNDPATH	--found out
									--print("astar pathfind success!")
								else 
									self.search_status = STATUS_NOPATH	--no way
									--print("astar pathfind fail!")
								end
								self.search_process:Cancel()
								self.search_process = nil
								--print("astarpathfinder cost time:",GetTime() - self.search_start_time)
							else 
								self.search_status = STATUS_CALCULATING -- in calculating , waiting for next round
							end
						end, 0)
	
end


function Pathfinder:GetSearchStatus()
	return self.search_status
end

function Pathfinder:GetSearchResult()
	return self.search_data and self.search_data.path
end

function Pathfinder:KillSearch()
	if self.search_process ~= nil then
		self.search_process:Cancel()
		self.search_process = nil
	end
	
	
	self.search_data = nil
	self.search_status = nil
end

function Pathfinder:SetPeriod(time)
	self.process_period = time
end

--function Pathfinder:SetPerRound(amount)
--	self.process_work_per_round = amount
--end
--
--function Pathfinder:SetMaxWork(amount)
--	self.process_maxwork = amount
--end

function Pathfinder:SetTimePerRound(time)
	self.process_time_per_round = time
end

function Pathfinder:SetMaxTime(time)
	self.process_maxtime = time
end

function Pathfinder:IsClear(p1, p2, pathcaps)
	if AStarUtil.CheckWalkableFromPoint then
		return AStarUtil.CheckWalkableFromPoint(Vector3(p1.x, 0, p1.z), Vector3(p2.x, 0, p2.z), pathcaps)
	end
end

function Pathfinder:TestClear(pathcaps)
	if ThePlayer and TheInput then
		local p1 = ThePlayer:GetPosition()
		local p2 = TheInput:GetWorldPosition()
		local result, reason = self:IsClear(p1, p2, pathcaps)
		print(result and "hasLOS" or "noLOS", reason or nil)
	end
end

function Pathfinder:CalcGroundSpeedMulti(point, groundcaps)
	return AStarUtil.calcGroundSpeedMulti and AStarUtil.calcGroundSpeedMulti(point, groundcaps)
end

function Pathfinder:IsPassableAtPoint(point, pathcaps)
	return AStarUtil.IsWalkablePoint and AStarUtil.IsWalkablePoint(point, pathcaps)
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