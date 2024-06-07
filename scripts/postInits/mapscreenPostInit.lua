local Widget = require "widgets/widget"

--the test of doubleclick
local DBCLICK_TIME_THRESHOLD = 0.3
local DBCLICK_DIST_THRESHOLD = 25
-- delay to check click after open the map 
local VALIDCLICK_TIME_THRESHOLD = 0.1

-- for additional travel 
local ad_travel_keystr = GetModConfigData("KEY_ADDITION_TRAVEL")
local CONTROL_ADDITIONAL_TRAVEL = ad_travel_keystr and rawget(GLOBAL, ad_travel_keystr) or nil

local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"

-- DEPRECATED
-- --some actions maybe added in other mod triggered by combinekey + rightclick
-- --** use controlpress instead to avoid the case of key stick(the key keep on down and not released )
-- function IsCombineKeyPressed()
-- 	--return TheInput:IsKeyDown(KEY_LALT) or TheInput:IsKeyDown(KEY_LCTRL) or TheInput:IsKeyDown(KEY_LSHIFT)
-- 	return TheInput:IsControlPressed(CONTROL_FORCE_INSPECT) or TheInput:IsControlPressed(CONTROL_FORCE_ATTACK) or TheInput:IsControlPressed(CONTROL_FORCE_TRADE) or TheInput:IsControlPressed(CONTROL_FORCE_STACK)
-- end

-- function IsTriggerControlPressed(control)
-- 	if TheInput:ControllerAttached() then --game controller mode
-- 		return control == CONTROL_INSPECT
-- 	else -- mouse and keyboard mode
-- 		return control == CONTROL_SECONDARY --and not IsCombineKeyPressed()
-- 	end
-- 	return false
-- end



local NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS = {
	[CONTROL_FORCE_ATTACK] = true, 	-- Ctrl
	[CONTROL_FORCE_TRADE] = true, 	-- Shift
	[CONTROL_FORCE_INSPECT] = true 	-- Alt
}
if CONTROL_ADDITIONAL_TRAVEL ~= nil then
	NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS[CONTROL_ADDITIONAL_TRAVEL] = false
end

-- returns : is travel control clicked(true/false),  is additional travel(true/false)
-- set it as global function so that minimap/smallmap postinit can use it 
function CheckClickedAndGetTravelType(control)
	local travel_control_pressed
	if TheInput:ControllerAttached() then --game controller mode
		travel_control_pressed = (control == CONTROL_INSPECT)
	else -- mouse and keyboard mode
		travel_control_pressed = (control == CONTROL_SECONDARY) --and not IsCombineKeyPressed()
	end
	if not travel_control_pressed then return false, false end

	for k,v in pairs(NO_TRIGGER_TRAVEL_MODIFIER_CONTROLS) do 
		if v and TheInput:IsControlPressed(k) then
			return false, false -- override as false to avoid conflict with other mod which has map rightclick action
		end
	end

	return true, (CONTROL_ADDITIONAL_TRAVEL ~= nil and TheInput:IsControlPressed(CONTROL_ADDITIONAL_TRAVEL))
end

--screenPos: original point(0,0) is center point
function WorldPosToScreenPos(self, x, z)
	local screen_width, screen_height = TheSim:GetScreenSize() -- 1920, 1080
	local half_x, half_y = RESOLUTION_X / 2, RESOLUTION_Y / 2 -- 1280/2, 720/2
	local map_x, map_y = TheWorld.minimap.MiniMap:WorldPosToMapPos(x, z, 0) -- Converts world position to map position
	local screen_x = ((map_x * half_x) + half_x) / RESOLUTION_X * screen_width -- Centers map point onto middle of map screen
	local screen_y = ((map_y * half_y) + half_y) / RESOLUTION_Y * screen_height
	return screen_x, screen_y
end

-- SINGLECLICK : AUTOWALK
-- DOUBLECLICK : ORIGINAL SINGLECLICK FUNCTION
-- we should tweak to make it work in main mapscreen
function AddAutoMoveTrigger(self, hasrightclickfn)

	-------------------------MOUSECLICK TRIGGER-----------------------
	--store the info about lastclick to test whether it's doubleclick this time
	self.lastactive_time = 0
	
	self.lastrightclick_time = 0
	self.lastrightclick_pos = Vector3(0,0,0)
	
	local old_OnBecomeActive = self.OnBecomeActive
	self.OnBecomeActive = function(self)
		self.lastactive_time = GetStaticTime()
		return old_OnBecomeActive(self)
	end

	local get_teleport_command_str = function(x, z)
		local command_str = [[
			local player = ConsoleCommandPlayer()
			local drownable = player and player.components.drownable
			local health = player and player.components.health
			local overwater = not TheWorld.Map:IsVisualGroundAtPoint(x, 0, z) and TileGroupManager and not TileGroupManager:IsInvalidTile(TheWorld.Map:GetTileAtPoint(x, 0, z)) and TheWorld.Map:GetPlatformAtPoint(x, z) == nil
			if not overwater or (health and health.invincible) or not (drownable and drownable.enabled) then
				c_teleport(x, 0, z)
				if player.SnapCamera then
					player:SnapCamera()
				end
			end
			]]
		return string.format("local x, z = %d, %d;", x, z) .. command_str
	end
	local function DoTeleport(x, z)
		if TheWorld and TheWorld.ismastersim then
			ExecuteConsoleCommand(get_teleport_command_str(x, z))
		else
			TheNet:SendRemoteExecute(get_teleport_command_str(x, z), x, z)
		end
	end

	local old_OnControl = self.OnControl
	self.OnControl = function (self, control, down)
		-- trigger way of keyboard
		local is_trigger_clicked, is_additional_travel = CheckClickedAndGetTravelType(control)
		if down and GetStaticTime()-self.lastactive_time > VALIDCLICK_TIME_THRESHOLD and is_trigger_clicked then
			local current_click_time = GetStaticTime()
			local current_click_pos = TheInput:GetScreenPosition()
			local topscreen = TheFrontEnd:GetActiveScreen()
			if topscreen and topscreen.GetWorldPositionAtCursor ~= nil then
				local x, _, z = topscreen:GetWorldPositionAtCursor()
				if not TheInput:ControllerAttached() and hasrightclickfn --if we do twice fast and small offset of click, it's a doubleclick(only when keyboard mode)
						and (current_click_time - self.lastrightclick_time) < DBCLICK_TIME_THRESHOLD
						and current_click_pos:Dist(self.lastrightclick_pos) < DBCLICK_DIST_THRESHOLD then
					--print("old_rightclick")
					ThePlayer.components.ngl_pathfollower:ForceStop()
					-- do teleport if we are in freebuildmode
					if TheNet:GetIsServerAdmin() and ThePlayer.player_classified.isfreebuildmode and ThePlayer.player_classified.isfreebuildmode:value() then
						ThePlayer:DoTaskInTime(0.5, function() DoTeleport(x, z)  end)
					end
					return old_OnControl and old_OnControl(self, control, down)
				else -- it's a single click ,goto autowalk
					if ThePlayer.components.ngl_pathfollower then
						local target_pos = Vector3(x, 0, z)
						ThePlayer.components.ngl_pathfollower:Travel(target_pos, is_additional_travel)
					end
				end
				self.lastrightclick_time = current_click_time
				self.lastrightclick_pos = current_click_pos
				return true
			end
		else -- other controls
			return old_OnControl and old_OnControl(self, control, down)
		end
		
	end

end

function AddExtraWidgets(self)
	------------------------POSITON TRANSFROM FUNCTIONS-----------------------------
	if self.WorldPosToScreenPos == nil then
		self.WorldPosToScreenPos = WorldPosToScreenPos
	end
	-------------------------PAINT WIDGET(ROOT)-------------------------------
	self.paintWidget = self:AddChild(Widget("PaintWidget"))
	-- local mapsize_w ,mapsize_h = TheSim:GetScreenSize()
	--self.paintWidget:SetScissor(-mapsize_w/2,-mapsize_h/2,mapsize_w,mapsize_h)
	------------------------SHOW PATH LINES(CHILD)-----------------------------
	-- add pathline widget 
	--self.pathLineGroup = self:AddChild(PathLineGroup(self,"images/plantregistry.xml","details_line.tex"))
	if GetModConfigData("PATHLINE_ENABLE") then
		self.pathLineGroup = self.paintWidget:AddChild(PathLineGroup(self,line_xml,line_texName))
		self.pathLineGroup:SetLineTint(1,1,1,0.8)
		self.pathLineGroup:SetLineDefaultHeight(40)
	end
	
	-----------------------SHOW DEST ICON(CHILD)------------------------------
	if GetModConfigData("ICON_ENABLE") then
		self.destIconImage = self.paintWidget:AddChild(DestIcon(self,icon_xml,icon_texName))
		self.destIconImage:SetDefaultScale(0.7)
	end
end

-- DISPLAY TWEAK IN mapwidget, TRIGGER TWEAK IN mapscreen
AddClassPostConstruct("widgets/mapwidget", AddExtraWidgets)
AddClassPostConstruct("screens/mapscreen", AddAutoMoveTrigger,true)