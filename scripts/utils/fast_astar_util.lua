-- 我有个想法，但是没有时间实现，目前openlist里面点的数量太多了，只能在客户端一个实体用，多了就炸了。
-- 我想能不能改进一下能给服务器的多个prefab 实体用，实现远距离的寻路：
-- 在A星算法的框架下，求相邻点的连通性我目前是用IsClear接口，并且点的网格间距很小，相隔一个地皮（4），这就导致我们需要检测很多点，openlist很大
-- 能不能把间距调大一些，比如8，16，并且连通性用官方寻路的结果来代替，就是SubmitSearch --> GetSearchResult 而不是IsClear
-- 比如求相邻8个方向的点，就一次向TheWorld.Pathfinder发送8个寻路请求，然后需要等待他们完成寻路
-- F值和G值由距离值和计算时间加权，因为计算时间的大小也一定程度反应两个点的距离远近或者路径复杂程度。
-- 当然我们还需要额外的一个变量来存储两个点之间的路径，用做最后迭代拼接道路，路径会很冗余，最后需要平滑一下
-- 我可能没有时间去实现了，留给大家试试，下面的是之前的A星框架
---------------------
-- For DebugPrint  --
---------------------
local DEBUG_MODE = false

local function DebugPrint(...)
	if DEBUG_MODE then
		return print(...)
	end
end
---------------------
-- Local Variables --
---------------------


-- 栅格/采样节点的距离间隔
-- Distance between pathfinding nodes
local PATH_NODE_DIST = 8
local PATH_NODE_DIST_SQ = PATH_NODE_DIST * PATH_NODE_DIST

-- 最大的工作量（即一共访问的点数量），达到后强制停止寻路
-- pathfinding will forcestop when it reach the max work amount
local PATH_MAX_WORK = 100
---------------------
-- Local Functions --
---------------------

-- 返回一个基于玩家位置为原点的2D相对位置坐标，单位长度为PATH_NODE_DIST
-- Makes a 2int coordinate
-- @param x : x val of coordinate
-- @param y : y val of coodinate
-- @return  : 2int coordinate table:
--       .x : x val of coordinate
--       .y : y val of coordinate
--       .f_score : g_score + h_score
local makeCoord = function(x, y, f_score)
	return 	{
				x = x,
				y = y,
				f_score = f_score or 0
			}
end

-- 基于玩家原点的相对坐标转换为世界中的绝对位置
-- Converts a 2int coordinate to Vector3
-- @param origin : The origin of the coordinate system
-- @param coord  : coordinate to convert
-- @return       : the Vector3 in world space corresponding to the given coordinate
local coordToPoint = function(origin, coord)
	return Vector3	(
						origin.x + (coord.x * PATH_NODE_DIST),
						0,
						origin.z + (coord.y * PATH_NODE_DIST)
					)
end

-- 世界位置 转换为 Step类型 （元素分别为y，x，z 的表结构）
-- Vector3 --> {y,x,z}
local pointToStep = function(point)
	return {y = point.y, x = point.x, z = point.z}
end

-- Step类型 转为 世界位置
-- {y,x,z} --> Vector3
local stepToPoint = function(step)
	return Vector3(step.x, step.y, step.z)
end

-- 二分查找插入的位置
local function binarySearchIndexToInsert(t, coord)
   local left, right = 1, #(t)
   while left <= right do
       local mid = math.floor((left + right)/2)
       if coord.f_score > t[mid].f_score then
           left = mid + 1
       elseif coord.f_score < t[mid].f_score then
           right = mid - 1
       else --  num == t[mid].f_score
           return mid
       end
   end
    return left
end

-- 保持开放序列从小到大有序，查找合适的位置插入到序列
-- insert to the openlist and keep the list sorted meanwhile
local pushIntoOpenList = function(search, coord)
	if #search.frontier == 0 then -- 如果没有元素，则直接插入
		table.insert(search.frontier, coord)
	else	-- 否则，二分查找插入的位置，保持从小到大有序状态
		--for i=1, #(search.frontier) do
		--	if coord.f_score < search.frontier[i].f_score then
		--		table.insert(search.frontier, i, coord)
		--		return
		--	end
		--end
		local index = binarySearchIndexToInsert(search.frontier, coord)
		table.insert(search.frontier, index, coord)
	end
end

-- 因为序列已经是有序的，因此第一个元素就是最小F值的坐标
-- since the openlist has been sorted ,just return the first coord which is the min F scores coord
local popFromOpenList = function(search)
	-- 已经是有序的，所以直接返回第一个元素即是最小F值的
	if search.frontier and #(search.frontier) > 0 then
		local best = search.frontier[1]
		table.remove(search.frontier, 1)
		return best
	else
		DebugPrint("[A STAR PATHFINDER] : " .. "no element in openlist!")
	end
end


-- 是否已经访问了这个坐标
-- Return true if we visited/tracked this coord , otherwise false
local visited = function(search, coord)
	if search.g_score_so_far[coord.x] == nil then
		search.g_score_so_far[coord.x] = {}
	end
	if search.direction_so_far[coord.x] == nil then
		search.direction_so_far[coord.x] = {}
	end
	return search.g_score_so_far[coord.x][coord.y] == nil
	
end

-- 计算损失值，寻路计算的时间来表示
local calcCost = function(p1, p2)
	-- Manhattan distance
	--return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
	
	-- Diagnol distance 
	local dx = math.abs(p1.x - p2.x)
	local dz = math.abs(p1.z - p2.z)
	local min_xz = math.min(dx,dz)
	return dx + dz - 0.5 * min_xz  --0.5 means is approximately equal to (2- sqrt(2))
end

-- check the LOS and potiental LOS
local function CheckWalkableFromPoint(pos, target_pos, pathcaps, ignore_checkwalls)
	local hasLOS = TheWorld.Pathfinder:IsClear(
													pos.x, pos.y, pos.z,
													target_pos.x, target_pos.y, target_pos.z,
													pathcaps
												)
	return true
end

-- 构建路径，从末尾节点向前遍历camefrom链表，其中只有方向不同的点才会插入到路径中，可以简化路径
-- Constructs a path from a finishedPath
-- @param search 	   : The search you request, which contains the params of pathfinding 
-- @param finalCoord   : The finalCoord that close the dest,but not the dest
-- @return             : The same path, stored in native format
local makePath = function(search, finalCoord)
	-- Convert came_from to the path 
	-- Structure: table
	-- .steps
	--       .1.y = 0
	--       .1.x = <x value>
	--       .1.z = <z value>
	--       ...
	
	-- construct path part
    -- be careful don't put step table of the same value into steps ,otherwise theplayer will goto the void with position -1.#J
	local path = { steps = { } }
	-- the nearest point to dest
	local finalPoint = coordToPoint(search.startPos, finalCoord)

	local lastDirection = finalPoint - search.endPos
	local currentCoord = finalCoord
	local lastCoord = currentCoord
	while(currentCoord.x ~= 0 or currentCoord.y ~= 0) do -- util the startcoord (0,0)
		local currentDirection = search.direction_so_far[currentCoord.x][currentCoord.y]
		-- In order to simplify the path, only the steps with different direction will be added
		if currentDirection ~= lastDirection   then
			local worldPoint = coordToPoint(search.startPos, currentCoord)
			--local point = Vector3(worldVec:Get()) It's Wrong!
			-- Notice: the step is a table of {y,x,z}, not Vector3
			-- to stay the same with klei's pathfinding result format
			local step = pointToStep(worldPoint)
			table.insert(path.steps, step)
		end
		lastDirection = currentDirection
		lastCoord = currentCoord
		currentCoord = search.came_from[currentCoord]
	end
	-- CurrentCoord == startCoord(0,0) when reach here 

	table.insert(path.steps, pointToStep(search.startPos))

	path.steps = table.reverse(path.steps) -- klei has write it down in the util.lua
	
	return path
end


-- 另一种平滑路径的方法，在构建完路径后跑一遍，每三个点两头hasLos，则中间点为非必要点
-- a method to smooth the path via run through the path and check LOS between points
-- remove the unneccessary points which has LOS ,except the points on the road
local smoothPath = function(search)
	-- smooth path part
	-- ie: {0,0}, {0,2}, {3,2} -> {0,0}, {3,2} (given LOS)
	
	local path = search.path
	local index = 2
	local pathcaps = search.pathcaps

	while(index < #(path.steps)) do
    
		-- Points to test
		local pre = path.steps[index-1]
		local post = path.steps[index+1]
		local cur = path.steps[index]

		local prePoint, curPoint, postPoint = stepToPoint(pre), stepToPoint(cur), stepToPoint(post)

        -- dont remove the points that on speedup_turf even if they're have LOS with last point
		if CheckWalkableFromPoint(prePoint, postPoint, pathcaps) then -- Has LOS
			table.remove(path.steps, index)
		else -- No LOS
			index = index + 1
		end
	end
	return path

end

------------------------
-- External Functions --
------------------------

-- 请求一个搜索，参数为起点，终点，路径设置（ignorecreep = true 指忽视即可以穿过蜘蛛网）和特殊地面设置（卵石路上和蛛网的速度变化，false则不考虑）
-- 搜索中包含了路径的信息，和用于寻路的一些初始变量
-- @param startPos : A Vector3 containing the starting position in world units
-- @param endPos   : A Vector3 continaing the ending position in world units
-- @param pathcaps : (Optional) the pathcaps to use for pathfinding
-- @param groundcaps: (Optional) whether movement speed get changed in road /in creep (spider-web)
-- @return         : A partial path object
--                 .path : If path is finished via LOS, this will be populated, otherwise nil
local requestSearch = function(startPos, endPos, pathcaps, groundcaps)
	
	----------------------
	-- Store parameters --
	----------------------
	local search = { }

	search.startPos = Vector3(startPos:Get())
	search.endPos   = Vector3(endPos:Get())

	-------------------------
	-- Prepare Pathfinding --
	-------------------------
		
	-- search variable init
	search.frontier = { } 			-- 1 dim array, coord as element
	search.g_score_so_far = { }		-- 2 dim array, coord's x,y as index, number as element
	search.direction_so_far = { }	-- 2 dim array, coord's x,y as index, Vector3 as element
	search.came_from = { }			-- linkedlist , coord as element
	
	search.path = nil
	table.insert(search.frontier, makeCoord(0,0,0))
	search.g_score_so_far[0]={}
	search.g_score_so_far[0][0] = 0
	
	search.direction_so_far[0]={}
	search.direction_so_far[0][0] = Vector3(0,0,0)
	-- search info init
	search.totalWorkDone = 0
	search.startTime = GetTime()

	return search
end


-- 处理搜索，放在PeriodicTask或者OnUpdate，输入是每轮的最大处理量，
-- 如果找到返回true，结果放在search.path里
-- 如果运行到超过最大量则返回false，因此应该放在PeroidicTask或者OnUpdate里，反复继续上次的执行，这种少量分次运行应该能更好处理中止
-- @param search 		 : The search to finish (request one via requestSearch)
-- @param workPerRound   : The number of point track pertime
-- @param maxWork        : The search will process until reach the maxWork amount
-- @return    			 : true if search is over (path == nil means not found path, path is valid means we found it), false if reach the workPerRound you set
local processSearch = function(search, workPerRound, maxWork)

	-- Path already found, return
	if search.path ~= nil then
		return true
	end
	
	-- Cache parameters
	local origin = search.startPos
	
	-- Paths processed this run
	local workDone = 0

	-- Process until finished (no search.frontier remain or a path is found)
	while #search.frontier > 0 do
		
		-- get the coord of min F value
		local currentCoord = popFromOpenList(search)
		local currentPoint = coordToPoint(origin, currentCoord)
		
		---------------------------------
		-- Successed in Pathfinding !! --
		---------------------------------
		--pathfinding finish
		if CheckWalkableFromPoint(currentPoint, search.endPos, search.pathcaps)
				and calcCost(currentPoint, search.endPos) <= PATH_NODE_DIST then
			
			DebugPrint("[A STAR PATHFINDER] : " .. "start generate path！")
			search.path = makePath(search, currentCoord)
			
			-- use another smooth method already, we penalize nodes where there is a change of direction
			-- see function calcDirectionMulti
			search.path = smoothPath(search)
			
			-- update info
			search.endTime = GetTime()
			search.costTime = search.endTime - search.startTime
			DebugPrint("[A STAR PATHFINDER] : " .. "finish pathfinding !, cost time: " .. search.costTime .. ",tracked points :" .. search.totalWorkDone )
			return true
		end
		
			-- Candidate points, 8 directions
			local candidatePoints = 	{
											makeCoord(currentCoord.x    , currentCoord.y + 1),							
											makeCoord(currentCoord.x + 1, currentCoord.y	),
											makeCoord(currentCoord.x 	, currentCoord.y - 1),
											makeCoord(currentCoord.x - 1, currentCoord.y 	),
											makeCoord(currentCoord.x + 1, currentCoord.y + 1),
											makeCoord(currentCoord.x - 1, currentCoord.y - 1),
											makeCoord(currentCoord.x + 1, currentCoord.y - 1),
											makeCoord(currentCoord.x - 1, currentCoord.y + 1)
											
											
										}
			
			--local blockers = TheSim:FindEntities(currentPoint.x, currentPoint.y, currentPoint.z, 1.5 * PATH_NODE_DIST, {"blocker"})
			-- Process Candidates
			for point=1,8,1 do
			--for point=1,4,1 do 
				local nextCoord = candidatePoints[point]
				local nextPoint = coordToPoint(origin, nextCoord)
			
				if CheckWalkableFromPoint(currentPoint, nextPoint, search.pathcaps)
					--and CheckLOSFromPoint(currentPoint, nextPoint, blockers)
				then
												
					-- Update G scores
					
					-- walk on the road first and on the creep last
-- 					local is_onroad = search.groundcaps.speed_on_road and (RoadManager ~= nil and RoadManager:IsOnRoad(nextPoint.x, 0, nextPoint.z) or TheWorld.Map:GetTileAtPoint(nextPoint.x, 0, nextPoint.z) == WORLD_TILES.ROAD) or false
-- 					local is_oncreep = search.groundcaps.speed_on_creep and (TheWorld.GroundCreep:OnCreep(nextPoint.x, 0, nextPoint.z)) or false
-- 					local is_on_faster_tiles = search.groundcaps.faster_on_tiles and search.groundcaps.faster_on_tiles[tostring(TheWorld.Map:GetTileAtPoint(nextPoint.x, 0, nextPoint.z))]

					local new_direction = (nextPoint - currentPoint):GetNormalized()
					local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] +  calcCost(currentPoint, nextPoint) * calcGroundSpeedMulti(nextPoint, search.groundcaps) * calcDirectionMulti(new_direction, search.direction_so_far[currentCoord.x][currentCoord.y])
					
					--local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] +  PATH_NODE_DIST 
					
					if visited(search, nextCoord) or new_cost < search.g_score_so_far[nextCoord.x][nextCoord.y] then
						
						search.g_score_so_far[nextCoord.x][nextCoord.y] = new_cost
						search.direction_so_far[nextCoord.x][nextCoord.y] = new_direction
						nextCoord.f_score = new_cost + calcCost(nextPoint, search.endPos)
						--DebugPrint("[A STAR PATHFINDER] : " .. "f: "..nextCoord.f_score)
						pushIntoOpenList(search, nextCoord)
						search.came_from[nextCoord] = currentCoord
						
						--DebugPrint("[A STAR PATHFINDER] : " .. string.format("(%d,%d)-->(%d,%d)",currentCoord.x,currentCoord.y,nextCoord.x,nextCoord.y))
						
						-- Update work done
						workDone = workDone + 1
					end
				-- else
					-- visited(search, nextCoord)
					-- search.g_score_so_far[nextCoord.x][nextCoord.y] = math.huge
				end
			end
			
			
			-- Check work
			if workDone > workPerRound then
				search.totalWorkDone = search.totalWorkDone + workDone
				-- if reach the max work , just give up
				if search.totalWorkDone < (maxWork or PATH_MAX_WORK) then
					return false	-- another try in next round
				else 
					DebugPrint("[A STAR PATHFINDER] : " .. "forcestop because max tracked amount reached, we have tracked points:" .. search.totalWorkDone)
					return true		-- too many tries, forcestop
				end
			end
	end
	
	----------------------------
	-- Fail in Pathfinding !! --
	----------------------------

	-- No path found ,it happens when you didn't set a max work and it will track all the map.
	if search.path == nil then
		DebugPrint("[A STAR PATHFINDER] : " .. "we have tracked all the map! no path found !")
		return true
	end
	
end

return
{
	requestSearch = requestSearch,
	processSearch = processSearch
}