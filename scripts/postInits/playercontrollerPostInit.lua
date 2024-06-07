local interrupt_controls = {}

--the keys to stop the autowalking 
for control = CONTROL_ATTACK, CONTROL_MOVE_RIGHT do
    interrupt_controls[control] = true	 
end

local function IsInGame()
	return ThePlayer and ThePlayer.HUD
end

local function IsInTyping()
	return  ThePlayer.HUD:HasInputFocus()
end

local function IsInMap()
	return ThePlayer.HUD:IsMapScreenOpen()

end

local function IsCursorOnHUD()
	local input = TheInput
	return input.hoverinst and input.hoverinst.Transform == nil
	--idk why function GetHUDEntityUnderMouse() sometime return false because of the hoverinst.entity:Isvalid()
	--so i remove it 
end


--keybind to stop the autowalking and remove the mappin(the dest icon)
AddComponentPostInit("playercontroller",function(self)
	local OnControl_old = self.OnControl
	 self.OnControl = function(self, control, down)
	 
		
		local pathfollower = ThePlayer and ThePlayer.components.ngl_pathfollower
		if pathfollower and pathfollower:HasDest() and IsInGame()then
			
			--print("InGame",IsInGame(),"InMap:",IsInMap(),"Intype:",IsInTyping())
			--when you open the map and type in command box it actually IsNotInMap
			
			--press Direction key in game screen
			if not IsInMap() and not IsInTyping() and interrupt_controls[control] then
				pathfollower:ForceStop()
			--press space key in map screen	
			elseif IsInMap() and control == CONTROL_ACTION then
				pathfollower:ForceStop()
			--press mouse key except your backpack,craftmenu and other HUD
			elseif not IsInMap() and not IsInTyping() and not IsCursorOnHUD() and (control == CONTROL_PRIMARY or control == CONTROL_SECONDARY) then
				pathfollower:ForceStop()
				--print("hoverinst:",TheInput.hoverinst,"valid:",TheInput.hoverinst.entity:IsValid(),"visible:",TheInput.hoverinst.entity:IsVisible())
			end
		end
		return OnControl_old(self, control, down)
	
	end
	

end)