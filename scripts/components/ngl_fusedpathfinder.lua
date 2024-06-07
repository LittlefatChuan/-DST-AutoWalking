-- the status of pathsearch
require("utils/step_util")
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

local Pathfinder = Class(function(self, inst)
	self.inst = inst

    self.cpp_pathfinder = self.inst.components.ngl_pathfinder
    self.lua_pathfinder = self.inst.components.ngl_astarpathfinder
    self.cpp_pathfinder_enabled = true
    self.lua_pathfinder_enabled = true

	self.process_maxtime = 1.5 --sec
    self.process_maxtime = 1.5 --sec
end)
    
function Pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps)
    self:KillSearch()
    -- 内部优化一下
    -- 海上寻路用C端寻路器，因为海上很多点都是连通的，Lua端的Openlist会很大，效率很低
    -- 并且只海上寻路 没有洪水，没有卵石路，完全可以只用CPP寻路器处理
    -- 除非是洞穴虚空，假如玩mod人物能地下穿虚空，这时候CPP寻路器无法在虚空地皮寻路，只能用LUA寻路器
    -- use C pathfinder-only when sea sailing, because it's more effective
    -- only ocean pathfinding , no road to follow ,no flood to avoid , it's okay to only use cpp pathfinder
    -- should use Lua pathfinder to handle no ocean world（eg: Void Region of Cave））
    local only_ocean_pathfinding = TheWorld.has_ocean and pathcaps and pathcaps.allowocean and pathcaps.ignoreLand
    -- lua pathfinder is ineffective to handle ocean pathfinding 
    -- it's okay to use only cpp pathfinder to handle ocean pathfinding
    local allow_void_pathfinding = not TheWorld.has_ocean and pathcaps and pathcaps.allowocean
    -- cpp pathfinder can't handle void pathfinding
    self.cpp_pathfinder_enabled = not allow_void_pathfinding and not (self.cpp_pathfinder.process_maxtime and self.cpp_pathfinder.process_maxtime <= 0)
    self.lua_pathfinder_enabled = not only_ocean_pathfinding and not (self.lua_pathfinder.process_maxtime and self.lua_pathfinder.process_maxtime < 0)
    if self.cpp_pathfinder_enabled then 
        self.cpp_pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps)
    end
    if self.lua_pathfinder_enabled then 
        self.lua_pathfinder:SubmitSearch(startPos, endPos, pathcaps, groundcaps)
    end

    self.pathcaps = pathcaps
    self.groundcaps = groundcaps

end


function Pathfinder:GetSearchStatus()
    local cpp_pathfinder_status = self.cpp_pathfinder_enabled and self.cpp_pathfinder:GetSearchStatus() or nil
    local lua_pathfinder_status = self.lua_pathfinder_enabled and self.lua_pathfinder:GetSearchStatus() or nil
    if cpp_pathfinder_status == nil and lua_pathfinder_status == nil then 
        return nil
    elseif cpp_pathfinder_status ~= STATUS_CALCULATING and lua_pathfinder_status ~= STATUS_CALCULATING then
        if cpp_pathfinder_status == STATUS_NOPATH and lua_pathfinder_status == STATUS_NOPATH then
            return STATUS_NOPATH
        else
            return STATUS_FOUNDPATH
        end
    else
        return STATUS_CALCULATING
    end
end

local CalcCost = function(p1, p2)
    -- Manhattan distance
    --return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
    
    -- Diagnol distance 
    local dx = math.abs(p1.x - p2.x)
    local dz = math.abs(p1.z - p2.z)
    local min_xz = math.min(dx,dz)
    return dx + dz - 0.5 * min_xz  --0.5 means is approximately equal to (2- sqrt(2))
end

function Pathfinder:CalcPathCost(path, pathcaps, groundcaps)
    local steps = path and path.steps or nil
    local cost = 0
    -- dumptable(groundcaps)
    --precheck 
    if steps == nil or not IsValidPath(path) then return math.huge end

    -- fix some wrong pathfinding result when startPos is at tile's edge(at overhang area and no pathfinding wall at that tile)
    local firstPoint, secondPoint = StepToVector3(steps[1]), StepToVector3(steps[2])
    local playerPos = self.inst:GetPosition()
    local player_at_overhang = not TheWorld.Map:IsAboveGroundAtPoint(playerPos:Get()) and TheWorld.Map:IsVisualGroundAtPoint(playerPos:Get())
    if player_at_overhang and not self:IsPassableAtPoint(firstPoint, pathcaps) and not self:IsClear(playerPos, secondPoint, pathcaps) then return math.huge end

    -- calc the cost
    for i= 1, #(steps)-1 do 
        local cur, next = StepToVector3(steps[i]), StepToVector3(steps[i+1])
        -- fix creep check if the creep is between points instead at points
        cost = cost + CalcCost(cur, next) * self:CalcGroundSpeedMulti2(cur, next, groundcaps) 
    end
    return cost

end


function Pathfinder:GetSearchResult()
	if self:GetSearchStatus() == STATUS_FOUNDPATH then
        local cpp_pathfinder_result, lua_pathfinder_result
        if self.cpp_pathfinder:GetSearchStatus() == STATUS_FOUNDPATH then
            cpp_pathfinder_result= self.cpp_pathfinder:GetSearchResult()
        end
        if self.lua_pathfinder:GetSearchStatus() == STATUS_FOUNDPATH then
            lua_pathfinder_result = self.lua_pathfinder:GetSearchResult()
        end

        if cpp_pathfinder_result == nil or lua_pathfinder_result == nil then
            -- print(cpp_pathfinder_result ~= nil and "CPP SUCC" or "CPP FAILED", lua_pathfinder_result ~= nil and "LUA SUCC" or "LUA FAILED")
            return cpp_pathfinder_result or lua_pathfinder_result or nil
        else
            local cpp_pathfinder_path_cost = self:CalcPathCost(cpp_pathfinder_result, self.pathcaps, self.groundcaps)
            local lua_pathfinder_path_cost = self:CalcPathCost(lua_pathfinder_result, self.pathcaps, self.groundcaps)
            -- print("CPP PATHCOST:",cpp_pathfinder_path_cost,"LUA PATHCOST:", lua_pathfinder_path_cost)
            return (cpp_pathfinder_path_cost < lua_pathfinder_path_cost) and cpp_pathfinder_result or lua_pathfinder_result
        end
    end
end

function Pathfinder:KillSearch()
    self.cpp_pathfinder:KillSearch()
    self.lua_pathfinder:KillSearch()
end

function Pathfinder:SetPeriod(time)
	self.lua_pathfinder:SetPeriod(time)
end

--function Pathfinder:SetPerRound(amount)
--	self.lua_pathfinder:SetPerRound(amount)
--end
--
--function Pathfinder:SetMaxWork(amount)
--	self.lua_pathfinder:SetMaxWork(amount)
--end

function Pathfinder:SetTimePerRound(lua_time)
    self.lua_pathfinder:SetTimePerRound(lua_time)
end

function Pathfinder:SetMaxTime(lua_time)
    self.lua_pathfinder:SetMaxTime(lua_time)
end

function Pathfinder:IsClear(p1, p2, pathcaps)
    return self.lua_pathfinder:IsClear(p1, p2, pathcaps)
end

function Pathfinder:TestClear(pathcaps)
    return self.lua_pathfinder:TestClear(pathcaps)
end

function Pathfinder:CalcGroundSpeedMulti(point, groundcaps)
	return self.lua_pathfinder:CalcGroundSpeedMulti(point, groundcaps)
end

-- fix the creep check to check creep is between points but not at points
-- notice more params here
function Pathfinder:CalcGroundSpeedMulti2(curPoint, nextPoint, groundcaps)
    -- check creep is primary in calcgroundspeedmulti
    if groundcaps and groundcaps.speed_on_creep == ASTAR_SPEED_SLOWER then
        -- only check creep
        local creep_check_pathcaps = {ignorewalls = true, allowocean = true, ignorecreep = false}
        if not self:IsClear(curPoint, nextPoint, creep_check_pathcaps) then
            return ASTAR_COSTMULTI_SLOWER * 2
        end
    end
    return self:CalcGroundSpeedMulti(nextPoint, groundcaps)
end

function Pathfinder:IsPassableAtPoint(point, pathcaps)
	return self.lua_pathfinder:IsPassableAtPoint(point, pathcaps)
end

function Pathfinder:TestPassable(pathcaps)
    return self.lua_pathfinder:TestPassable(pathcaps)
end

return Pathfinder