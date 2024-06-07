-- 注册寻路墙，只是为了绕开某块危险区域，这时候不再和物体的物理半径有关
-- register pathfinding wall only for avoid danger region
-- yep , it is not related to the actually physics radius, it just stands for the danger region

local mine_no_tags = { "notraptrigger", "flying", "ghost", "playerghost", "spawnprotection" }
local function IgnoreMineTrigger(player)
	if player == nil then return false end
	return player:HasOneOfTags(mine_no_tags)
end

local function IsUnevenGroundEnabled(inst) 
	-- check anim in client, it's the only way, -- see UpdateOverrideSymbols in antlion_sinkhole.lua
	local build, sym = inst and inst.AnimState and inst.AnimState:GetSymbolOverride("cracks1")
	return build == nil and sym == nil
end

-- ugly way to check can we ignore the unevenground 
local function IgnoreCarefulWalkerSlowDown(player)
	if player == nil then return false end
	-- riding
	local in_riding = player.replica and player.replica.rider and player.replica.rider._isriding and player.replica.rider._isriding:value()
	if in_riding then
		return true
	end
	-- woodie's weretransform
	local in_weretransform = player:HasOneOfTags({"werebeaver", "weregoose", "weremoose"})
	if in_weretransform then
		return true
	end
	
	return false
end

local WANDER_TOLERANCE = 2
return {

	-- prefab_fn : check the entity should add custompfwalls component
	-- radius_fn : return the radius of pathfinding cells to register
	-- enable_fn : check when should enable the pathfinding cell,(optional)
	
	-- with mine component: trap_starfish trap_teeth_maxwell
	{
		prefab_fn = function(inst) return inst:HasTag("trapdamage") or inst.prefab == "trap_teeth_maxwell"  end,
	 	radius_fn = function(inst) return TUNING.STARFISH_TRAP_RADIUS  end,
		enable_fn = function(inst) return inst:HasTag("mineactive") and not IgnoreMineTrigger(ThePlayer) end
	},
	-- with unevenground component: antlion_sinkhole eyeofterror_sinkhole daywalker_sinkhole bearger_sinkhole and more
	-- ThePlayer: carefulwalker
	{
		prefab_fn = function(inst) return inst:HasTag("antlion_sinkhole") end,
		radius_fn = function(inst)
			--local basic_boundingbox = {-3.2503850460052,	-3.314530134201,	3.0616064071655,	3.4429333209991}
			--local basic_w, basic_h = basic_boundingbox[3] - basic_boundingbox[1], basic_boundingbox[4] - basic_boundingbox[2]
			local basic_radius = TUNING.ANTLION_SINKHOLE.UNEVENGROUND_RADIUS
			local basic_w, basic_h = 6.312, 6.757
			local radius = basic_radius
			if inst.AnimState ~= nil then
				local x1,y1, x2,y2 = inst.AnimState:GetVisualBB()
				local cur_w, cur_h = x2-x1, y2-y1
				local avg_scale = (cur_w/basic_w + cur_h/basic_h)/2
				radius = basic_radius * avg_scale
			end
			return radius
		end,
		enable_fn = function(inst) return IsUnevenGroundEnabled(inst) and not IgnoreCarefulWalkerSlowDown(ThePlayer) end
	},
	-- UM MOD
	{		
		prefab_fn = function(inst) return inst.prefab == "snowpile" end,
		radius_fn = function(inst) return 2 end
	},
	-- -- ISLAND ADVANTURE MOD (FIXME: should register pathfinding walls with correct position offset, maybe should write a new component for it)
	-- {	prefab_fn = function(inst) return inst.prefab and inst.prefab == "network_flood" end,
	-- 	radius_fn = function(inst) return TILE_SCALE/2 end,
	-- 	enable_fn = function(inst) return not IgnoreFloodSlowDown(ThePlayer) end
	-- },
	-- with miasmanager component: miasma_cloud (Theplayer : miasmawatcher)
	{
		prefab_fn = function(inst) return inst:HasTag("miasma") end,
		radius_fn = function(inst) return TILE_SCALE/2 end
	},

	-- projectiles from toadstool: mushroombomb sporecloud
	{
		prefab_fn = function(inst) return inst.prefab == "mushroombomb" or inst.prefab == "mushroombomb_dark" end,
		radius_fn = function(inst) return TUNING.TOADSTOOL_MUSHROOMBOMB_RADIUS end
	},
	{
		prefab_fn = function(inst) return inst:HasTag("sporecloud") end,
		radius_fn = function(inst) return TUNING.TOADSTOOL_SPORECLOUD_RADIUS end
	},

	-- klaus's deer ice and fire magic
	{
		prefab_fn = function(inst) return inst:HasOneOfTags({"deer_ice_circle", "deer_fire_circle"}) end,
		radius_fn = function(inst) return 3 end
	},

	-- hostile childspawner
	{
		prefab_fn = function(inst) return inst:HasTag("hive") and (inst:HasTag("hostile") or inst:HasTag("WORM_DANGER")) end,
		radius_fn = function(inst) return 3 end
	},
	{
		prefab_fn = function(inst) return inst.prefab == "pigtorch_flame" end,
		radius_fn = function(inst) return 6 end
	},

	-- activated deerclopseyeball_sentryward
	{
		prefab_fn = function(inst) return inst.prefab == "deerclopseyeball_sentryward_fx" end,
		radius_fn = function(inst) return TUNING.DEERCLOPSEYEBALL_SENTRYWARD_GROUND_ICE_RADIUS end
	},

	-- mobs
	{
		prefab_fn = function(inst) return inst.prefab == "um_pawn" end,
		radius_fn = function(inst) return 7+2*WANDER_TOLERANCE end -- wander as fast speed
	},
	{
		prefab_fn = function(inst) return inst:HasTag("dragonfly") end,
		radius_fn = function(inst) return TUNING.DRAGONFLY_AGGRO_DIST end
	},
	{
		prefab_fn = function(inst) return inst:HasTag("beefalo") end, -- beefalo
		radius_fn = function(inst) return TUNING.BEEFALO_TARGET_DIST + WANDER_TOLERANCE end,
		enable_fn = function(inst) return inst:HasTag("scarytoprey") and not ThePlayer:HasTag("beefalo") end -- in mood and no equipped beefalo hat
	},
	{
		prefab_fn = function(inst) return inst:HasTag("eyeplant") end,
		radius_fn = function(inst) return TUNING.EYEPLANT_ATTACK_DIST end,
		enable_fn = function(inst) return not ThePlayer:HasTag('eyeplant_friend') end -- RuiTa Mod
	},
	{
		prefab_fn = function(inst) return inst.prefab == "spat" end,
		radius_fn = function(inst) return TUNING.SPAT_TARGET_DIST + WANDER_TOLERANCE end, -- dangerious, this guy can long-distance attack,
	},
	{
		prefab_fn = function(inst) return inst.prefab == "walrus" end,
		radius_fn = function(inst) return TUNING.WALRUS_TARGET_DIST + WANDER_TOLERANCE end,  -- dangerious, this guy can long-distance attack too
	},
	{
		prefab_fn = function(inst) return inst.prefab == "walrus_camp" end,
		radius_fn = function(inst) return 10 end,  -- AGGRO_SPAWN_PARTY_RADIUS in walrus_camp.lua
		enable_fn = function(inst) return inst.Light and inst.Light:IsEnabled() end
	},
}

