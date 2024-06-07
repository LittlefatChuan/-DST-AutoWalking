local Text = require "widgets/text"
local Image = require "widgets/image"
local Widget = require "widgets/widget"

---------------------------PathLine---------------------------------

local PathLine = Class(Image, function(self, atlas, tex)
	Image._ctor(self, atlas, tex, tex)
	self.default_h = 50
	-- be careful it's just only fit to Horizontal PathLine
	self:SetVRegPoint(ANCHOR_MIDDLE)
	self:SetHRegPoint(ANCHOR_LEFT)
end)

function PathLine:AdjustToPoints(startpos_x, startpos_y, endpos_x, endpos_y, zoom)
	
	local linevec_x, linevec_y = endpos_x - startpos_x, endpos_y - startpos_y
	
	local length = VecUtil_Length(linevec_x, linevec_y)
	local w,h = self:GetSize()
	local height = zoom and (self.default_h / math.pow(zoom, 0.5)) or h
	self:SetSize(length, height) -- remain a wide area to get focus
	
	-- be careful it's just only fit to Horizontal PathLine
	local angle = -VecUtil_GetAngleInDegrees(linevec_x, linevec_y) 
	self:SetRotation(angle)
	
	self:SetPosition(startpos_x, startpos_y)
end

function PathLine:SetDefaultHeight(h)
	self.default_h = h
end

--------------------------------PathLineGroup----------------------------

local updateFns = {
	MapWidget = function(self, path)
		if path == nil or self.lineImages == nil or #self.lineImages == 0 then
			return
		end
		local mapwidget = self.mapwidget
		local zoom = mapwidget.minimap:GetZoom()
	
		-- update the position of lineImages,make them following the map zoom and offset
		
		local cur_step = path.currentstep
		local last_x, last_y = nil, nil
		for i, step in ipairs(path.steps) do

			local screen_x, screen_y = mapwidget:WorldPosToScreenPos(step.x, step.z)
			
			local lineIndex = i - 1
			local line = self.lineImages[lineIndex]
			if (lineIndex >= 1 and line ~= nil) then

				if (cur_step ~= nil and ThePlayer ~= nil) then
					if(lineIndex == cur_step - 1) then	-- cur_step = 2 --> lineImages[1] 's startPos keeps following player Pos
						-- current line keeps following player's position
						local player_worldpos_x, _, player_worldpos_z = ThePlayer:GetPosition():Get()
						local player_screenpos_x, player_screenpos_y = mapwidget:WorldPosToScreenPos(player_worldpos_x, player_worldpos_z)
						line:AdjustToPoints(player_screenpos_x, player_screenpos_y, screen_x, screen_y, zoom)
						
						if(line:IsVisible() == false) then
							line:Show()
						end						
					elseif(lineIndex <= cur_step - 2) then	-- cur_step = 3 --> hide lineImages[1]
						-- stop update and hide the lineImages, according the step we have passed
						if(line:IsVisible() == true) then
							line:Hide()
						end
					else
						-- show all the others
						line:AdjustToPoints(last_x, last_y, screen_x, screen_y, zoom)
						
						if(line:IsVisible() == false) then
							line:Show()
						end
					end
				end
			end
			
			last_x = screen_x
			last_y = screen_y
		end	
	end,
	
	MiniMapWidget = function(self, path)
		if path == nil or self.lineImages == nil or #self.lineImages == 0 then
			return
		end
		
		
		local minimapwidget = self.mapwidget
		local img = minimapwidget.img
		local img_w, img_h = img:GetSize()
		
		self:SetPosition(img:GetPosition():Get())
		
		local zoom = minimapwidget.minimap:GetZoom()

		-- update the position of lineImages,make them following the map zoom and offset
		
		local cur_step = path.currentstep
		local last_x, last_y = nil, nil
		for i, step in ipairs(path.steps) do

			local screen_x, screen_y = minimapwidget:WorldPosToScreenPos(step.x, step.z)
			
			local lineIndex = i - 1
			local line = self.lineImages[lineIndex]
			if (lineIndex >= 1 and line ~= nil) then

				if (cur_step ~= nil and ThePlayer ~= nil) then
					if(lineIndex == cur_step - 1) then	-- cur_step = 2 --> lineImages[1] 's startPos keeps following player Pos
						-- current line keeps following player's position
						local player_worldpos_x, _, player_worldpos_z = ThePlayer:GetPosition():Get()
						local player_screenpos_x, player_screenpos_y = minimapwidget:WorldPosToScreenPos(player_worldpos_x, player_worldpos_z)
						line:AdjustToPoints(player_screenpos_x, player_screenpos_y, screen_x, screen_y, zoom)
						
						if(line:IsVisible() == false) then
							line:Show()
						end						
					elseif(lineIndex <= cur_step - 2) then	-- cur_step = 3 --> hide lineImages[1]
						-- stop update and hide the lineImages, according the step we have passed
						if(line:IsVisible() == true) then
							line:Hide()
						end
					else
						-- show all the others
						line:AdjustToPoints(last_x, last_y, screen_x, screen_y, zoom * minimapwidget.uvscale)
						
						if(line:IsVisible() == false) then
							line:Show()
						end
					end
				end
			end
			
			last_x = screen_x
			last_y = screen_y
		end
	end,
	
	SmallMap = function(self, path)
		if path == nil or self.lineImages == nil or #self.lineImages == 0 then
			return
		end
		

		local smallmap = self.mapwidget
		local img = smallmap.img
		local img_w, img_h = img:GetSize()
		
		self:SetPosition(img:GetPosition():Get())

		local zoom = smallmap.minimap:GetZoom()

		-- update the position of lineImages,make them following the map zoom and offset
		
		local cur_step = path.currentstep
		local last_x, last_y = nil, nil
		for i, step in ipairs(path.steps) do

			local screen_x, screen_y = smallmap:WorldPosToScreenPos(step.x, step.z)
			
			local lineIndex = i - 1
			local line = self.lineImages[lineIndex]
			if (lineIndex >= 1 and line ~= nil) then

				if (cur_step ~= nil and ThePlayer ~= nil) then
					if(lineIndex == cur_step - 1) then	-- cur_step = 2 --> lineImages[1] 's startPos keeps following player Pos
						-- current line keeps following player's position
						local player_worldpos_x, _, player_worldpos_z = ThePlayer:GetPosition():Get()
						local player_screenpos_x, player_screenpos_y = smallmap:WorldPosToScreenPos(player_worldpos_x, player_worldpos_z)
						line:AdjustToPoints(player_screenpos_x, player_screenpos_y, screen_x, screen_y, zoom)
						
						if(line:IsVisible() == false) then
							line:Show()
						end						
					elseif(lineIndex <= cur_step - 2) then	-- cur_step = 3 --> hide lineImages[1]
						-- stop update and hide the lineImages, according the step we have passed
						if(line:IsVisible() == true) then
							line:Hide()
						end
					else
						-- show all the others
						line:AdjustToPoints(last_x, last_y, screen_x, screen_y, zoom * smallmap.uvscale.x)
						
						if(line:IsVisible() == false) then
							line:Show()
						end
					end
				end
			end
			
			last_x = screen_x
			last_y = screen_y
		end
	end,
}


local PathLineGroup = Class(Widget, function(self, mapwidget, atlas, tex)
    Widget._ctor(self, "PathLineGroup")
    self.mapwidget = mapwidget
	self.lineImages = {}
	self.line_default_h = 50
	self.line_atlas = atlas 
	self.line_tex = tex	
	self.UpdateLinesPosition = mapwidget and updateFns[mapwidget.name] or nil
	self.tint = {1,1,1,1}
	--self.path = nil
	
	if self.UpdateLinesPosition then
		self:StartUpdating()
	end
  
end)

function PathLineGroup:InsertLines(amount)
	for i = 1,amount do
		local line = self:AddChild(PathLine(self.line_atlas, self.line_tex))
		local tint = self.tint
		line:SetTint(tint[1],tint[2],tint[3],tint[4])
		line:SetDefaultHeight(self.line_default_h)
		line:Hide()	
		table.insert(self.lineImages, line)
	end
end

function PathLineGroup:SetLineTint(r, g, b , a)
	self.tint = {r,g,b,a}
	if not self:IsEmpty() then
		for _,v in ipairs(self.lineImages) do
			v:SetTint(r,g,b,a)
		end
	end
end

function PathLineGroup:SetLineDefaultHeight(h)
	self.line_default_h = h
	if not self:IsEmpty() then
		for _,v in ipairs(self.lineImages) do
			v:SetDefaultHeight(h)
		end
	end
end

function PathLineGroup:Clear()
	for _,v in ipairs(self.lineImages) do
		v:Kill()
	end
	self.lineImages = {}
end

function PathLineGroup:Count()
	return #(self.lineImages)
end

function PathLineGroup:IsEmpty()
	return self:Count() == 0
end

function PathLineGroup:OnGainFocus()
	if not self:IsEmpty() then
		for _,v in ipairs(self.lineImages) do
			v:SetTint(self.tint[1],self.tint[2],self.tint[3], self.tint[4] * 0.25)
		end
	end
end

function PathLineGroup:OnLoseFocus()
	if not self:IsEmpty() then
		for _,v in ipairs(self.lineImages) do
			v:SetTint(self.tint[1],self.tint[2],self.tint[3], self.tint[4])
		end
	end
end

function PathLineGroup:OnUpdate(dt)

	local pathfollower = ThePlayer and ThePlayer.components.ngl_pathfollower
	local path = pathfollower and pathfollower.path

	-- no path
	if path == nil then
		-- clear the lines
		if not self:IsEmpty() then
			self:Clear()
		end
		-- dont show if no path
		return
	end

	-- has path
		-- add the lines if we have no any line
	if self:IsEmpty() then
		self:InsertLines(#path.steps - 1) -- n points need n-1 lines
		-- clear the wrong lines remained at last time
	elseif self:Count() ~= #path.steps - 1 then
		self:Clear()
	end
		-- update lines position if path exists
		self:UpdateLinesPosition(path)

end
-- -- auto update by tracking the path data
-- function PathLineGroup:BindingPath(path)
	-- self.path = path
-- end

return PathLineGroup