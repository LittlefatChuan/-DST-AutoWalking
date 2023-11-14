local Widget = require "widgets/widget"

--the test of doubleclick
local DBCLICK_TIME_THRESHOLD = 0.3
local DBCLICK_DIST_THRESHOLD = 25
local VALIDCLICK_TIME_THRESHOLD = 0.1

local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"

--some actions maybe added in other mod triggered by combinekey + rightclick
--** use controlpress instead to avoid the case of key stick(the key keep on down and not released )
function IsCombineKeyPressed()
	--return TheInput:IsKeyDown(KEY_LALT) or TheInput:IsKeyDown(KEY_LCTRL) or TheInput:IsKeyDown(KEY_LSHIFT)
	return TheInput:IsControlPressed(CONTROL_FORCE_INSPECT) or TheInput:IsControlPressed(CONTROL_FORCE_ATTACK) or TheInput:IsControlPressed(CONTROL_FORCE_TRADE) or TheInput:IsControlPressed(CONTROL_FORCE_STACK)
end

function IsTriggerControlPressed(control)
	if TheInput:ControllerAttached() then --game controller mode
		return control == CONTROL_INSPECT
	else -- mouse and keyboard mode
		return control == CONTROL_SECONDARY and not IsCombineKeyPressed()
	end
	return false
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
	
	local old_OnControl = self.OnControl
	self.OnControl = function (self, control, down)
		-- trigger way of keyboard
		if down and GetStaticTime()-self.lastactive_time > VALIDCLICK_TIME_THRESHOLD and IsTriggerControlPressed(control) then
			local current_click_time = GetStaticTime()
			local current_click_pos = TheInput:GetScreenPosition()
			
			if not TheInput:ControllerAttached() and hasrightclickfn --if we do twice fast and small offset of click, it's a doubleclick(only when keyboard mode)
				and (current_click_time - self.lastrightclick_time) < DBCLICK_TIME_THRESHOLD
					and current_click_pos:Dist(self.lastrightclick_pos) < DBCLICK_DIST_THRESHOLD then
					--print("old_rightclick")
					ThePlayer.components.ngl_pathfollower:ForceStop()
					return old_OnControl(self, control, down)
			else -- it's a single click ,goto autowalk
				local topscreen = TheFrontEnd:GetActiveScreen()
				if topscreen.minimap ~= nil then
					local x, _, z = topscreen:GetWorldPositionAtCursor()
					local target_pos = Vector3(x, 0, z)
					ThePlayer.components.ngl_pathfollower:Travel(target_pos)
				end
			end
			
			self.lastrightclick_time = current_click_time
			self.lastrightclick_pos = current_click_pos
		else --control except mouserightdown
			return	old_OnControl and old_OnControl(self, control, down)
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
	local mapsize_w ,mapsize_h = TheSim:GetScreenSize()
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