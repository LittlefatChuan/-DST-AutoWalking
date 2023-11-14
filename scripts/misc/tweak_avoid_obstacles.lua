local excluded_tags = {"wall", "insanityrock", "sanityrock", "stargate"}

local function is_included(inst)
	return 	inst:HasTag("blocker") and inst.Physics
		 and (
			inst:GetPhysicsRadius(0) > .5
					--4 stuffs that player prefers to use in blocking
					or inst.prefab == "homesign"
					or inst.prefab == "fossil_stalker"
					or inst.prefab == "lureplant"
					--or	string.sub(inst.prefab,1,11) == "chesspiece_"
					or (inst.components.heavyobstaclephysics ~= nil or inst:HasTag("heavy")	)
			)
		-- the prefab which has registered their pathfinding wall
		and not inst:HasOneOfTags(excluded_tags) and not (inst.prefab and string.sub(inst.prefab,1,14) == "support_pillar")
end


AddPrefabPostInitAny(function (inst)
	if  is_included(inst) and inst.replica.ngl_pfwalls == nil and inst.components.ngl_pfwalls_clientonly == nil then
		inst:AddComponent("ngl_pfwalls_clientonly")
	end
end)
