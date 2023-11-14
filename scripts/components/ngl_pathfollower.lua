require("utils/step_util")
require("utils/bit_operate_util")

-- 发送左键点击RPC的最远距离，超出会发送RPC失败
local SERVER_LEFTCLICK_DIST_SQ = 4096 --64*64
-- 为了让子路径搜索时能够加载到下一个节点附近是否有寻路墙，让最大的节点距离更接近屏幕加载距离
--make it closer to the entities loading range to make the subsearch can check all the obstacles
local MAX_STEP_DIST = 40
local MAX_STEP_DIST_SQ = MAX_STEP_DIST * MAX_STEP_DIST
-- 路径搜索的状态
-- the status of pathsearch
local STATUS_CALCULATING = 0
local STATUS_FOUNDPATH = 1
local STATUS_NOPATH = 2

-- 提前一小段距离视为到达，关闭延迟补偿会有大概1帧的延迟，所以会更大
-- 并且距离理应和速度有关，但速度似乎很难获取，特别是关闭延迟补偿时 locomotor被移除
--should adjust them according to the player's speed, increase them when high speed
local FORCESTOP_OFFSET = 2
local ARRIVESTEP_MOVEMENTPREDICT_ENABLED = 0
local ARRIVESTEP_MOVEMENTPREDICT_DISABLED = 1.5 --主要是提前切换到下一个点防止一段一段走的视觉上卡顿

-- 移动模式，具体在locomotor的Update里触发
-- 左键点击模式：RPC.LEFTCLICK，最后调用服务器端的locomotor:GoToPoint()，会触发官方的寻路,可用于refine，但当鼠标上附带物品时，由于左键动作变为Drop不再是WalkTo，无法移动
-- 直线行走模式：RPC.DirectWalk,在playercontroller:OnUpdate中调用服务器端的locomotor:RunInDirection()，仅直走
-- move mode
local MOVEMODE_LEFTCLICK = 0	-- via Remote Call locomotor:GoToPoint(), ACTONS.WALKTO actually
local MOVEMODE_DIRECTWALK = 1	-- via Remote Call locomotor:RunInDirection()

-- 用做A星算法的加减速地皮，例如卵石路加速，蜘蛛网减速
-- groundcaps setting for astar pathfinder
local ASTAR_SPEED_FASTER = 1
local ASTAR_SPEED_NORMAL = 0
local ASTAR_SPEED_SLOWER = -1

-- 在DIRECTWALK模式可能因为碰撞或其他原因偏移路径（LEFTCLICK模式下本身会寻路且紧跟路径），需要检测是否偏移（见redirect_fn2），重新矫正方向
-- only beyond this distance should we correct direction in DIRECTWALK movemode
local REDIRECT_DIST = 1

-- 有效的路径，至少要有两个step，起点和终点
local function IsValidPath(path)
	return path ~= nil and path.steps and #path.steps >= 2
end

-- 点与直线的距离
-- the distance between point and line of two points
local function getDistFromPointToLine(point, linePoint1, linePoint2)
	local x0,y0 = point.x, point.z
	local x1,y1 = linePoint1.x, linePoint1.z
	local x2,y2 = linePoint2.x, linePoint2.z
	return math.abs( (x2-x1)*(y0-y1) - (y2-y1)*(x0-x1) ) / math.sqrt((x2-x1)*(x2-x1) + (y2-y1)*(y2-y1))
end

-- 距离路径超出REDIRECT_DIST，矫正方向
-- we should correct the direction if we are far from the path in MOVEMODE_DIRECTWALK
local function redirect_fn2(inst)
	local self = inst.components.ngl_pathfollower
	if self.path == nil or self:GetMoveMode(true) ~= MOVEMODE_DIRECTWALK or not self:FollowingPath() then return end

	local path = self.path
	local player_pos = inst:GetPosition()
	player_pos.y = 0
	local curstep_pos = StepToVector3(path.steps[path.currentstep])
	local prestep_pos = StepToVector3(path.steps[path.currentstep - 1])
	if curstep_pos == prestep_pos then return end -- will result in a denominator of 0 when caculating the distance

	local dist = getDistFromPointToLine(player_pos, prestep_pos, curstep_pos)
	--print("TRAVEL: DIST - ",dist)
	if(dist > REDIRECT_DIST) then
		self:Move(curstep_pos)
	end
end



local PathFollower = Class(function(self, inst)
    self.inst = inst

	--self.movemode = MOVEMODE_DIRECTWALK
	self.debugmode = false
	self.debug_signs = nil

	self.dest = nil
	self.path = nil
	--self.arrive_step_dist = ARRIVE_STEP
	self.atdestfn = nil

	-- self.extra_check_interval = 5 * FRAMES
	-- self.extra_check_timer = 5 * FRAMES
	self.extra_check_fn = redirect_fn2

	self.waitsearchresult_task = nil
	self.followpath_task = nil
	self.check_arrival_for_directwalk_task = nil

	self.pathfinder = nil
	self.lua_pathfinder = nil
	self.lua_pathfinder_enabled = true -- only we do have lua pathfinder and enabled meanwhile, can we use it

	self.subsearch_enabled = false
	self.subsearch_info = {startstep = nil, endstep = nil} -- subsearch index of step

end)


local function CheckAndGetSearchResult(self)
	local pathfinder = self:GetCurrentPathfinder()
	local pathfinder_str = self.using_lua_pathfinder and "LUA" or "C"
	local search_over, validpath = false, nil
	local status = pathfinder and pathfinder:GetSearchStatus()
	if status ~= STATUS_CALCULATING then
		search_over = true
		local time = GetTime()
		if status == STATUS_FOUNDPATH then
			-- GET PATH RESULT
			local foundpath = pathfinder:GetSearchResult()
			if foundpath and IsValidPath(foundpath) then
				validpath = foundpath
				--print("get path, pathfinder ", pathfinder_str, " ,cost ", time - self.search_start_time)
			else
				--print("invalid path, pathfinder ", pathfinder_str, " ,cost ", time - self.search_start_time)
			end
			
		else
			if status == nil then
				-- LOST PATH SEARCH
				--print("lost search, pathfinder ", pathfinder_str, " ,cost ", time - self.search_start_time)
			else
				-- NO PATH
				--print("no path, pathfinder ", pathfinder_str, " ,cost ", time - self.search_start_time)
			end
		end
	end
	return search_over, validpath
end

-- 测试用，看看每两步之间是否超出RPC范围
-- just for debug to check the dest of each steps
local function checkDist(path)
	print(#path.steps)
	for index = 2,#(path.steps) do
		local pre = StepToVector3(path.steps[index-1])
		local current = StepToVector3(path.steps[index])
		local distsq = pre:DistSq(current)
		print(distsq)
		-- if distsq > SERVER_LEFTCLICK_DIST_SQ then -- out of range
			-- print("outofrange",distsq)
		-- end
	end
end

-- 用于设置路径前的预处理，确保路径里面两个step之间的距离在发送RPC的有效范围内（distsq < 4096），否则截断成两部分
-- make the distance between adjacent pathsteps in range of sendLeftClickRPC
-- it's unnecessary in DIRECTWALK Mode, but still should do it to handle the case when toggle to the LEFTCLICK Mode during the path following
local function PreprocessPath(self, path)
	-- 需要考虑一个情况：当寻路得到结果时，人物当前的位置可能和起始点因为移动存在一些偏差
	-- 可能会导致当前位置不再与第二个step连通,也可能不再在RPC发送范围内
	-- 这时需要把原点设置为角色位置，检查是否再连通，不连通则多一步为原来的起点
	-- to handle the case of this:
	-- https://forums.kleientertainment.com/klei-bug-tracker/dont-starve-together/a-rare-pathfind-bug-r40745/
	-- in that case, we may have shifted the position which is the startpos of pathsearch since maintaining the previous movement
	-- should recheck the los between second step and player's position and recheck the range of steps
	local cur_pt = self.inst:GetPosition()
	local pathcaps = self:GetPathCaps(true)
	local secondStep = path.steps[2]
	-- update the current playerpos as startpos
	local old_firstStep = path.steps[1]
	path.steps[1] = Vector3ToStep(cur_pt)

	local check_pathfinder = self:GetLuaPathfinder() or self:GetPathfinder()
	local cur_pt_hasLOS = check_pathfinder:IsClear(cur_pt, StepToVector3(secondStep), pathcaps)
	if not cur_pt_hasLOS and TheWorld.Map:IsVisualGroundAtPoint(old_firstStep.x, 0, old_firstStep.z) then
		table.insert(path.steps, 2, old_firstStep)
	end

	local index = 2
	while(index <= #(path.steps)) do
		local pre = StepToVector3(path.steps[index-1])
		local cur = StepToVector3(path.steps[index])
		if pre:DistSq(cur) > MAX_STEP_DIST_SQ + 4 then -- out of range, 4 is a small tolerance
			local inrange_pos = (cur - pre):GetNormalized()* (MAX_STEP_DIST)+pre
			table.insert(path.steps, index, Vector3ToStep(inrange_pos))
			--print("after split",StepToVector3(path.steps[index-1]):Dist(StepToVector3(path.steps[index])))
		else
			index = index + 1
		end
	end
	return path
end

-- see utils/astar_util:calcGroundSpeedMulti
local ASTAR_COSTMULTI_NORMAL = 1
local function IsPointOnFasterGround(lua_pathfinder, point, groundcaps)
	if lua_pathfinder and lua_pathfinder.CalcGroundSpeedMulti then
		return lua_pathfinder:CalcGroundSpeedMulti(point, groundcaps) < ASTAR_COSTMULTI_NORMAL
	end
	return false
end
local function IsPointOnSlowerGround(lua_pathfinder, point, groundcaps)
	if lua_pathfinder and lua_pathfinder.CalcGroundSpeedMulti then
		return lua_pathfinder:CalcGroundSpeedMulti(point, groundcaps) > ASTAR_COSTMULTI_NORMAL
	end
	return false
end

-- 子路径拼接完后进行路径平滑
local function SmoothPath(self, path, startstep, endstep)
	local startstep = startstep or 1
	local endstep = endstep or #(path.steps)
	local check_pathcaps = shallowcopy(self:GetPathCaps(true))
	check_pathcaps.ignorecreep = self.inst:HasTag("spiderwhisperer")
	local check_groundcaps = self:GetGroundCaps(true)

	local lua_pathfinder = self:GetLuaPathfinder()
	local check_pathfinder = self:GetLuaPathfinder() or self:GetPathfinder()

	local index = startstep+1 -- startstep的后一个step才是有可能会删除的
	while(index <= endstep-1 and index < #(path.steps)) do --endstep的前一个step才是有可能会删除的
		local pre = StepToVector3(path.steps[index-1])
		local post = StepToVector3(path.steps[index+1])
		local cur = StepToVector3(path.steps[index])
		-- delete the unnecessary points
		if ((pre.x == post.x and pre.z == post.z) or
				check_pathfinder:IsClear(pre, post, check_pathcaps)) -- equals or hasLOS
				and (lua_pathfinder == nil or not IsPointOnFasterGround(lua_pathfinder, cur, check_groundcaps)) then -- not on faster ground
			--make it not out of RPC range after remove current point
			if VecUtil_DistSq(pre.x, pre.z, post.x, post.z) > MAX_STEP_DIST_SQ + 4 then
				local inrange_pos = (post - pre):GetNormalized()* (MAX_STEP_DIST)+pre
				path.steps[index] = Vector3ToStep(inrange_pos)
				index = index + 1
			else
				table.remove(path.steps, index)
				endstep = endstep -1
			end
		else
			index = index + 1
		end
		--print("index:",index)
	end
	return path
end

-- 用于寻路完成后的精细化，将子路径拼接进原路径
-- when we get a refined subpath, next is to combine subpath to the path
local function PostprocessPath(self, path, subpath, startstep, endstep)
	-- 掐头去尾，中间部分插入
	-- remove the first and last step, insert the the internal part
	local sub_maxsteps = #(subpath.steps)
	if sub_maxsteps > 2 then
		local steps = deepcopy(path.steps)
		--删除原来路径的中间节点 {a(startstep), b, c, d(endstep)} --> {b,c}
		-- delete original internal step
		if (endstep - startstep) > 1 then
			for i= endstep-1, startstep+1, -1 do
				table.remove(steps, i)
			end
		end
		-- 将中间的节点加入到原路径 path.steps{b, c} + subpath.steps{d(firststep),e,f,h(laststep)} --> {b,e,f,c}
		-- merge internal steps of subpath(ignore the firststep and laststep because they're perhaps at overhang area) to pathsteps
		for i = 2, sub_maxsteps - 1 do
			local step = subpath.steps[i]
			table.insert(steps, startstep+i-1, step)
			if self.debugmode and self.debug_signs then
				local sign = SpawnPrefab("minisign")
				sign.Transform:SetPosition(step.x, step.y, step.z)

				table.insert(self.debug_signs, sign)
			end
		end
		path.steps = steps
		path = SmoothPath(self, path, startstep)
		--print("merge subpath to path")
	end
	return path
end

-- 得到后续没有寻路墙，蜘蛛网，海难洪水的路径节点
-- get first follow-up step that without pathfinding wall or without creep(spider-net) or without flood (for SW)
local function GetFirstIndexOfWalkableStep(steps, startstep, endstep, pathfinder, pathcaps)
	if steps ~= nil then
		for i=startstep, (endstep or #(steps)) do
			local step = steps[i]
			--if (pathcaps.ignorewalls or not TheWorld.Pathfinder:HasWall(step.x, 0, step.z)) and
			--		not IsPointOnSlowerGround(pathfinder, StepToVector3(step), groundcaps) then
			--	--print("find a no wall step with backward offset", i-startstep)
			--	return i
			--end
			if pathfinder.IsPassableAtPoint == nil or pathfinder:IsPassableAtPoint(StepToVector3(step), pathcaps) then
				return i
			end

		end
	end
end

-- 由于客户端存在玩家一定范围加载实体，范围外实体无法检测，因此第一次寻路可能检测不到范围外的墙体和蜘蛛网，当每次到达下一步时再次进行子路径寻路来refine
-- we are not able to check all the entities(walls, spidernet) about ground condition, because the game is only load the entities in a player range
-- so we should research some subpath to refine it when we arrive next step during the pathfollow
local function DoSubpathSearch(self)
	if not self:IsSearching() and self.path ~= nil then
		local check_pathfinder = self:GetLuaPathfinder() or self:GetPathfinder()
		local check_pathcaps = shallowcopy(self:GetPathCaps(true))
		local check_groundcaps = self:GetGroundCaps(true)
		check_pathcaps.ignorecreep = not (check_groundcaps.speed_on_creep and check_groundcaps.speed_on_creep < 0)
		check_pathcaps.ignoreflood = not (check_groundcaps.speed_on_flood and check_groundcaps.speed_on_flood < 0)

		local steps = self.path.steps
		local currentstep = self.path.currentstep
		local maxstep = #(steps)
		local startstep = currentstep-1
		local endstep = GetFirstIndexOfWalkableStep(steps, currentstep, maxstep, self:GetCurrentPathfinder(), check_pathcaps)
						or maxstep

		local startpos = StepToVector3(steps[startstep])
		local endpos = StepToVector3(steps[endstep])

		-- only has not LOS we do the search to refine subpath
		if not (startpos == endpos or 	--precheck
				check_pathfinder:IsClear(startpos, endpos, check_pathcaps)) then --check LOS(line of sight)
			self.subsearch_info = {startstep = startstep, endstep = endstep}
			self:FindPath(startpos, endpos, check_pathcaps) --use klei's pathfinder this time
			--print("start a subsearch", startstep, endstep, maxstep)
		end

	end
end


-- 得到路径后保证人物跟随，检查与下一步的位置，到达后切换下一步，直至到达终点
-- when we get a path ,just make the character following it
local function FollowPath(self)
	local path = self.path
	local inst = self.inst
	if self.dest == nil then return end
	if self.extra_check_fn ~= nil then
		self.extra_check_fn(inst)
	end
	local in_idle = inst:HasTag("idle") -- official tag
	local arrive_currentstep = inst:HasTag("arrive_currentstep") -- my tag

	local player_pos = inst:GetPosition()
	player_pos.y = 0

	local currentstep_pos = StepToVector3(path.steps[path.currentstep]) -- {y,x,z} --> Vector3

	local step_distsq = player_pos:DistSq(currentstep_pos)

	-- Add tolerance to step points.
	local physdiameter = self.inst:GetPhysicsRadius(0)*2
	step_distsq = step_distsq - physdiameter * physdiameter

	local arrive_step_dist = self:GetArriveStep()
	if step_distsq <= (arrive_step_dist)*(arrive_step_dist) then
		local maxsteps = #self.path.steps
		if self.path.currentstep < maxsteps then
			self.path.currentstep = self.path.currentstep + 1
			self.inst:PushEvent("ngl_startnextstep", {currentstep = self.path.currentstep})
			local step = self.path.steps[self.path.currentstep]
			self:Move(StepToVector3(step))
			--print("switch to nextstep")
			if self.subsearch_enabled then
				-- clear the subsearch so it'll cancel last subpath refine if we have already arrive the next step
				self:KillAllSearches()
				self.subsearch_info = {startstep = nil, endstep = nil}
				DoSubpathSearch(self)
			end
		else
			self.inst:PushEvent("ngl_onreachdestination",{ pos = self.dest })
			if self.atdestfn ~= nil then
				self.atdestfn(self.inst)
			end
			--print("arrive the dest")

			self:ForceStop()
		end
	elseif in_idle or arrive_currentstep then
		self:Move(currentstep_pos)
		--print("revoke the follow")
	end

end

local function DirectWalkWithNoPath(self)
	local player_pos = self.inst:GetPosition()
	player_pos.y = 0
	local dest_distsq = player_pos:DistSq(self.dest)

	local in_idle = self.inst:HasTag("idle") -- official tag
	local arrive_currentstep = self.inst:HasTag("arrive_currentstep") -- my tag

	local arrive_step_dist = 2 --set larger tolerance because we have not set redirectfn in this case so far
	if dest_distsq <= (arrive_step_dist)*(arrive_step_dist) then
		self.inst:PushEvent("ngl_onreachdestination",{ pos = self.dest })
		if self.atdestfn ~= nil then
			self.atdestfn(self.inst)
		end
		self:ForceStop()
	elseif in_idle or arrive_currentstep then
		self:Move(self.dest)
	end
end

function PathFollower:OnUpdate()
	--等待结果：
	----如果寻路计算中，return等待结果
	----如果第一个寻路器搜索完成，且设置了第二个寻路器（第一个默认是官方C层的寻路器，第二个是lua层的A星寻路器），再用第二个搜索一下
	--处理结果：
	----如果查到寻路结果，让人物跟随路径
	----如果找不到或者无效路径，尝试直线方向靠近

	--waiting for path searching finish:
	----when the pathfinder is in calcating , just return and waiting for the result in next period
	----when C pathfinding search is over and the Lua pathfinder available, save the first's result and try to search with Lua pathfinder
	--handle the result when All Finished:
	----when Lua pathfinding search is over, prior to use Lua result and next use C result, otherwise no path
	----when we get a valid path, next is to depart and follow the path
	----when no path or invalid path , try to reach it with direct walking
	if self.path == nil and self:IsSearching() then
		local search_over, foundpath = CheckAndGetSearchResult(self)
		if not search_over then -- still in calcating
			return -- waiting for next update to check again
		end
		-- path search finished
			-- stop and clean the search
		self:KillAllSearches()
		
		-- 寻路完成
		if not self:CanUseLuaPathfinder() or self.using_lua_pathfinder then -- the final search
			local final_path = foundpath or self.tmp_path or nil
			if final_path ~= nil then
				--set up path
				local final_path = PreprocessPath(self, final_path)
				--final_path = SmoothPath(self, final_path)
				--checkDist(final_path)
				self.path = {}
				self.path.steps = final_path.steps
				self.path.currentstep = 2

				self.search_over_time = GetTime()
			else -- no path or invalid path
				self.path = nil
			end
		else -- 设置了两个寻路器，且第一个寻路搜索完成：保存一份官方的寻路器结果
			 -- equip with two pathfinder, and in first search over
			-- save the path as tmp
			self.tmp_path = foundpath
			self:SwitchToLuaPathfinder(true)
			local lua_pathfinder = self:GetLuaPathfinder()
			-- 官方的寻路可以在网格内精细采点但由于lua的A星寻路不行，可能会始终找不到路
			-- 如果官方寻路器在很短时间就有结果，则说明这是一段很短且简单的路径，且有可能是唯一一条网格内采点的路径
			-- 因此lua的A星寻路器可能无法检测到这条路，我们设置更短的lua的A星寻路时间限制
			-- if the C-side pathfinder has the result in a short time, it means it's a simple path.
			-- so we set the Lua-side pathfinder a shorter time limit
			if lua_pathfinder then
				-- 如果科雷的寻路器在短时间内找到了路，则说明路径不会很复杂，但有可能是网格内的采样点，lua层的A星只检测网格中心，未必能够找到，因此设定一个较短的时间限制
				-- 问我为什么不直接用科雷寻路器的结果，因为它不能跟随路径 :(
				lua_pathfinder:SetMaxTime(foundpath ~= nil and 0.3 or 2.5)
			end
			
			self:FindPath()
			return
		end


		---- 开始出发
		---- 停止上一次的直线走路
		---- 如果从Physics推测的pathcaps和服务器端的pathcaps不同，则每一步采用直线移动模式，否则用左键点击移动模式
		---- 如果没有路则直线移动模式
		-- start the autowalking
		if self.path ~= nil then
			-- for debug
			if self.debugmode then
				self:VisualizePath()
				print("Pathfinder:",self.using_lua_pathfinder and "Lua" or "C","search time cost:", self.search_over_time - self.search_start_time)
			end

			-- call it before SetMoveModeOverrideInternal
			self:RemoteStopDirectWalking()
			-- only the lua pathfinder can handle bypassing the flood
			local should_consider_flood = self:GetGroundCaps(true).speed_on_flood ~= ASTAR_SPEED_NORMAL
			self:SwitchToLuaPathfinder(should_consider_flood)
			self:GetCurrentPathfinder():SetMaxTime(1) -- limit subsearch cost time as 1 sec

			-- start pathfollow
			local cur_pathcaps = self:GetPathCaps(true)
			if cur_pathcaps then
				-- locomotor默认是 allowocean = false, ignorewalls = false,
				-- 如果我们通过Physics计算得到的pathcaps能跨海或者穿墙 和loco的不一致时，在左键点击下的移动会触发locomotor的寻路导致绕道
				self:SetMoveModeOverrideInternal((cur_pathcaps.allowocean or cur_pathcaps.ignorewalls) and MOVEMODE_DIRECTWALK or nil)
			end
			self:Move(StepToVector3(self.path.steps[self.path.currentstep]))
			self.inst:PushEvent("ngl_startpathfollow", {path = self.path})

			-- start add pathfinding walls for more obstacles
			-- for feature of avoid obstacle , see components/ngl_pfwalls_clientonly.lua
			TheWorld.ngl_ispathfinding = true
			TheWorld:PushEvent("ngl_pathfinding_change",{enabled = true})

			-- subsearch
			-- delay one frame to make sure the obstacle has accepted the event and finish to add the pathfinding walls
			self.inst:DoTaskInTime(0, function()
				if self.subsearch_enabled then
					self:KillAllSearches()
					self.subsearch_info = {startstep = nil, endstep = nil}
					DoSubpathSearch(self)
				end
			end)
		else
			if self.dest then
				-- start direct walk with no path
				self:SetMoveModeOverrideInternal(MOVEMODE_DIRECTWALK)
				self:Move(self.dest)
				self.inst:PushEvent("ngl_startdirectwalkwithnopath", {dest = self.dest})
			end
		end
	end

	---- 每到达一步，再次寻路来获取更精确的路径，因为只有客户端加载范围内的实体能被检测到
	---- 即第一次寻路无法检测到加载范围外的墙体和蜘蛛网
	---- do the path follow
	if self.path ~= nil then
		-- path follow
		FollowPath(self) -- request subpath search in-side
		-- refine subpath
		if self.subsearch_enabled and self:IsSearching() then
			local search_over, subpath = CheckAndGetSearchResult(self)
			if search_over then
				self:KillAllSearches()
				if subpath and self.subsearch_info and self.subsearch_info.startstep and self.subsearch_info.endstep then
					--local should_consider_flood = self:GetGroundCaps(true).speed_on_flood ~= ASTAR_SPEED_NORMAL
					self.path = PostprocessPath(self, self.path, subpath, self.subsearch_info.startstep, self.subsearch_info.endstep)
					self:Move(StepToVector3(self.path.steps[self.path.currentstep]))
					self.subsearch_info = {startstep = nil, endstep = nil}
				else
					--print("invalid subpath or incomplete subsearch info", subpath or "no subpath", self.subsearch_info or "no subsearch info")
				end
			end
		end
	else -- direct walk with no path
		DirectWalkWithNoPath(self)
	end

end

-- 能在延迟补偿的两种情况都好使，但当鼠标上附带物品时，由于左键动作变为Drop不再是WalkTo，无法移动
-- GoToPoint works both in the movment prediction
-- doesn't work when we hold something and left action is Drop
function PathFollower:GoToPoint(pos)
	local locomotor = self:GetLocomotor()
	if locomotor then	--lag compensation ON
		local act = BufferedAction(self.inst, nil, ACTIONS.WALKTO)
		locomotor:GoToPoint(pos, act, true)
	else	--lag compensation OFF
		SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, pos.x, pos.z) -- actually it call locomotor:GoToPoint in dedicated server
	end
end

-- 能在延迟补偿的两种情况都好使，鼠标上附带物品也能走，但是需要手动检测是否偏移路径
-- RunInDirection works both in the movment prediction
-- directwalk mode need a extra task to check if we run off the path
function PathFollower:RunInDirection(dir)
	local locomotor = self:GetLocomotor()
	if locomotor then	--lag compensation ON
		locomotor:RunInDirection(-math.atan2(dir.z, dir.x) / DEGREES)
	else	--lag compensation OFF
		SendRPCToServer(RPC.DirectWalking, dir.x, dir.z) -- actually it call locomotor:RunInDirection in dedicated server
	end

end

-- 左键点击的移动打断可以自动ClearBufferedAction来停止，但是DirectWalk需要发送StopWalkingRPC来停止直走
-- the direct walk in server triggered via send DIRECTWALK RPC
-- can only be stop via send StopWalkingRPC and can be redirected via resend DirectWalkingRPC
-- leftclick (ACTIONS.WALKTO) can be cleared internal by both leftclick and directwalk
function PathFollower:RemoteStopDirectWalking()
	-- remote and directwalking
	-- (should preserve the previous movemode to check, so plz call RemoteStopDirectWalking before SetMoveModeOverrideInternal)
	if self:GetLocomotor() == nil and self:GetMoveMode(true) == MOVEMODE_DIRECTWALK then
		SendRPCToServer(RPC.StopWalking)
	end
end

-- 根据不同移动模式来执行移动
-- select GoToPoint or RunInDirection by self:GetMoveMode()
function PathFollower:Move(pos)

	-- to avoid the case when we arrive the step but keep the previous directwalk state
	self:RemoteStopDirectWalking()

	-- get new movemode
	local movemode = self:GetMoveMode()
	if movemode == MOVEMODE_LEFTCLICK then
		self:GoToPoint(pos)
	elseif movemode == MOVEMODE_DIRECTWALK then
		local player_pos = self.inst:GetPosition()
		player_pos.y = 0
		local normalized_dir = (pos - player_pos):GetNormalized()
		self:RunInDirection(normalized_dir)
	end
end

-- 触发自动走路，输入可以是1. Vector3（触发寻路）； 2. Steps； 3. Path
-- OVERLOAD:
-- 1. Vector3 as input(Vector3)
-- 2. steps as input {{x = x1,y = y1,z = z1},....}
-- 3. path as input {steps = {...}}
function PathFollower:Travel(destPos)
	if destPos == nil then return end
	self:Clear()

	if destPos.IsVector3 and destPos:IsVector3() then -- is a Vector3
		local pathfinder = self:GetPathfinder()
		local lua_pathfinder = self:GetLuaPathfinder()
		if pathfinder then
			-- has move it to start following, which means add more obstacles' pathfinding walls only for subsearch
			---- for feature of avoid obstacle , see components/ngl_pfwalls_clientonly.lua
			--TheWorld.ngl_ispathfinding = true
			--TheWorld:PushEvent("ngl_pathfinding_change",{enabled = true})

			self.dest = destPos
			-- 客户端只加载一定范围的实体，因此最开始的寻路无法检测到范围外的墙体和蜘蛛网
			-- 走路过程中，每次到达当前步，再次对下一小段进行寻路来重新检测墙体和蜘蛛网进行refine
			-- when client-side, the game only loads the entity in a range, so we recheck the obstacles when arrive current step
			-- do subpath search while pathfollow to refine the path
			local pathcaps = self:GetPathCaps()
			local groundcaps = self:GetGroundCaps()
			-- 忽略寻路墙和蜘蛛网的话没必要做refine
			-- it's unnecessary to do path refine when ignore pathfinding walls and spider-web
			self.subsearch_enabled = not (TheWorld.ismastersim or -- not the client host world, we can check all the entities in the world so don't need the subsearch to recheck the out of loading range entities
											(pathcaps.ignorewalls and not (groundcaps.speed_on_creep and groundcaps.speed_on_creep == ASTAR_SPEED_SLOWER))) -- not the case of ignore walls and no speed down on creep meanwhile, subsearch is just for rechecking the walls and creep out range
			-- 海上寻路用C端寻路器，因为海上很多点都是连通的，Lua端的Openlist会很大，效率很低
			-- use C pathfinder-only when sea sailing, because it's more effective
			-- should use Lua pathfinder to handle no ocean world
			self.lua_pathfinder_enabled = not (TheWorld.has_ocean and pathcaps.allowocean and pathcaps.ignoreLand)
			-- 最开始的寻路采用两个寻路器分别寻路，见OnUpdate
			--不能同时寻路，因为都吃CPU（官方的效率高但做了性能限制，耗时超过10帧后放弃，lua的A星效率低，但可控可以自己限定最大时间，还可以沿着卵石路）
			-- dont do two search meanwhile, it costs CPU a lot and reduces each's efficiency
			self:SwitchToLuaPathfinder(false)
			if self:CanUseLuaPathfinder() then -- equip with two available pathfinder, we search twice one by one
				-- 给游戏自带寻路接口设定一个虚拟的时间限制，也许在某些情况只有它能够找到短距离的网格内采样的唯一路径
				-- set pathfinder component max time as a short time limit
				-- because in some case , only C pathfinder can scan some walkable points inside a tile
				pathfinder:SetMaxTime(0.1)
			end

			self.inst:PushEvent("ngl_newdest", {dest = self.dest})
			self:FindPath()
		end

	elseif type(destPos) == "table" then
		local steps
		if IsValidPath(destPos) then					-- is a path
			steps = destPos.steps
		elseif #destPos >= 2 then						-- is a steps
			steps = destPos
		end

		if steps ~= nil then
			self.dest = StepToVector3(steps[#steps])
			self.path = {steps = steps, currentstep = 2}
			self.subsearch_enabled = false -- a preset-path, dont change the path
			self.inst:PushEvent("ngl_startpathfollow", {path = self.path})
		else
			print("invalid travel input")
			return
		end
	end


	self.inst:StartUpdatingComponent(self)
	self.in_updating = true

end

-- pathfind via one pathfinders at once
function PathFollower:FindPath(startpos, endpos, pathcaps, groundcaps)
	--print("pathfinding with" , self.using_lua_pathfinder and "Lua-side" or "C-side" , "pathfinder" )

	local pathfinder = self:GetCurrentPathfinder()
	if pathfinder == nil then return end

	local p0 = startpos or Vector3(self.inst:GetPosition():Get())
	local p1 = endpos or Vector3(self.dest:Get())

	p0.y = 0
	p1.y = 0

	self:SetPathCapsOverrideInternal(pathcaps) --if pathcaps nil, then set overrdie as nil, which means cancel the override
	self:SetGroundCapsOverrideInternal(groundcaps)

	if pathfinder then
		pathfinder:SubmitSearch(p0, p1, self:GetPathCaps(), self:GetGroundCaps())
	end

	self.in_searching = true
	self.search_start_time = GetTime()
	--self.waitsearchresult_task = self.inst:DoPeriodicTask(FRAMES, check_search_status, FRAMES)
end

function PathFollower:KillAllSearches()
	self.in_searching = false -- set flag as search over
	local pathfinder = self:GetPathfinder()
	if pathfinder then
		pathfinder:KillSearch()
	end

	local lua_pathfinder = self:GetLuaPathfinder()
	if lua_pathfinder then
		lua_pathfinder:KillSearch()
	end
end


function PathFollower:IsSearching()
	return self.in_searching
end

function PathFollower:HasDest()
	return self.dest ~= nil
end

function PathFollower:GetLocomotor()
	return self.inst.components.locomotor or nil
end

-- 强制停止，清除所有任务，停止人物移动
-- stop and reset all the record
function PathFollower:ForceStop()
	self.inst:StopUpdatingComponent(self)
	self.in_updating = false

	self:Clear()

	local locomotor = self:GetLocomotor()
	if locomotor then
		locomotor:Stop()
		locomotor:Clear()
	else
		-- differs in different modes
		if self:GetMoveMode(true) == MOVEMODE_DIRECTWALK then
			SendRPCToServer(RPC.StopWalking)
		else
			-- common stop method
			local angle = self.inst:GetRotation() * DEGREES
			local offset_x = math.cos(angle) * FORCESTOP_OFFSET
			local offset_z = -math.sin(angle) * FORCESTOP_OFFSET
			local x,_,z = self.inst:GetPosition():Get()

			-- ugly code, just stop via leftclick the pos we front-facing
			SendRPCToServer(RPC.LeftClick, ACTIONS.WALKTO.code, x + offset_x, z + offset_z)
		end
	end

	self.inst:PushEvent("ngl_stoppathfollow")
	TheWorld.ngl_ispathfinding = false
	TheWorld:PushEvent("ngl_pathfinding_change",{enabled = false})

end



-- 清除所有任务和数据
function PathFollower:Clear()

	self:KillAllSearches()
	-- if self.waitsearchresult_task then
	-- 	self.waitsearchresult_task:Cancel()
	-- 	self.waitsearchresult_task = nil
	-- end

	-- if self.followpath_task then
	-- 	self.followpath_task:Cancel()
	-- 	self.followpath_task = nil
	-- end

	-- if self.check_arrival_for_directwalk_task then
	-- 	self.check_arrival_for_directwalk_task:Cancel()
	-- 	self.check_arrival_for_directwalk_task = nil
	-- end

	self.path = nil
	self.tmp_path = nil
	self.dest = nil

	self.using_lua_pathfinder = false

	if self.debug_signs ~= nil then
		for _, sign in pairs (self.debug_signs) do
			sign:Remove()
		end
		self.debug_signs = nil
	end
end

function PathFollower:WaitingForPathSearch()
	-- return self.waitsearchresult_task ~= nil
	return self.in_updating and self.path == nil and self.in_searching
end

function PathFollower:FollowingPath()
	-- return self.followpath_task ~= nil
	return self.in_updating and self.path ~= nil
end

function PathFollower:DirectWalkingWithNoPath()
	-- return self.check_arrival_for_directwalk_task ~= nil
	return self.in_updating and self.path == nil and not self.in_searching
end

-- get the C pathfinder
function PathFollower:GetPathfinder()
	return self.pathfinder
end

-- get lua pathfinder if exists
function PathFollower:GetLuaPathfinder()
	return self.lua_pathfinder
end

function PathFollower:CanUseLuaPathfinder()
	return self:GetLuaPathfinder() ~= nil and self.lua_pathfinder_enabled
end

function PathFollower:SwitchToLuaPathfinder(enabled)
	if self:CanUseLuaPathfinder() then
		self.using_lua_pathfinder = enabled
	end
end	

-- switched between C-side pathfinder and Lua-side pathfinder
function PathFollower:GetCurrentPathfinder()
	return self.using_lua_pathfinder and self.lua_pathfinder or self.pathfinder
end

local function is_implemented_required_interfaces(pathfinder_cmp)
	return (pathfinder_cmp.SubmitSearch and pathfinder_cmp.GetSearchStatus and pathfinder_cmp.GetSearchResult and pathfinder_cmp.KillSearch and pathfinder_cmp.SetMaxTime) ~= nil
end

local function get_pathfinder_component(pathfinder, self)
	local pathfinder_cmp = nil
	if type(pathfinder) == "string" and self.inst.components[pathfinder] then
		pathfinder_cmp = self.inst.components[pathfinder]
	elseif type(pathfinder) == "table" then
		pathfinder_cmp = pathfinder
	end
	return pathfinder_cmp
end

-- set C-side Pathfinder, higher efficiency with inherent time limits
-- FindPath via C pathfinder first
function PathFollower:SetPathfinder(pathfinder)
	if pathfinder then
		local pathfinder_cmp = get_pathfinder_component(pathfinder, self)
		if pathfinder_cmp == nil then
			print("Pathfinder not exists")
			return
		end
		if is_implemented_required_interfaces(pathfinder_cmp) then
			self.pathfinder = pathfinder_cmp
		else
			print("Pathfinder has not implemented all requested interfaces")
		end
	end
end

-- set lua-side Astar Pathfinder, lower efficiency but without time limits
-- we will FindPath via Lua pathfinder if C pathfinder get no result
function PathFollower:SetLuaPathfinder(pathfinder)
	local lua_pathfinder_cmp = get_pathfinder_component(pathfinder, self)
	if self.pathfinder then
		if self.pathfinder ~= lua_pathfinder_cmp then
			self.lua_pathfinder = lua_pathfinder_cmp
		else
			print("Not allow to set the same pathfinder")
		end
	else
		print("Set C pathfinder first")
	end
end

function PathFollower:GetArriveStep()
	return self:GetLocomotor() and ARRIVESTEP_MOVEMENTPREDICT_ENABLED or ARRIVESTEP_MOVEMENTPREDICT_DISABLED
end

-- it's very complex to get the actual speed
-- including externalspeedmultiplier, groundmulti, inventoryitem multi and many other multi
-- evenif so ,it's not the actual
function PathFollower:GetSpeed()
	return
end

--- MOVE MODE

-- Deprecated, self-adapte by default and use SetMoveModeOverrideInternal to override it
--function PathFollower:SetMoveMode(movemode)
--	self.movemode = movemode
--end

-- use for component internal toggle movemode
function PathFollower:SetMoveModeOverrideInternal(movemode)
	self._movemode_override = movemode
end

-- outer interface and with higher priority, note that setmovemodeoverride before the Travel
function PathFollower:SetMoveModeOverride(movemode)
	self.movemode_override = movemode
end

-- should update the movemode after call Self:Move
function PathFollower:UpdateMoveMode()
	--update according to active_item
	-- when active_item , the left action is DROP but not WALKTO,which cause fail to handle LEFTCLICK RPC
	-- so use DIRECTWALK rpc instead
	local active_item = self.inst.replica.inventory and self.inst.replica.inventory:GetActiveItem() or nil
	self.movemode = active_item and MOVEMODE_DIRECTWALK or MOVEMODE_LEFTCLICK
end

-- without_update means you will get the previous movemode, actually it's the movemode of currentstep
-- Match the movemode when Move and Stop, otherwise it may have some problem
function PathFollower:GetMoveMode(without_update)
	if not without_update then
		self:UpdateMoveMode()
	end
	return self.movemode_override or self._movemode_override or self.movemode
end

--function PathFollower:GetMoveModeString()
--	if self.movemode_override then
--		if self.movemode_override == MOVEMODE_LEFTCLICK then
--			return "leftclick mode (0)"
--		elseif self.movemode_override == MOVEMODE_DIRECTWALK then
--			return "directwalk mode (1)"
--		end
--	else
--		return "adaptive mode "
--	end
--end

--- PATH CAPS
function PathFollower:SetPathCapsOverrideInternal(pathcaps)
	self._pathcaps_override = pathcaps
end

function PathFollower:SetPathCapsOverride(pathcaps)
	self.pathcaps_override = pathcaps
end

-- client side Physics modification will apply only when lag compensation enabled
function PathFollower:SetCollideWith(COLLISION_TYPE, clear_collide)
    local old_collision_mask = self.inst.Physics:GetCollisionMask()
    local new_collision_mask = old_collision_mask
        if not clear_collide and not self:CanCollideWith(COLLISION_TYPE) then
            new_collision_mask = self.inst.Physics:GetCollisionMask() + COLLISION_TYPE
        elseif clear_collide and self:CanCollideWith(COLLISION_TYPE) then
            new_collision_mask = self.inst.Physics:GetCollisionMask() - COLLISION_TYPE
        end
    self.inst.Physics:SetCollisionMask(new_collision_mask)
end

-- a function return can player collide with other
-- for example: if we can cross the ocean and land ,then it return false with COLLISION.LAND_OCEAN_LIMITS
function PathFollower:CanCollideWith(COLLISION_TYPE)
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

--GROUND            = 32,
--BOAT_LIMITS       = 64,
--LAND_OCEAN_LIMITS = 128,             -- physics wall between water and land
--LIMITS            = 128 + 64,        -- BOAT_LIMITS + LAND_OCEAN_LIMITS
--WORLD             = 128 + 64 + 32,   -- BOAT_LIMITS + LAND_OCEAN_LIMITS + GROUND
--ITEMS             = 256,
--OBSTACLES         = 512,
--CHARACTERS        = 1024,
--FLYERS            = 2048,
--SANITY            = 4096,
--SMALLOBSTACLES    = 8192,		-- collide with characters but not giants
--GIANTS            = 16384,	-- collide with obstacles but not small obstacles

    local collision_mask = self.inst.Physics:GetCollisionMask()
    return BitOperate(collision_mask,COLLISION_TYPE,"and") == COLLISION_TYPE
end

function PathFollower:UpdatePathCaps()
	local isplayer = self.inst:HasTag("player")
	local iswebber = self.inst:HasTag("spiderwhisperer")
	local is_onland = self.inst:IsOnValidGround() -- is standing on land at this moment
	--local is_sailing = self.inst.IsSailing and self.inst:IsSailing() -- for island adventure Mod
    -- get result from Physics component(C++ side) and use bit operate function in bit_operate_util.lua
	local no_land_ocean_limits = not self:CanCollideWith(COLLISION.LAND_OCEAN_LIMITS)
	local no_obstacle_collision = not self:CanCollideWith(COLLISION.OBSTACLES)
	self.pathcaps = {
						player = isplayer, ignorecreep = true, ignoreflood = true, ignorewalls = no_obstacle_collision,
						allowocean = not is_onland or no_land_ocean_limits,
						ignoreLand = not is_onland and not no_land_ocean_limits,
					}
	-- pathcaps的不忽略蜘蛛网不等于groundcaps的蜘蛛网减速！
	-- 不忽略蜘蛛网 意味着如果到处都有蜘蛛网，比如远古迷宫，会寻路失败
	-- 而蜘蛛网减速 意味着会先考虑没有蜘蛛网的点作为路径，如果最坏情况下到处都有蜘蛛网，还是会返回踩到蜘蛛网的路径
	-- ignorecreep = false is NOT equals speed_on_creep = ASTAR_SPEED_SLOWER !
	-- ignorecreep = false means you will failed to find a way if all areas are on creep
	-- speed down on creep means you will prior to find a way without creep, but in worst casea i mentioned, it will get the way on the creep
end


function PathFollower:GetPathCaps(without_update)
	if not without_update then
		self:UpdatePathCaps()
	end
	return self.pathcaps_override or self._pathcaps_override or self.pathcaps
end

--- FASTER GROUND TILES
--this may be very expensive
local function search_faster_on_tiles(inst)
    local faster_on_tiles = {}
    for tile_name, tile_id in pairs(WORLD_TILES) do
        if TileGroupManager:IsLandTile(tile_id) then
            if inst:HasTag("turfrunner_"..tostring(tile_id)) then
                faster_on_tiles[tostring(tile_id)] = true
            end
        end
    end
    --print("call faster tiles search")
    return faster_on_tiles
end

function PathFollower:UpdateCachedFasterGroundTiles(mount)
    local inst = mount or self.inst
    if self.cached_faster_on_tiles == nil then
        self.cached_faster_on_tiles = {}
    end
    self.cached_faster_on_tiles[inst] = search_faster_on_tiles(inst)
end


function PathFollower:GetFasterGroundTiles(mount, without_update)
    local inst = mount or self.inst
    if self.cached_faster_on_tiles == nil or self.cached_faster_on_tiles[inst] == nil and not without_update then
        -- update only has no corresponding record
        self:UpdateCachedFasterGroundTiles(inst)
    end
    return self.cached_faster_on_tiles[inst]
end

--- GROUND CAPS
function PathFollower:SetGroundCapsOverrideInternal(groundcaps)
	self._groundcaps_override = groundcaps
end

function PathFollower:SetGroundCapsOverride(groundcaps)
	self.groundcaps_override = groundcaps
end

-- for astar pathfinder
function PathFollower:UpdateGroundCaps()
	self.groundcaps = {speed_on_flood = nil, speed_on_road = nil, speed_on_creep = nil, faster_on_tiles = nil}
	-- i'm not sure the groundcaps when you pick a mod character who can fly
	-- at least we can exclude the ghost, we can sure ghost is no speed change for ground
	local can_cross_limits = not self:CanCollideWith(COLLISION.LAND_OCEAN_LIMITS)
	local isghost = self.inst:HasTag("player") and
					(self.inst.player_classified ~= nil and self.inst.player_classified.isghostmode:value()) or
					(self.inst.player_classified == nil and self.inst:HasTag("playerghost"))

	if isghost then return end

	local iswebber = self.inst:HasTag("spiderwhisperer")
-- 	local isriding =(self.inst.replica and self.inst.replica.rider and self.inst.replica.rider._isriding:value()) or
-- 					(self.inst.components and self.inst.components.rider and self.inst.components.rider:IsRiding())
	local mount = (self.inst.player_classified ~= nil and self.inst.player_classified.ridermount:value()) or
	              (self.inst.components and self.inst.components.rider and self.inst.components.rider:GetMount()) or
	              nil
	local locomotor = self:GetLocomotor()
	--FLOOD (island adventure Mod)
	local world_has_flood_cmp = TheWorld.components.flooding ~= nil
	local has_flood_immune_tags = self.inst:HasTag("flying") or self.inst:HasTag("flood_immune") or self.inst:HasTag("playerghost")
	self.groundcaps.speed_on_flood = world_has_flood_cmp and not has_flood_immune_tags and ASTAR_SPEED_SLOWER or ASTAR_SPEED_NORMAL


	--ROAD
	if mount ~= nil then
		local mount_faster_on_road = (self.inst.player_classified ~= nil and self.inst.player_classified.riderfasteronroad:value()) or
									 (mount.components.locomotor ~= nil and mount.components.locomotor.fasteronroad)
		self.groundcaps.speed_on_road = mount_faster_on_road and ASTAR_SPEED_FASTER or ASTAR_SPEED_NORMAL
	else
		if locomotor then
			self.groundcaps.speed_on_road = locomotor.fasteronroad and ASTAR_SPEED_FASTER or ASTAR_SPEED_NORMAL
		else -- we can't get locomotor:FasterOnRoad() when lag compensation OFF ,but player always fasteronroad i think
			self.groundcaps.speed_on_road = ASTAR_SPEED_FASTER
		end
	end


	--CREEP(spidernet)
	--ghost not trigger the creep
	if mount ~= nil then
		-- webber riding the mount will not trigger the creep either
		self.groundcaps.speed_on_creep = (not iswebber) and ASTAR_SPEED_SLOWER or ASTAR_SPEED_NORMAL
	else
		if locomotor then
			self.groundcaps.speed_on_creep = locomotor.fasteroncreep and ASTAR_SPEED_FASTER or (locomotor.triggerscreep and ASTAR_SPEED_SLOWER or ASTAR_SPEED_NORMAL)
		else
			self.groundcaps.speed_on_creep = iswebber and ASTAR_SPEED_FASTER or ASTAR_SPEED_SLOWER
		end
	end

	--FASTER TILES
    --it 's corresponding to the locomotor.faster_on_tiles
    -- such as wurt --> MARSH

	if mount ~= nil then
		self.groundcaps.faster_on_tiles = self:GetFasterGroundTiles(mount)
	else
		self.groundcaps.faster_on_tiles = self:GetFasterGroundTiles(self.inst)
	end

end

function PathFollower:GetGroundCaps(without_update)
	if not without_update then
		self:UpdateGroundCaps()
	end
	return self.groundcaps_override or self._groundcaps_override or self.groundcaps
end

--- DEBUG FNS
function PathFollower:GetDebugString()

	if self.dest == nil then
		return "no dest"
	else
		local status
		if self:DirectWalkingWithNoPath() then
			status = "no path and reset to directwalk"
		elseif self:WaitingForPathSearch() then
			status = "waiting for search result"
		elseif self:FollowingPath() then
			status = "following the path"
		end

		return "DEST:" .. tostring(self.dest) .. " STATUS:" .. status
	end
end

function PathFollower:VisualizePath()
	if not IsValidPath(self.path) then return end
	self.debug_signs = {}
	for _,step in pairs (self.path.steps) do
		local sign = SpawnPrefab("minisign")
		sign.Transform:SetPosition(step.x, step.y, step.z)

		table.insert(self.debug_signs, sign)
	end
end

function PathFollower:SetDebugMode(enabled)
	self.debugmode = (enabled == true)
	if self:FollowingPath() then
		self:VisualizePath()
	end
end

local function find_closest_prefab_exclude_list(x, y, z, rad, prefab, list)
    local ents = TheSim:FindEntities(x,y,z, rad or 30)
    local closest = nil
    local closeness = nil
    for k,v in pairs(ents) do
        if v.prefab == prefab then
			local vx,vy,vz = v:GetPosition():Get()
            if (closest == nil or (closeness and VecUtil_DistSq(x,z, vx,vz) < closeness)) and not v:HasTag("ngl_scaned") then
                closest = v
                closeness = VecUtil_DistSq(x,z, vx,vz)
            end
        end
    end
    if closest then
        table.insert(list, closest)
		closest:AddTag("ngl_scaned")
		--print("found", closest.GUID, " add to pathsteps")
		-- call by recursion
		local cx,cy,cz = closest:GetPosition():Get()
		find_closest_prefab_exclude_list(cx, cy, cz, rad, prefab, list)
    end
end

-- generate steps via seeking for the nearest prefab
function PathFollower:GenerateStepsByPrefab(prefab, rad, without_travel)
	local rad = 40 or rad
	local found_prefabs = {}
	local x,y,z = self.inst:GetPosition():Get()
	find_closest_prefab_exclude_list(x, y, z, rad, prefab, found_prefabs)

	if #(found_prefabs) == 0 then return end

	--first step is my position
	local exported_steps = {{x = x,y = y,z = z}}
	for _,v in pairs(found_prefabs) do
		local vx,vy,vz = v:GetPosition():Get()
		table.insert(exported_steps, {x=vx, y=vy, z=vz})
		v:RemoveTag("ngl_scaned")
	end

	if not without_travel then
		self:Travel(exported_steps)
	end
	return exported_steps
end

return PathFollower