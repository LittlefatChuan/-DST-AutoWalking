--local excluded_tags = {"wall", "insanityrock", "sanityrock", "stargate"}

-- 给更多障碍注册寻路墙（基于物理半径），使得角色在自动寻路中，寻路系统能够找到绕开他们的路
-- register pathfinding wall to more obstacles based on their physics radius ,for avoiding stucked
-- it only walks during the autowalking and unregister when walking is over
local function ObstaclesToRegisterPathfinding(inst)
	return 	inst and inst:HasTag("blocker") and inst.Physics
		 and (
			inst:GetPhysicsRadius(0) >= .4
					--4 stuffs that player prefers to use in blocking
					or inst.prefab == "homesign"
					or inst.prefab == "fossil_stalker"
					or inst.prefab == "lureplant"
					--or	string.sub(inst.prefab,1,11) == "chesspiece_"
					or (inst.components.heavyobstaclephysics ~= nil or inst:HasTag("heavy")	)
			)
		-- the prefab which has registered their pathfinding wall
		--and not inst:HasOneOfTags(excluded_tags) and not (inst.prefab and string.sub(inst.prefab,1,14) == "support_pillar")

end


-- 注册寻路墙，只是为了绕开某块危险区域，这时候不再和物体的物理半径有关
-- register pathfinding wall only for avoid danger region
-- yep , it is not related to the actually physics radius, it just stands for the danger region

local CUSTOM_BYPASS_PREFABS = require("misc/custom_bypass_prefab_defs")


AddPrefabPostInitAny(function (inst)
	
	-- custom prefabs
	for _, subtab in ipairs(CUSTOM_BYPASS_PREFABS) do
		if subtab.prefab_fn and subtab.prefab_fn(inst)
				and inst.replica.ngl_pfwalls == nil and inst.components.ngl_obstaclepfwalls == nil and inst.components.ngl_custompfwalls == nil then
			inst:AddComponent("ngl_custompfwalls")
			inst.components.ngl_custompfwalls.radius_fn = subtab.radius_fn or nil
			inst.components.ngl_custompfwalls.enable_fn = subtab.enable_fn or nil
			return
		end
	end

	-- standard obstacles
	if ObstaclesToRegisterPathfinding(inst) and inst.replica.ngl_pfwalls == nil and inst.components.ngl_obstaclepfwalls == nil then
		inst:AddComponent("ngl_obstaclepfwalls")
		inst:DoTaskInTime(0.1, function()
			-- 那些本身在游戏中就已经注册寻路单元的物体，需要一直生效寻路单元，记录到寻路单元信息表
			inst.components.ngl_obstaclepfwalls.always_apply_pathfinding = (inst._pfpos ~= nil or inst._ispathfinding ~= nil )
			-- inst.components.ngl_obstaclepfwalls.radius = nil -- set pathfinding dims via tracking the physics radius
		end)
		-- otherwise, record pathfinding and apply pathfinding cell only during the autowalking
	end

	-- -- flooding in island adventure
	-- if inst.prefab == "network_flood" then
	-- 	inst:AddComponent("ngl_floodpfwalls")
	-- end

end)
