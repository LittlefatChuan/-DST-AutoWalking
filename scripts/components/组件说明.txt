-- ngl_pathfollower: 路径跟随组件，主要用于得到路径后让人物持续跟随路径，能在开关延迟补偿时都能好使，
-- ngl_astarpathfinder: Lua层的A星寻路算法实现，详见utils/astar_util.lua
-- ngl_pathfinder: 将游戏自带的CPP端的寻路接口进行了封装，来统一两个寻路器的接口给pathfollower调用, 具体实现不知，听说是C++层的分层A星寻路(分为地皮格和墙点格两层)
-- ngl_fusedpathfinder: 将CPP寻路器和LUA寻路器简单融合，会同时寻路两次选择优者作为结果
-- ngl_obstaclepfwalls:仅在客户端上给更多的障碍物加上寻路墙，当寻路完成，人物跟随路径时，会通过发送事件来注册障碍物的寻路墙，同时用官方的寻路进行再次分段寻路，然后在拼接回原路径进行动态的路径调整
-- ngl_custompfwalls:自定义给某些prefab加上寻路墙，比如陷阱，蚁狮陷坑等等，见misc/custom_bypass_prefab_defs.lua
	-- 寻路墙指的是通过TheWorld.Pathfinder:AddWall(x,y,z)来注册该点的记录，这时候寻路器会认为该点有1x1大小的正方形墙体，调用IsClear接口或者是寻路都会有影响(pathcaps.ignorewalls = false 的情况下）
	-- 需要注意添加的xyz必须对齐为墙体摆放点（x= math.floor(x) + 0.5），官方的寻路采样的最小单位也是墙点
	-- 服务器版本：见"Better Pathfinding" Mod 里components/ngl_pfwalls 和ngl_pfwalls_replica，在服务器和客户端上都添加了更多障碍物的寻路墙
-- 游戏自带寻路的一点线索（陈年老帖）：
https://forums.kleientertainment.com/forums/topic/9897-ai-pathfinding-of-creatures-still-not-fixed/
https://forums.kleientertainment.com/klei-bug-tracker/ds-shipwrecked/unreasonable-routing-with-coffee-buff-when-building-stonewallhaywall-r1685/


