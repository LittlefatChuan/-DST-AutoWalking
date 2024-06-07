local PathLineGroup = require "widgets/ngl_pathlinegroup"
local DestIcon = require "widgets/ngl_desticon"
local Widget = require "widgets/widget"

local ROT_REPEAT = .25

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

local function AddRotForSmallmap(self)
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

local function AddResetKeyForSmallmap(self)
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


--------------------------------------------------------------------
local function SmallMap_GetCursorPosition(self)	
	local x_cursor, y_cursor = TheSim:GetPosition()
	local x_widgetcenter, y_widgetcenter = self.img:GetWorldPosition():Get()
	local w, h = self.img:GetSize()
	local scale = self.img:GetScale()
	local x = (x_cursor - x_widgetcenter)*(2 - self.uvscale.x)/scale.x + w/2
	local y = (y_cursor - y_widgetcenter)*(2 - self.uvscale.y)/scale.y + h/2
	x = 2 * x / w - 1
    y = 2 * y / h - 1
	return x, y
end

local function SmallMap_GetWorldPositionAtCursor(self)
    local x, y = self:GetCursorPosition()
    x, y = self.minimap:MapPosToWorldPos(x, y, 0)
    return x, 0, y -- Coordinate conversion from minimap widget to world.
end

-- ScreenPos: original point(0,0) is center of SmallMap
local function SmallMap_WorldPosToScreenPos(self, x, z)
	local map_x, map_y = self.minimap:WorldPosToMapPos(x, z, 0)
	
	local w, h = self.img:GetSize()
	local scale = self.img:GetScale()
	local map_x = map_x * w * scale.x /(2 - self.uvscale.x)/ 2
	local map_y = map_y * h * scale.y /(2 - self.uvscale.y)/ 2
    local screen_x = map_x /scale.x
    local screen_y = map_y /scale.y 
	
    return screen_x, screen_y
end

------------------------------------------------------------------------

---store uvscale while setzoom---- klei plz add function Image:GetUVScale 
local function SmallMap_SetZoom(self, zoom)
	if zoom then
		if zoom < 0 then
			self.data.zoomlevel = 0
		elseif zoom < 1 then
			self.data.zoomlevel = zoom
		elseif zoom < 20 then
			self.data.zoomlevel = math.floor(zoom)
		else
			self.data.zoomlevel = 20
		end
	end

	local zoomget = self.minimap:GetZoom()
	local zoomset,zoomscale = math.modf(self.data.zoomlevel)
	local zoomcalc = math.floor(self.data.zoomlevel-zoomget)
	self.minimap:Zoom( zoomcalc )
	local uvscale = zoomset > 0 and 1 or 1-(1-zoomscale)*0.9 -- 1.0~1.9

	local scrx,scry = TheSim:GetScreenSize()
	local sx = math.max(self.data.size_w, self.data.size_h*scrx/scry)
	local sy = math.max(self.data.size_h, self.data.size_w*scry/scrx)
	local scx = 2 - self.data.size_w/sy * scry/scrx * uvscale
	local scy = 2 - self.data.size_h/sx * scrx/scry * uvscale
	self.img:SetUVScale( scx, scy )
	-----add------
	self.uvscale = {x = scx, y = scy}
	--------------
	self.memory.zoom = nil--// handle redraw
end


--------------------------------------------------------------------


-----------------------------ADD AUTOWALK--------------------------
function AddAutoMoveForSmallMap(self)
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
	self.paintWidget:SetScissor(-self.data.size_w/2,-self.data.size_h/2,self.data.size_w,self.data.size_h)

	local old_resizer_controlfn = self.resizer._controlfn
	self.resizer._controlfn = function(inst, cursor)
        old_resizer_controlfn(inst, cursor)
        -- setscissor following the resizer
        if not self.data.lock_resize then
            self.paintWidget:SetScissor(-self.data.size_w/2,-self.data.size_h/2,self.data.size_w,self.data.size_h)
        end
	end
	------------------------SHOW PATH LINES-----------------------------
	-- add pathline widget 
	if GetModConfigData("PATHLINE_ENABLE") then
		self.pathLineGroup = self.paintWidget:AddChild(PathLineGroup(self,line_xml,line_texName))
		self.pathLineGroup:SetLineTint(1,1,1,0.8)
		self.pathLineGroup:SetLineDefaultHeight(30)
	end
		
	-----------------------SHOW DEST ICON------------------------------
	-- to hide the icon outside the minimap area, i add it as pathlinegroup's child
	if GetModConfigData("ICON_ENABLE") then
		self.destIconImage = self.paintWidget:AddChild(DestIcon(self,icon_xml,icon_texName))
		self.destIconImage:SetDefaultScale(0.25)
	end
end
AddClassPostConstruct("widgets/smallmap",
	function(self)
		
		self.GetCursorPosition = SmallMap_GetCursorPosition
		self.GetWorldPositionAtCursor = SmallMap_GetWorldPositionAtCursor
		self.WorldPosToScreenPos = SmallMap_WorldPosToScreenPos
		self.SetZoom = SmallMap_SetZoom
		
		self:SetZoom(self.data.zoomlevel)-- to get self.uvscale during init
		
		AddAutoMoveForSmallMap(self)
		--AddResetKeyForSmallmap(self)--it has the reset button already,should i add this ?
end)

