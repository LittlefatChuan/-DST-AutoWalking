local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"
local Widget = require "widgets/widget"

local ROT_REPEAT = .25

-------------------------ADD MORE KEYBIND------------
local function DoRotate(right)
    -- if not TheCamera:CanControl() then
		-- print("can't control")
        -- return
    -- end

    local rotamount = right and 45 or -45
    if not IsPaused() then
        TheCamera:SetHeadingTarget(TheCamera:GetHeadingTarget() + rotamount)
        --UpdateCameraHeadings()
    end
	--print("rot:"..rotamount)
end

local function AddRotForMinimap(self)
	local old_OnControl = self.OnControl
	self.OnControl = 
		function (self, control, down)
		    local isenabled, ishudblocking = ThePlayer.components.playercontroller:IsEnabled()
			if not isenabled and not ishudblocking then
				return
			end
			
			local time = GetStaticTime()
			local invert_rotation = Profile:GetInvertCameraRotation()
			if 	self.lastrottime == nil or time - self.lastrottime > ROT_REPEAT then	
				if control == CONTROL_ROTATE_LEFT or control == CONTROL_ROTATE_RIGHT then
					DoRotate(control == (invert_rotation and CONTROL_ROTATE_LEFT or CONTROL_ROTATE_RIGHT))
					self.lastrottime = time
				end
			end
			return old_OnControl(self, control, down)
		end

end

local function AddResetKeyForMinimap(self)
	local old_OnMouseButton = self.OnMouseButton
	self.OnMouseButton = 
		function (self, button, down, x, y)
			if button == MOUSEBUTTON_MIDDLE and down then
				self.minimap:ResetOffset()
			end
			
			if old_OnMouseButton ~= nil then
				return old_OnMouseButton(self, button, down, x, y)
			end
			return true
		end
end
----------------------ADD MORE FUNCTIONS-------------------------------
local function MiniMapWidget_GetMapPosition(self)
	local x_cursor, y_cursor = TheSim:GetPosition()
	local x_widgetcenter, y_widgetcenter = self.img:GetWorldPosition():Get()
	local w, h = self.img:GetSize()
	local scale = self.img:GetScale()
	local x = (x_cursor - x_widgetcenter)*(2-self.uvscale)/scale.x + w/2
	local y = (y_cursor - y_widgetcenter)*(2-self.uvscale)/scale.y + h/2
	--print(uvscale)
	--print(self.parent:GetScale():Get())
	--print(self:GetScale())
	x = 2 * x / w - 1
    y = 2 * y / h - 1
	return x, y
end

local function MiniMapWidget_GetWorldPositionAtCursor(self)
    local x, y = self:GetCursorPosition()
	--print("gt-mappos:",x,y)
    x, y = self.minimap:MapPosToWorldPos(x, y, 0)
	--print("gt_worldpos:",x,y)
    return x, 0, y -- Coordinate conversion from minimap widget to world.
end

-- ScreenPos: original point(0,0) is center of MiniMapHUD
local function MiniMapWidget_WorldPosToScreenPos(self, x, z)
	local map_x, map_y = self.minimap:WorldPosToMapPos(x, z, 0)
	
	local w, h = self.img:GetSize()
	local scale = self.img:GetScale()
	local map_x = map_x * w * scale.x /(2 - self.uvscale)/ 2
	local map_y = map_y * h * scale.y /(2 - self.uvscale)/ 2
    local screen_x = map_x /scale.x
    local screen_y = map_y /scale.y 
	
    return screen_x, screen_y
end
--------------------------FIX ORINGINAL FNS------------------------
---fix OnUpdate----
local function MiniMapWidget_OnUpdate(self, dt)
	if not self.shown then return end
	if not self.focus then return end
	if not self.img.focus then return end

	if TheInput:IsControlPressed(CONTROL_PRIMARY) then
		local pos = TheInput:GetScreenPosition()
		if self.lastpos then
			--local scale = 1/(self.uvscale*self.uvscale)
			local dx = ( pos.x - self.lastpos.x )*(2-self.uvscale)
			local dy = ( pos.y - self.lastpos.y )*(2-self.uvscale)
			self.minimap:Offset( dx, dy )
		end
		
		self.lastpos = pos
	else
		self.lastpos = nil
	end
end

---fix OnShow---- someone may dont like that minimap zoom tracked by map screen
function MiniMapWidget_OnShow(self)
	if self:IsOpen() then
		self:EnableMinimapUpdating()
	end
	self.minimap:Zoom(self.mapscreenzoom + 0.75 - self.minimap:GetZoom())
	self.minimapzoom = self.mapscreenzoom + 0.75
	self.minimap:ResetOffset()
end

-----------------------------ADD AUTOWALK--------------------------
function AddAutoMoveForMiniMap(self)
	-------------------------MOUSECLICK TRIGGER-----------------------
	local old_OnControl = self.OnControl
	self.OnControl = function (self, control, down)
		local is_trigger_clicked, is_additional_travel = CheckClickedAndGetTravelType(control)
		if is_trigger_clicked and down then		
			local topscreen = TheFrontEnd:GetActiveScreen()
			if topscreen == ThePlayer.HUD then
				if self.minimap ~= nil then
					local x, _, z = self:GetWorldPositionAtCursor()
					local target_pos = Vector3(x, 0, z)
					ThePlayer.components.ngl_pathfollower:Travel(target_pos, is_additional_travel)
				end
			end
		else --control except mouserightdown
			return	old_OnControl and old_OnControl(self, control, down)
		end
	end
	
	-------------------------PAINT WIDGET-----------------------
	self.paintWidget = self.img:AddChild(Widget("PaintWidget"))
	-- lw newbee 
	-- hide the widget outside this area
	self.paintWidget:SetScissor(-self.mapsize.w/2,-self.mapsize.h/2,self.mapsize.w,self.mapsize.h)
	------------------------SHOW PATH LINES-----------------------------
	-- add pathline widget 
	if GetModConfigData("PATHLINE_ENABLE") then
		self.pathLineGroup = self.paintWidget:AddChild(PathLineGroup(self,line_xml,line_texName))
		self.pathLineGroup:SetLineTint(1,1,1,0.8)
		self.pathLineGroup:SetLineDefaultHeight(15)
	end
		
	-----------------------SHOW DEST ICON------------------------------
	-- to hide the icon outside the minimap area, i add it as pathlinegroup's child
	if GetModConfigData("ICON_ENABLE") then
		self.destIconImage = self.paintWidget:AddChild(DestIcon(self,icon_xml,icon_texName))
		self.destIconImage:SetDefaultScale(0.2)
	end
end

------------------------------APPLY-------------------------------
AddClassPostConstruct("widgets/minimapwidget",
	function(self)
		self.GetCursorPosition = MiniMapWidget_GetMapPosition
		self.GetWorldPositionAtCursor = MiniMapWidget_GetWorldPositionAtCursor
		self.WorldPosToScreenPos = MiniMapWidget_WorldPosToScreenPos
		-- better to use hook instead of override to tweak it
		--self.OnUpdate = MiniMapWidget_OnUpdate 
		--self.OnShow = MiniMapWidget_OnShow
		AddAutoMoveForMiniMap(self)
		AddRotForMinimap(self)
		AddResetKeyForMinimap(self)

end)

