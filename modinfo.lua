local CH = locale == "zh" or locale == "zhr"
name = CH and "自动寻路" or "Auto Walking"
forumthread = ""
author = "川小胖 & Fengying(original author)"

version = "3.7.5"

description = CH and
[[功能：
1.右键单击地图 或小地图mod一点，自动走向该位置
停止方法：WASD、F、空格、鼠标点击；	地图中：空格
2.(Ctrl/Shift/Alt)+右键 或 右键双击 来进行原本的地图右键操作，如灵魂跳跃，投掷烂靴子
3.延迟补偿是否开启，右键寻路都能生效
4.寻路自动绕路功能，绕开更多的障碍物，如食人花、骨架、木牌、池塘等
(需要多层世界且禁用"独行长路"模组)

更新日志：
3.7.5:
寻路算法速度优化，感谢 “萌萌的新” 提供帮助
]]
-- 3.7.4:修复被击退后罚站,新增禁止迷雾寻路,新增更多绕过的危险物体
-- 3.7.3:新增一些寻路会绕过的物体,新增追加寻路模式
-- 3.7.2:修正角色在能跨海时的无法跟随卵石路和绕过蜘蛛网的问题（例如伍迪变鹅）
-- 3.7.1:兼容岛屿冒险能够海上寻路，A星寻路器可以绕过水坑，并尝试缓解寻路中的卡位问题。
-- 3.7.0:修复智能绕路选项的闪退问题，现在走路过程中能够动态更正路径，检测新进入加载范围的障碍物
-- 3.6.9:新的图标！(感谢小巫)不满意也可以在配置的图标风格里换回老版
-- 3.6.8:移动期间自适应调节移动的模式（根据鼠标是否吸附着物品），以及相关的buuuug修复
-- 3.6.7:添加手柄的兼容，连接手柄时，地图中按检查键Y触发
-- 3.6.6:降低了跟随卵石路的频率，添加了角色的跨海能力检测（兼容mod）自动切换寻路模式,添加了额外加速地皮的检测（兼容地皮mod），改进了仅对角线方向地皮连接的识别，修复了路线图标在SmallMap模组上的显示问题
-- 3.6.5：地图新增路线UI; 解决了鼠标拿着物品寻路会中断的问题; 代码重构.
-- 3.6.4：寻路优先跟随加速卵石路，尽量绕开减速蜘蛛网
-- 3.6.3：适当降低了备用寻路算法的计算负载，来解决部分机器在远距离寻路产生的闪退问题
-- 3.6.2：现在开启延迟补偿和关闭延迟补偿的走路效果保持一致，可以远距离寻路且不会被动打断
-- 3.6.1：增加了一个备用的A星寻路算法，花费1s内的时间来解决远距离寻路失败的问题，默认开启，如果遇到问题可以在配置页面关闭。
-- 3.6.0：增加了一个备用寻路算法，花费1~2s左右的时间来解决远距离寻路失败的问题，默认关闭，可以在配置页面打开测试
-- 3.5.8：麦斯威尔重做崩溃修复
-- 3.5.7：优化了双击判定，只有在短时间（0.3s）和短距离（25像素）内的两次点击才视为双击
-- 3.5.6：修复在卡键情况下会导致右键无法触发寻路，绕路功能中暂时移除了重物的修改
-- 3.5.5：对小地图mod（MiniMapHUD或SmallMap）进行了一些适应性修改（如果启用了）可以直接点小地图自动寻路
or
[[1.Click a point on the map or Minimap Mod with right button then automatically walk to target
2.DoubleClick(or click with Ctrl/Shift/Alt) a point on the map with right button and it will do the original map rightclick action.
For example: soulhop when you pick wortox 
3.automatically avoiding some obstacles during the walking(only works in multi-shard world and no "Dont Starve Alone" Mod)

UPDATE:
3.7.5:
Made some optimization for pathfinding algorithm, Thanks for help of "萌萌的新"
]]
-- 3.7.4: Avoiding more dangerous stuffs during the walking, Banned for fog of war is now configable
-- 3.7.3: Avoiding some dangerous stuffs during the walking, New feature - Additional Travel is available
-- 3.7.2: Fix a issue that the road following and spider-net bypassing not works when charactor are allowed to cross the ocean and land(eg: woodie's weregoose transform)
-- 3.7.1: Now it works well with island adventure mod, and new feature of bypassing the flood, fixed some incorrect logic when bypassing obstacles
-- 3.7.0: Fix the crash issue of Bypass obstacles option, and add Dynamic Adjustment of Path during the autowalking
-- 3.6.9: New Icon(Enabled by default), toggle in mod config to back to the classical
-- 3.6.8: fixed buuuug(i dont wanna modify it anymore) and make it can toggle the movemode adaptive(by checking the active item) during the path follow
-- 3.6.7: You can trigger it by inspect control(Y defaultly) in map when controller attached
-- 3.6.6: Less meaningless road following .Auto switch to directly walk if charactor can cross between land and ocean.Be compatible with more tiles that able to accelerate.Fix display issue of pathline in SmallMap Mod
-- 3.6.5: Path line now can be shown in mapscreen, solve the issue that autowalk will be stopped with item in active slots, refactor the code.
-- 3.6.4: Auto follow the road and avoid the spider-net as possible in walking process
-- 3.6.3: Reduce the caculate load of backup pathfinding algorithm to solve the crash problem
-- 3.6.2: The backup pathfinding algorithm can work in both case.
-- 3.6.1: An A star pathfinding algorithm has been added as the backup pathfinder(So far,it's enabled only when Lag compensation OFF), to solve the pathfinding if we can't found a path via the interface provided by Klei
-- You can disable it in config (the last option) when you get some problem with it

api_version = 10
dst_compatible = true
dont_starve_compatible = false
shipwrecked_compatible = false
reign_of_giants_compatible = false

all_clients_require_mod = false
client_only_mod = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

priority = -1001

local LMB = "\238\132\128"
local RMB = "\238\132\129"

configuration_options = {
	{
		name = "ALLOW_FOGOFWAR",
		label = CH and "允许地图迷雾寻路" or "Allow Fog Of War",
		hover = CH and "是否允许在地图迷雾寻路" or "Allow Pathfinding in Fog Of War",
		options = {{description = CH and "是" or "Yes",data = true},{description = CH and "否" or "No",data = false}},
		default = true,
	},
	{	
		name = "ICON_ENABLE",
		label = CH and "目的图标显示" or "show dest icon",
		hover = CH and "右键点击地图是否生成图标以便提示" or "mark the position you clicked", 
		options = {{description = CH and "开启" or "Enabled",data = true},{description = CH and "关闭" or "Disabled",data = false}},
		default = true,
	},
	{	
		name = "PATHLINE_ENABLE",
		label = CH and "路线显示" or "show path line",
		hover = CH and "寻路成功是否生成路线以便提示" or "show the pathline if find a path", 
		options = {{description = CH and "开启" or "Enabled",data = true},{description = CH and "关闭" or "Disabled",data = false}},
		default = true,
	},
	{
		name = "ICON_STYLE",
		label = CH and "图标风格" or "icon style",
		hover = CH and "感谢小巫翻新了图标" or "Thank you Miss Wu for drawing the new icon",
		options = {{description = CH and "新版" or "New", data = 1},{description = CH and "老版" or "Classical",data = 0}},
		default = 1,
	},
	{
		name = "TWEAK_MINIMAP_ENABLE",
		label = CH and "Minimap模组修改" or "tweak of Minimap Mod",
		hover = CH and "是否增加Minimap模组的修改，可以点小地图寻路" or "Make it works just rightclick in the Minimap",
		options = {{description = CH and "开启" or "Enabled",data = true},{description = CH and "关闭" or "Disabled",data = false}},
		default = true,


	},
	{
		name = "TWEAK_SMALLMAP_ENABLE",
		label = CH and "Smallmap模组修改" or "tweak of Smallmap Mod",
		hover = CH and "是否增加Smallmap模组的修改，可以点小地图寻路" or "Make it works just rightclick in the Smallmap",
		options = {{description = CH and "开启" or "Enabled",data = true},{description = CH and "关闭" or "Disabled",data = false}},
		default = true,

	},
	{
		name = "TWEAK_DETOUR_ENABLE",
		label = CH and "智能绕路(需要洞穴)" or "Bypass obstacles(Caves Added)",
		hover = CH and "寻路会自动绕开障碍物，测试阶段，如遇到bug请留言" or "in beta ,turn it off if any error occur",
		options = {{description = CH and "开启" or "Enabled",data = true},{description = CH and "关闭" or "Disabled",data = false}},
		default = true,


	},
	{
		name = "PATHFINDER",
		label = CH and "寻路器" or "Pathfinder",
		hover = CH and "A*：可远距离寻路，且可跟随卵石路\n官方自带：用于近距离快速寻路，远距离可能失效" or "A star:long-distance pathfinder and can follow the road\nklei's:short-distance but cost less time to caculate, may fail in long-distance search",
		options = {{description = CH and "A*" or "A star",data = "A star"},{description = CH and "官方自带" or "klei's",data = "klei's"}},
		default = "A star",

	},
	{
		name = "KEY_ADDITION_TRAVEL",
		label = CH and "追加寻路按键" or "Additional Travel Keybind",
		hover = CH and "在第一次标点的位置继续搜索后续标点的路线，如果一次标点寻路失败可以尝试手动分段标点" or "extend the existed path base on the previous destination you marked \n try to segment the pathfinding task manually to relieve the pathfinding stress",
		options = {{description = CH and "禁用" or "Disabled",data = false},{description = CH and "Shift+"..RMB or "Shift+"..RMB ,data = "CONTROL_FORCE_TRADE"},{description = CH and "Ctrl+"..RMB or "Ctrl+"..RMB ,data = "CONTROL_FORCE_ATTACK"},{description = CH and "Alt+"..RMB or "Alt+"..RMB ,data = "CONTROL_FORCE_INSPECT"}},
		default = false,

	},
}