-- Thanks for the tutorial of A Star : https://www.redblobgames.com/pathfinding/a-star/introduction.html
-- And a very nice article： https://www.gamedev.net/reference/articles/article2003.asp
-- 他的中文译版： https://blog.csdn.net/kenkao/article/details/5476392
-- And the Coordinate system of trailblazer mod： https://steamcommunity.com/sharedfiles/filedetails/?id=810372558
-- Written by 川小胖
---------------------
-- For DebugPrint  --
---------------------
local DEBUG_MODE = false

local function DebugPrint(...)
	return DEBUG_MODE and print(...)
end
---------------------
----- Variables -----
---------------------

-- global vars so they can be used in other files
-- define of groundtile speed multiplier
ASTAR_SPEED_FASTER = 1
ASTAR_SPEED_NORMAL = 0
ASTAR_SPEED_SLOWER = -1

-- cost multi of groundtile
ASTAR_COSTMULTI_FASTER = 0.5 --0.5
ASTAR_COSTMULTI_NORMAL = 1
ASTAR_COSTMULTI_SLOWER = 2  --2

-- cost multi of direction change
local ASTAR_COSTMULTI_DIRECTION = 2  --Deprecated

-- cost multi of angle difference
local ASTAR_COSTMULTI_ANGLE = 1.5  -- 1 ~ 2,  FASTER (0.5) < NORMAL (1) <= FASTER*ANGLE (0.5*2)

-- 栅格/采样节点的距离间隔
-- Distance between pathfinding nodes
local PATH_NODE_DIST = 4
local PATH_NODE_DIST_SQ = PATH_NODE_DIST * PATH_NODE_DIST

-- 最大的工作量（即一共访问的点数量），达到后强制停止寻路
-- pathfinding will forcestop when it reach the max work amount
local PATH_MAX_WORK = 15000

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

-- see https://www.gamedev.net/reference/articles/article2003.asp -- chapter"Notes on Implementation" -- Point 7

------------------------
-- OpenList Functions --
------------------------
local BinaryHeap = require("utils/binaryheap")

--- COST FUNCTIONS
-- 计算损失值，哈夫曼距离主要用于4方向，对角线距离用于8方向
-- calc the cost of G scores and F scores , F = G + H
-- when we consider four directions ,better to use Manhattan distance
-- when we consider eight directions ,better to use Diagnol distance
local calcCost = function(p1, p2)
	-- Manhattan distance
	--return math.abs(p1.x - p2.x) + math.abs(p1.z - p2.z)
	
	-- Diagnol distance 
	local dx = math.abs(p1.x - p2.x)
	local dz = math.abs(p1.z - p2.z)
	local min_xz = math.min(dx,dz)
	return dx + dz - 0.5 * min_xz  --0.5 means is approximately equal to (2- sqrt(2))
end


-- 计算地面速度乘数，通过减小在卵石路上的G值可以优先考虑卵石路上的点，达到跟随卵石路的效果
-- 同样通过增大蜘蛛网上的G值可以尽量避免走到蜘蛛网上，（Webber则是加速）
local calcGroundSpeedMulti = function(point, groundcaps)
    --NO GROUNDCAPS SETTINGS
    if groundcaps == nil then return ASTAR_COSTMULTI_NORMAL end

	--FLOOD (island adventure Mod)
	-- if groundcaps.speed_on_flood ~= nil then
	-- 	local is_onflood = TheWorld.components.flooding ~= nil and TheWorld.components.flooding.OnFlood and
	-- 							TheWorld.components.flooding:OnFlood(point.x, 0, point.z)
	-- 	if is_onflood then
    --         if groundcaps.speed_on_flood < ASTAR_SPEED_NORMAL then
    --             return ASTAR_COSTMULTI_SLOWER
    --         elseif groundcaps.speed_on_flood > ASTAR_SPEED_NORMAL then
    --             return ASTAR_COSTMULTI_FASTER
    --         end
	-- 	end
	-- end

    --CREEP (actually it should check the walkable between points instead of walkable of point, but it should be okay since creep always fill a tile)
    if groundcaps.speed_on_creep ~= nil then
        local is_oncreep = TheWorld.GroundCreep:OnCreep(point.x, 0, point.z) -- CheckWalkableFromPoint(curpoint, point, {ignorewalls = true, allowocean = true, ignorecreep = false})
        -- should walk around the spidernet evenif it's on road or faster tiles
        if is_oncreep then
            if groundcaps.speed_on_creep < ASTAR_SPEED_NORMAL then
                return ASTAR_COSTMULTI_SLOWER
            elseif groundcaps.speed_on_creep > ASTAR_SPEED_NORMAL then
                return ASTAR_COSTMULTI_FASTER
            end
        end
    end

    --ROAD
	local current_ground_tile = TheWorld.Map:GetTileAtPoint(point.x, 0, point.z)
    if groundcaps.speed_on_road ~= nil then
        local is_onroad = RoadManager ~= nil and RoadManager:IsOnRoad(point.x, 0, point.z) or
                            --current_ground_tile == WORLD_TILES.ROAD
							GROUND_ROADWAYS ~= nil and GROUND_ROADWAYS[current_ground_tile]
        if is_onroad then
            -- nobody will walk slower on road but just in case
            if groundcaps.speed_on_road < ASTAR_SPEED_NORMAL then
                return ASTAR_COSTMULTI_SLOWER
            elseif groundcaps.speed_on_road > ASTAR_SPEED_NORMAL then
                return ASTAR_COSTMULTI_FASTER
            end
        end
    end
    --FASTER TILES
    if groundcaps.faster_on_tiles ~= nil then
        if groundcaps.faster_on_tiles[tostring(current_ground_tile)] then
            return ASTAR_COSTMULTI_FASTER
        end
    end
    return ASTAR_COSTMULTI_NORMAL
end

-- 计算方向变化乘数，方向变化的点损失值更大，从而达到平滑路径的效果
-- less cost of G scores in same direction and more cost in different direction 
-- it's another method to smooth the path
local calcDirectionMulti = function(nextCoord_direct, currentCoord_direct)
    --return 1
	return (1 * (nextCoord_direct == currentCoord_direct and 1 or ASTAR_COSTMULTI_DIRECTION))
end


-- 计算角度变化乘数, 与上类似，但是按角度分段
local calcAngleMulti = function(nextCoord_direct, currentCoord_direct)
	local nextCoord_angle = VecUtil_GetAngleInRads(nextCoord_direct.x, nextCoord_direct.z)
	local toDest_degree = VecUtil_GetAngleInRads(currentCoord_direct.x, currentCoord_direct.z)
	--DebugPrint(1+ (ASTAR_COSTMULTI_ANGLE-1) * math.abs(nextCoord_angle - toDest_degree)/(2*PI))
	return 1+ (ASTAR_COSTMULTI_ANGLE-1) * math.abs(nextCoord_angle - toDest_degree)/(2*PI)
end


-- 陆地和浅海交界处，浅海地皮会伸出 1/4区域 的陆地，overhang区因为算浅海地皮，和陆地没有LOS
-- overhang area means the extend area that near the shallow ocean, it's belong as shallow ocean tile
local IsOverhangAtPoint = function(x, y, z)
	if type(x) == "table" and x.IsVector3 ~= nil and x:IsVector3() then
		x, y, z = x:Get()
	end
	return not TheWorld.Map:IsAboveGroundAtPoint(x, y, z) and TheWorld.Map:IsVisualGroundAtPoint(x, y, z)
end

-- 单点可走
-- walkable of one point(on ocean land tile, creep, walls, flood)
local function IsWalkablePoint(point, pathcaps)
	pathcaps = pathcaps or {allowocean = false, ignoreLand = false, ignorewalls = false, ignorecreep = false}

	-- check ocean and Land
	if not pathcaps.allowocean or pathcaps.ignoreLand then
		local is_onland = TheWorld.Map:IsVisualGroundAtPoint(point.x, 0, point.z)
		if not pathcaps.allowocean and not is_onland then -- not allow ocean but actually on ocean
			return false
		end
		if pathcaps.ignoreLand and is_onland then -- not allow land but actually on land
			return false
		end
	end
	-- check the creep
	if not pathcaps.ignorecreep then
		local is_oncreep = TheWorld.GroundCreep:OnCreep(point.x, 0, point.z)
		if is_oncreep then
			return false
		end
	end
	-- DEPRECATED, see bypass prefab defs "network_flood"
	-- -- check the flood
	-- if not pathcaps.ignoreflood then
	-- 	local is_onflood = TheWorld.components.flooding ~= nil and TheWorld.components.flooding.OnFlood and
	-- 							TheWorld.components.flooding:OnFlood(point.x, 0, point.z)
	-- 	if is_onflood then
	-- 		return false
	-- 	end
	-- end

	-- check the walls
	if not pathcaps.ignorewalls then
		local has_wall = TheWorld.Pathfinder:HasWall(point.x, 0, point.z)
		if has_wall then
			return false
		end
	end


	return true
end

-- 两点之间采样检测连通性 FIXME: diagonal direction walls can't be checked normally 
-- it's so expensive to check tiles walkable between points with long distance
local function SamplingCheckWalkable(pos, target_pos, pathcaps, sampling_dist)
	local vec, len = (target_pos - pos):GetNormalizedAndLength()
	local pathcaps = pathcaps or {}
	local sampling_dist = sampling_dist or (TILE_SCALE / 5)
	if len > sampling_dist then -- the points dist smaller than sampling_dist, just skip
		local i = sampling_dist
		while(i < len) do
			local checkPos = pos + vec*i
			if not IsWalkablePoint(checkPos, pathcaps) then
				return false
			end
			i = i + sampling_dist
		end
	end
	return true
end

-- 检测两点连通性， 先用C接口检测，再手动检测某些可能连通的情况
-- check the LOS and potiental LOS
local function CheckWalkableFromPoint(pos, target_pos, pathcaps, without_check_potiental_walkable)
	local pathcaps = pathcaps or {ignorewalls = false,  ignorecreep = false, ignoreLand = false, allowocean = false, }
	-- precheck
	if pos == target_pos then
		return true
	end

	--------------------------------------------
	--[[ check flood individually for island adventure world]]
	-- DEPRECATED, see bypass prefab defs "network_flood"
	--------------------------------------------
	-- if not pathcaps.ignoreflood then
	-- 	local check_flood_pathcaps = {ignorewalls = true, ignorecreep = true, allowocean = true}
	-- 	local is_sampledpos_no_flood = SamplingCheckWalkable(pos, target_pos, check_flood_pathcaps)
	-- 	if not is_sampledpos_no_flood then
	-- 		return false, "flood blocked"
	-- 	end
	-- end

	--------------------------------------------
	--[[ C side interface to check LOS ]]
	--------------------------------------------
	-- the C side pathfinder result
	-- this interface don't check the flood, diagonal tile connection points ,overhang points and fake ocean tiles area points
	local hasLOS = TheWorld.Pathfinder:IsClear(
			pos.x, pos.y, pos.z,
			target_pos.x, target_pos.y, target_pos.z,
			pathcaps
	)
	if hasLOS == true then
		return true
	end

	if without_check_potiental_walkable then
		return false, "IsClear return false"
	end

	-- when reach here, IsClear return false
	-- we are going to check diagonal tile connection points and overhang points and the points at void of Cave
	
	-- ABOUT POINTS ON ONLY Diagonal TILES CONNECTIONS:
	-- https://forums.kleientertainment.com/forums/topic/147232-the-issue-about-pathfinderisclear-on-tile-connection-in-diagonal-direction/
	-- when the points are in diagonal tile connection,IsClear(pathcaps={allowocean=false}) return false
	-- they can be actually walk through,so we should take account of it

	-- ABOUT POINTS ON OVERHANGE AREA:
	-- overhang area means the extra 1/4 TILE_SCALE visual ground area generated because of two different tiles connection
	-- IsClear(pathcaps={allowocean=false}) interface return false if one of points is at overhang area(allowocean = false)
	
	-- ABOUT POINT AT VOID OF CAVE:
	-- IsClear(pathcaps={allowocean=true}) return false when one of the points is at outbound tiles(fake ocean tiles) in the no ocean world (eg: Cave)
	-- to handle this we should take the points on outbound tiles in to account 
	--------------------------------------------
	--[[ check points with Diagonal Direction or At Overhang ]]
	--------------------------------------------
	if not pathcaps.allowocean then -- only land allowed only should we check the diagonal direction points and overhang points 
		local is_overhang = IsOverhangAtPoint(pos.x, pos.y, pos.z) or IsOverhangAtPoint(target_pos.x, target_pos.y, target_pos.z)
		local tile_x1, tile_y1 = TheWorld.Map:GetTileCoordsAtPoint(pos.x, pos.y, pos.z)
		local tile_x2, tile_y2 = TheWorld.Map:GetTileCoordsAtPoint(target_pos.x, target_pos.y, target_pos.z)
		local abs_dir_x, abs_dir_y = math.abs(tile_x1 - tile_x2), math.abs(tile_y1 - tile_y2)
		local is_diagonal_dir = (abs_dir_x > 0 and abs_dir_y > 0) and (abs_dir_x == abs_dir_y)
		if not is_diagonal_dir and not is_overhang then
			return false, "not at diagonal direction or overhang"
		end
	end


	--------------------------------------------
	--[[ check walkable at points]]
	--------------------------------------------

	local is_points_both_walkable = IsWalkablePoint(pos, pathcaps) and IsWalkablePoint(target_pos, pathcaps)
	if not is_points_both_walkable then
		return false, "not both walkable points"
	end

	--------------------------------------------
	--[[ check walls and creep between points(only works in world with ocean)]]
	--------------------------------------------
	-- set allowocean to exclude the ocean tile factor
	-- it's unfit for world has not ocean(eg: the cave) to set allowocean flag in order to check walls individually, it always return no LOS

	local world_has_ocean = TheWorld.has_ocean
	local skip_allowocean_check = not world_has_ocean

	if not skip_allowocean_check and not (pathcaps.ignorewalls and pathcaps.ignorecreep) then
		-- set allowocean to check walls and creep
		local check_pathcaps = shallowcopy(pathcaps)
		check_pathcaps.allowocean = true

		local walkable_exclude_oceanlandlimits = TheWorld.Pathfinder:IsClear(
						pos.x, pos.y, pos.z,
						target_pos.x, target_pos.y, target_pos.z,
						check_pathcaps
				)
		if not walkable_exclude_oceanlandlimits then
			return false, "walls or creep blocked"
		end
	end
	-- Check Completion:
	--- Diagonal Direction Points(allowocean = false):
	---- FOREST WORLD|| walls:√ 		creep:√ 	flood:√ 	oceanlandlimits:×
	---- CAVE   WORLD|| walls:× 		creep:× 	flood:√ 	oceanlandlimits:×
	--- Overhang Area Points:(allowocean = false):
	---- FOREST WORLD|| walls:√ 		creep:√ 	flood:√ 	oceanlandlimits:×
	---- CAVE   WORLD|| walls:× 		creep:× 	flood:√ 	oceanlandlimits:×
	--- Void Tiles Points:(allowocean = true):
	---- CAVE   WORLD|| walls:× 		creep:× 	flood:√ 	oceanlandlimits:×
	--------------------------------------------
	--[[ check sampled pos walkable(oceanlandlimits, creep, walls, )]]
	--------------------------------------------
	-- it's so expensive to check sampled pos for points with long distance, only use it if no other choice

	--take some samples point and check if is on land,to handle the two points are both at one of overhang area in same tile
	--check some point to ensure the connection between tiles
	local check_pathcaps = shallowcopy(pathcaps)
	if world_has_ocean then
		check_pathcaps.ignorewalls = true
		check_pathcaps.ignorecreep = true
		-- check_pathcaps.ignoreflood = true
	else
		-- check_pathcaps.ignoreflood = true
	end
	local is_sampledpos_walkable = SamplingCheckWalkable(pos, target_pos, check_pathcaps)
	if not is_sampledpos_walkable then
		return false, "sampled pos not walkable"
	end

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
	table.insert(path.steps, pointToStep(search.original_endPos))
	if search.endPos ~= search.original_endPos and not CheckWalkableFromPoint(search.endPos, search.original_endPos, search.pathcaps)
		and search.endPos ~= search.startPos then
	    table.insert(path.steps, pointToStep(search.endPos))
	end

	local lastDirection = finalPoint - search.endPos
	local currentCoord = finalCoord
	local lastCoord = currentCoord
	while(currentCoord.x ~= 0 or currentCoord.y ~= 0) do -- util the startcoord (0,0)
		local currentDirection = search.direction_so_far[currentCoord.x][currentCoord.y]
		-- In order to simplify the path, only the steps with different direction will be added
		if currentDirection ~= lastDirection   then
			local worldPoint = coordToPoint(search.startPos, currentCoord)
			--local point = Vector3(worldVec:Get()) It's Wrong!
			-- Notice: the step is a table of {x,y,z}, not Vector3
			-- to keep the same with klei's pathfinding result format
			local step = pointToStep(worldPoint)
			table.insert(path.steps, step)
		end
		lastDirection = currentDirection
		lastCoord = currentCoord
		currentCoord = search.came_from[currentCoord]
	end
	-- CurrentCoord == startCoord(0,0) when reach here 
	local pointNextStartPos = coordToPoint(search.startPos, lastCoord)
	if search.original_startPos ~= search.startPos and not CheckWalkableFromPoint(search.original_startPos, search.startPos, search.pathcaps) then
		table.insert(path.steps, pointToStep(search.startPos))
	end
	table.insert(path.steps, pointToStep(search.original_startPos))
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
	local check_pathcaps = shallowcopy(search.pathcaps)
	-- reset the ignorecreep = false , to test whether the point can help me avoid the creep
	if search.groundcaps.speed_on_creep and search.groundcaps.speed_on_creep < 0 then
		check_pathcaps.ignorecreep = false
	end
	---- DEPRECATED, see bypass prefab defs "network_flood"
	-- -- reset the ignoreflood = false , to test whether the point can help me avoid the flood
	-- if search.groundcaps.speed_on_flood and search.groundcaps.speed_on_flood < 0 then
	-- 	check_pathcaps.ignoreflood = false
	-- end

	while(index < #(path.steps)) do
    
		-- Points to test
		local pre = path.steps[index-1]
		local post = path.steps[index+1]
		local cur = path.steps[index]

		local prePoint, curPoint, postPoint = stepToPoint(pre), stepToPoint(cur), stepToPoint(post)
		local is_on_speedup_turf = calcGroundSpeedMulti(curPoint, search.groundcaps) < ASTAR_COSTMULTI_NORMAL --ASTAR_COSTMULTI_FASTER

        -- dont remove the points that on speedup_turf even if they're have LOS with previous point
		if CheckWalkableFromPoint(prePoint, postPoint, check_pathcaps) and
			 (not is_on_speedup_turf ) then -- Has LOS
			table.remove(path.steps, index)
		else -- No LOS
			index = index + 1
		end
	end
	return path

end



-- 找自身和附近地皮的Walkable中心点
-- find the walkable center point  from self tile and nearby tiles
-- to avoid the situation when point is overhang that hasnoLOS with any other points
local function FindNearbyWalkableCenterPoint(point, pathcaps, check_los)
	local x, y, z = point:Get()
	local is_landtile = TheWorld.Map:IsVisualGroundAtPoint(x, y ,z)
	if not is_landtile then return nil end

	--local is_overhang = is_landtile and not TheWorld.Map:IsAboveGroundAtPoint(x, y, z)
	--local with_checklos = not is_overhang

	local resultCenterPoint = nil

	local currentTileCenterPoint = Vector3(TheWorld.Map:GetTileCenterPoint(x, y, z))
	-- consider current tile first
	if not check_los and IsWalkablePoint(currentTileCenterPoint, pathcaps) or CheckWalkableFromPoint(point, currentTileCenterPoint, pathcaps) then
		resultCenterPoint = currentTileCenterPoint
	else
		-- consider nearby tiles next
		local breakFlag = false
		for dx= -1, 1 ,1 do
			for dz = -1, 1, 1 do
				local nearbyTileCenterPoint = currentTileCenterPoint+Vector3(dx, 0, dz)*TILE_SCALE
				if not check_los and IsWalkablePoint(nearbyTileCenterPoint, pathcaps) or CheckWalkableFromPoint(point, nearbyTileCenterPoint, pathcaps) then
					resultCenterPoint = nearbyTileCenterPoint
					breakFlag = true
					break
				end
			end
			if breakFlag then
				break
			end
		end
	end

	if resultCenterPoint == nil then
		DebugPrint("no fitable point")
	end

	return resultCenterPoint or nil
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

	-- LOS parameter
	search.pathcaps = pathcaps and shallowcopy(pathcaps) or {}
	search.pathcaps.player = true

	-- better to set it in pathfollower
	-- i have set the penalty factor for creep and flood in calcGroundSpeedMulti
	search.pathcaps.ignorecreep = true
	-- search.pathcaps.ignoreflood = true


	---- handle the case that one of points is on the tile which pathfinding not allow, just early quit
	--check obviously no way to avoid unnecessary resource waste
    if not(IsWalkablePoint(startPos, search.pathcaps) and IsWalkablePoint(endPos, search.pathcaps)) then -- obviously no path
		search.path = {} -- early quit and finish with no way
		return search
	end

	search.groundcaps = groundcaps and shallowcopy(groundcaps) or {speed_on_road = nil, speed_on_creep = nil, faster_on_tiles = {}}-- nil means not consider road and creep

	-- perserve the real start and end position
    search.original_startPos = Vector3(startPos:Get())
    search.original_endPos = Vector3(endPos:Get())

	-- 2023.8.10: merge it to FindNearbyWalkableCenterPoint without check_los
	------ handle the case that points has wall , try to override it as nearby no wall point, otherwise early quit
	---- override the endPos as searching the nearby point if dest has wall
	--if not search.pathcaps.ignorewalls and not is_point_without_wall(endPos) then
	--	local inv_dir = startPos - endPos
	--	local start_angle = VecUtil_GetAngleInDegrees(inv_dir.x, inv_dir.z)
	--	local fitable_override_point = SearchNearbyPointWithoutWall(endPos, start_angle, TILE_SCALE, 8)
	--	if fitable_override_point ~= nil then
	--		endPos = fitable_override_point
	--	else -- obviously no path
	--		search.path = {}
	--		return search
	--	end
	--end

    ---- try to standardization and handle the case that points are at overhang area
    -- there'll be some issue without standardization in some case ,such as when the points in diagonal tile connection
    -- in some other case it failed to standardization and maybe okay to pathfinding with origin point
	search.startPos = FindNearbyWalkableCenterPoint(startPos, pathcaps, true) or search.original_startPos
	search.endPos   = FindNearbyWalkableCenterPoint(endPos, pathcaps) or search.original_endPos

	-------------------------
	-- Prepare Pathfinding --
	-------------------------
	
	-- 就算是HasLos，我们也应该处理一下让它尽可能顺着卵石路走
	-- we should process it to follow the road even if it has LOS yet
	
	
	-- Has LOS, return line
	-- if TheWorld.Pathfinder:IsClear	(
											-- search.startPos.x, search.startPos.y, search.startPos.z,
											-- search.endPos.x,   search.endPos.y,   search.endPos.z,
											-- search.pathcaps
										-- )
	-- then
		-- -- just walk straight
		-- search.path = {steps = {pointToStep(startPos), pointToStep(endPos)}}
		
	-- else
		-- No LOS, prepare pathfinding
		
		-- search variable init
		-- search.openlist = { } 			-- 1 dim array, coord as element (use binary search to maintain sorted list)
		search.openlist = BinaryHeap:new()	-- use binary heap for optimalize
		search.closedlist = { }			-- 2 dim array, coord's x,y as index, bool as element
		search.g_score_so_far = { }		-- 2 dim array, coord's x,y as index, number as element
		search.direction_so_far = { }	-- 2 dim array, coord's x,y as index, Vector3 as element
		search.came_from = { }			-- linkedlist , coord as element
		
		search.path = nil
		search.openlist:push(makeCoord(0,0,0))
		search.g_score_so_far[0]={}
		search.g_score_so_far[0][0] = 0
		
		search.direction_so_far[0]={}
		search.direction_so_far[0][0] = Vector3(0,0,0)
		-- search info init
		search.totalWorkDone = 0
		search.startTime = os.clock() --[[GetTime() ]]
	--end
	
	return search
end

-- 处理搜索，放在PeriodicTask或者OnUpdate，输入是每轮的最大处理量，
-- 如果找到返回true，结果放在search.path里
-- 如果运行到超过最大量则返回false，因此应该放在PeroidicTask或者OnUpdate里，反复继续上次的执行，这种少量分次运行应该能更好处理中止
-- @param search 		 : The search to finish (request one via requestSearch)
-- @param workPerRound   : The number of point track pertime
-- @param maxWork        : The search will process util reach the maxWork amount
-- @return    			 : true if search is over (path == nil means not found path, path is valid means we found it), false if reach the workPerRound you set
local processSearch = function(search, timePerRound, maxTime)

	-- Path already found, return
	if search.path ~= nil then
		return true
	end
	
	-- Cache parameters
	local origin = search.startPos
	
	-- Paths processed this run
	local workDone = 0
	local round_start_time = os.clock()
	-- Process until finished (no search.openlist remain or a path is found)
	while not search.openlist:isEmpty() do
		
		-- get the coord of min F value
		local currentCoord = search.openlist:pop()
		search.closedlist[currentCoord.x] = search.closedlist[currentCoord.x] or {}
		search.closedlist[currentCoord.x][currentCoord.y] = true

		local currentPoint = coordToPoint(origin, currentCoord)
		
		---------------------------------
		-- Successed in Pathfinding !! --
		---------------------------------
		--pathfinding finish

		-- NOTE: should checkCost first because Check Long Distance Points Walkable is so expensive
		if calcCost(currentPoint, search.endPos) <= PATH_NODE_DIST
				and CheckWalkableFromPoint(currentPoint, search.endPos, search.pathcaps) then
			
			DebugPrint("[A STAR PATHFINDER] : " .. "start generate path！")

			-- make path with some smooth feature via only preserve the points with different direction
			-- and we penalized the points which with change of direction (see function calcDirectionMulti)
			search.path = makePath(search, currentCoord)

			search.path = smoothPath(search)

			-- update info
			search.endTime = os.clock() --[[GetTime() ]]
			search.costTime = search.endTime - search.startTime
			DebugPrint("[A STAR PATHFINDER] : " .. "finish pathfinding !, cost time: " .. search.costTime .. ",tracked points :" .. search.totalWorkDone )
			return true
		end
		
			-- Candidate coordinates, 8 directions
			local neighborCoordinates = 	{
											makeCoord(currentCoord.x    , currentCoord.y + 1),							
											makeCoord(currentCoord.x + 1, currentCoord.y	),
											makeCoord(currentCoord.x 	, currentCoord.y - 1),
											makeCoord(currentCoord.x - 1, currentCoord.y 	),
											makeCoord(currentCoord.x + 1, currentCoord.y + 1),
											makeCoord(currentCoord.x - 1, currentCoord.y - 1),
											makeCoord(currentCoord.x + 1, currentCoord.y - 1),
											makeCoord(currentCoord.x - 1, currentCoord.y + 1)
											
											
										}
			-- Process Candidates
			for _, coordinate in ipairs(neighborCoordinates) do
				local nextCoord = coordinate
				local nextPoint = coordToPoint(origin, nextCoord)
			
				if not (search.closedlist[nextCoord.x] and search.closedlist[nextCoord.x][nextCoord.y]) and -- not in closed list
					CheckWalkableFromPoint(currentPoint, nextPoint, search.pathcaps) then	-- walkable between two points
					-- Update G scores

					-- walk on the road first and on the creep last
					-- 					local is_onroad = search.groundcaps.speed_on_road and (RoadManager ~= nil and RoadManager:IsOnRoad(nextPoint.x, 0, nextPoint.z) or TheWorld.Map:GetTileAtPoint(nextPoint.x, 0, nextPoint.z) == WORLD_TILES.ROAD) or false
					-- 					local is_oncreep = search.groundcaps.speed_on_creep and (TheWorld.GroundCreep:OnCreep(nextPoint.x, 0, nextPoint.z)) or false
					-- 					local is_on_faster_tiles = search.groundcaps.faster_on_tiles and search.groundcaps.faster_on_tiles[tostring(TheWorld.Map:GetTileAtPoint(nextPoint.x, 0, nextPoint.z))]

					local new_direction = (nextPoint - currentPoint):GetNormalized()

					local cost = calcCost(currentPoint, nextPoint)
					local groundSpeedMulti = calcGroundSpeedMulti(nextPoint, search.groundcaps)
					if groundSpeedMulti < ASTAR_COSTMULTI_NORMAL then  -- ASTAR_COSTMULTI_FASTER
						groundSpeedMulti = groundSpeedMulti * calcAngleMulti(new_direction, search.direction_so_far[currentCoord.x][currentCoord.y])
					end

					--local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] +  PATH_NODE_DIST
					--local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] +  calcCost(currentPoint, nextPoint) * calcGroundSpeedMulti(nextPoint, search.groundcaps) * calcDirectionMulti(new_direction, search.direction_so_far[currentCoord.x][currentCoord.y])
					--local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] +  calcCost(currentPoint, nextPoint) * calcGroundSpeedMulti(nextPoint, search.groundcaps) * calcAngleMulti(new_direction, search.direction_so_far[currentCoord.x][currentCoord.y])
					local new_cost = search.g_score_so_far[currentCoord.x][currentCoord.y] + cost * groundSpeedMulti

					search.g_score_so_far[nextCoord.x] = search.g_score_so_far[nextCoord.x] or {}
					search.direction_so_far[nextCoord.x] = search.direction_so_far[nextCoord.x] or {}

					if search.g_score_so_far[nextCoord.x][nextCoord.y] == nil or new_cost < search.g_score_so_far[nextCoord.x][nextCoord.y] then
						search.g_score_so_far[nextCoord.x][nextCoord.y] = new_cost
						search.direction_so_far[nextCoord.x][nextCoord.y] = new_direction
						nextCoord.f_score = new_cost + calcCost(nextPoint, search.endPos)
						--DebugPrint("[A STAR PATHFINDER] : " .. "f: "..nextCoord.f_score)
						if not search.openlist:contains(nextCoord) then
							search.openlist:push(nextCoord)
						else
							search.openlist:update(nextCoord)
						end
						search.came_from[nextCoord] = currentCoord

						--DebugPrint("[A STAR PATHFINDER] : " .. string.format("(%d,%d)-->(%d,%d)",currentCoord.x,currentCoord.y,nextCoord.x,nextCoord.y))

						-- Update work done
						--workDone = workDone + 1
						search.totalWorkDone = search.totalWorkDone + 1
					end
				end
			end
			
			
			-- Check work
			local time = os.clock()
			if time - round_start_time > timePerRound then
				--search.totalWorkDone = search.totalWorkDone + workDone
				-- if reach the max work , just give up
				if time - search.startTime < maxTime then
					--print(os.clock() - round_start_time)
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
	processSearch = processSearch,
	-- extra functions for astarpathfinder
	CheckWalkableFromPoint = CheckWalkableFromPoint,
	IsWalkablePoint = IsWalkablePoint,
	calcGroundSpeedMulti = calcGroundSpeedMulti,
}