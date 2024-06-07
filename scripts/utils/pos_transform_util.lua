-- some useful position transform functions:
-- i use these functions in widgetPostInits folder
function WorldPosToScreenPos(self, x, z)
	local screen_width, screen_height = TheSim:GetScreenSize()
	local half_x, half_y = RESOLUTION_X / 2, RESOLUTION_Y / 2 
	local map_x, map_y = TheWorld.minimap.MiniMap:WorldPosToMapPos(x, z, 0)
	local screen_x = ((map_x * half_x) + half_x) / RESOLUTION_X * screen_width 
	local screen_y = ((map_y * half_y) + half_y) / RESOLUTION_Y * screen_height
	return screen_x, screen_y
end

local function MiniMapWidget_GetMapPosition(self)
	local x_cursor, y_cursor = TheSim:GetPosition()
	local x_widgetcenter, y_widgetcenter = self.img:GetWorldPosition():Get()
	local w, h = self.img:GetSize()
	local scale = self.img:GetScale()
	local x = (x_cursor - x_widgetcenter)*(2-self.uvscale)/scale.x + w/2
	local y = (y_cursor - y_widgetcenter)*(2-self.uvscale)/scale.y + h/2
	x = 2 * x / w - 1
    y = 2 * y / h - 1
	return x, y
end

local function MiniMapWidget_GetWorldPositionAtCursor(self)
    local x, y = self:GetCursorPosition()
    x, y = self.minimap:MapPosToWorldPos(x, y, 0)
    return x, 0, y 
end

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



