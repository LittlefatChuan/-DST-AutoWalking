local PLAYER_PHYS_RADIUS = 0.5 --the physics radius of the player = 0.5
local offset = PLAYER_PHYS_RADIUS

local NGL_ObstaclePFWall = Class(function(self, inst)
	self.inst = inst
	self.lastpos = nil
	self.lastrad = nil
	self.physrad_override = nil
	--self.gonna_remove = false
	self.init_task = self.inst:DoTaskInTime(0,function() self:Init();self.init_task = nil end)
	if TheWorld.ismastersim then
		--Server function 
		
		--we should wait until position has been located
		self.onputininventory = function()
			self.lift_task = self.inst:DoTaskInTime(0.5,function()
									self:RemoveWallSafely()
									self.lift_task = nil
								end)
		end
		
		self.ondropped = function()
			self.drop_task = self.inst:DoTaskInTime(0.5,function()
									self:AddWallSafely()
									self.drop_task = nil
								end)
		end
		

		
	else
		--Client function(see function add_heavy_equip_listener in tweak_avoid_obstacles.lua)
		
		-- self.onequip = function(player, data)
			-- if data.item == self.inst  then
				-- self:RemoveWallSafely()
			-- end		
		-- end
		
		-- self.onunequip = function(player, data)
			-- if data.item == self.inst and data.eslot == EQUIPSLOTS.BODY then
				-- --self.unequip_task = self.inst:DoTaskInTime(0.5,function()
									-- self:AddWallSafely()
				-- --					self.unequip_task = nil
				-- --				end)
			-- end			
		-- end
		

	 end
	--Common function
	self.frozenfn_snowlevel = function (self, snowlevel)
		if snowlevel > .02 then
			if not self.frozen then
			self.frozen = true
			--self.freeze_task = self.inst:DoTaskInTime(0.1,function()
								self:RemoveWallSafely()
			--					self.freeze_task = nil
			--				end)
			end
		elseif self.frozen then
			self.frozen = false
			--self.unfreeze_task = self.inst:DoTaskInTime(0.1,function()
								self:AddWallSafely()
			--					self.unfreeze_task = nil
			--				end)
		end
	end
	
	self.sandstormfn_toggle = function ()
		local sandstorm = self.sandstorm
		local isactive = not (sandstorm.wetness >0 or sandstorm.snowlevel >0 ) and sandstorm.issummer 
		if sandstorm.isactive ~= isactive then
			if isactive then
				--self.fill_task = self.inst:DoTaskInTime(0.1,function()
									self:AddWallSafely()
				--					self.fill_task = nil
				--				end)
			else 
				--self.unfill_task = self.inst:DoTaskInTime(0.1, function()
									self:RemoveWallSafely()
				--					self.unfill_task = nil
				--				end)
			end
			sandstorm.isactive = isactive
		end		
	
	
	end
	
	self.sandstormfn_issummer = function (self, issummer)
		if self.sandstorm == nil then
			self.sandstorm = {issummer = false, wetness = 0, snowlevel = 0, isactive = false}
		end

		self.sandstorm.issummer = issummer
		self.sandstormfn_toggle()
	end
	
	self.sandstormfn_wetness = function (self, wetness)
		if self.sandstorm == nil then
			self.sandstorm = {issummer = false, wetness = 0, snowlevel = 0, isactive = false}
		end

		self.sandstorm.wetness = wetness
		self.sandstormfn_toggle()
	end
	
	self.sandstormfn_snowlevel = function (self, snowlevel)
		if self.sandstorm == nil then
			self.sandstorm = {issummer = false, wetness = nil, snowlevel = nil, isactive = false}
		end

		self.sandstorm.snowlevel = snowlevel
		self.sandstormfn_toggle()
	end
	
	
	-- self.on_sandstorm = function (inst, data)
		-- sayfortest()
		-- if self.sandstorm == nil then
			-- self.sandstorm = {issummer = false, iswet = false, isactive = false}
		-- end
		
		-- if data.season then
			-- self.sandstorm.issummer = (data.season == SEASONS.SUMMER)
		-- end
		-- if data.wetness and data.snowlevel then
			-- self.sandstorm.iswet = (data.wetness > 0 or data.snowlevel > 0)
		-- end
		
		-- local isactive = self.sandstorm.iswet and self.sandstorm.issummer 
		-- if self.sandstorm.isactive ~= isactive then
			-- if isactive then
				-- --self.fill_task = self.inst:DoTaskInTime(0.1,function()
									-- self:AddWallSafely()
				-- --					self.fill_task = nil
				-- --				end)
			-- else 
				-- --self.unfill_task = self.inst:DoTaskInTime(0.1, function()
									-- self:RemoveWallSafely()
				-- --					self.unfill_task = nil
				-- --				end)
			-- end
			-- self.sandstorm.isactive = isactive
		-- end
	 
end)



function NGL_ObstaclePFWall:HasWall()
	return (self.last_pos ~= nil and self.last_rad ~= nil)
end


--get the centerpos of square
function NGL_ObstaclePFWall:GetWallPos()
	return self.last_pos or nil
end


--the wall area is a big square combined with 1x1 square 
--get the radius of incircle 
function NGL_ObstaclePFWall:GetWallRadius()
	return self.last_rad and self.last_rad + offset or nil
end

function NGL_ObstaclePFWall:GetDebugString()
	local s = "WallSquare: unset"
	if self:HasWall() then
		local x, y , z = self:GetWallPos():Get()
		local rad = self:GetWallRadius()
		s = string.format("WallSquare: centerpos: %.2f, %.2f, %.2f; incicle radius: %.2f",x,y,z,rad)
	end
	return s
end


--Add a combined big Square that can cover the physics circle
function NGL_ObstaclePFWall:AddWall()
	if self.inst:GetCurrentPlatform() ~= nil then return end
	local x, _, z = self.inst.Transform:GetWorldPosition()
	local physrad = self.physrad_override or self.inst:GetPhysicsRadius(0)

		for x_offset = physrad-0.5+offset, math.max(-physrad,-0.5), -1 do
			for z_offset = physrad-0.5+offset, math.max(-physrad,-0.5), -1 do
				for x_sign = -1,1,2 do
					for z_sign = -1,1,2 do 
						--tell the pathfiner we should bypass this area
						--the unit wall area is square of 1x1 ,center point as parameter
						TheWorld.Pathfinder:AddWall(x+x_offset*x_sign, 0, z+z_offset*z_sign)
					end
				end
			end
		end
		
	--end
	self.last_pos = Vector3(x, 0, z)
	self.last_rad = physrad
	
	--print(self.inst.prefab.." add wall",x,0,z)
end

--it will remove the former wall before adding a new wall 
function NGL_ObstaclePFWall:AddWallSafely(force)
	
	self:RemoveWallSafely(force)
	self:AddWall()
end


function NGL_ObstaclePFWall:RemoveWall()
	local pos = self.last_pos or self.inst:GetPosition()
	local x, _, z = pos:Get() 
	local physrad = self.physrad_override or self.last_rad or self.inst:GetPhysicsRadius(0)

	
		for x_offset = physrad-0.5+offset, math.max(-physrad,-0.5), -1 do
			for z_offset = physrad-0.5+offset, math.max(-physrad,-0.5), -1 do
				for x_sign = -1,1,2 do
					for z_sign = -1,1,2 do 
						TheWorld.Pathfinder:RemoveWall(x+x_offset*x_sign, 0, z+z_offset*z_sign)
					end
				end
			end
		end
		
		
	--restore the pos and rad ,use for recover overlap walls
	self.recover_pos = self.last_pos
	self.recover_rad = self.last_rad
	self.last_pos = nil
	self.last_rad = nil
	--print(self.inst.prefab.." remove wall",x,0,z)

end

--it will remove wall only when it has added a wall before
function NGL_ObstaclePFWall:RemoveWallSafely(force)
	if (self.last_pos == nil or self.last_rad == nil) and not force then return end
	self:RemoveWall()
	self:RecoverOverlapWall()

end



--if we remove the overlap area with others by accident
--we should tell him to update it. or readd it ?
function NGL_ObstaclePFWall:RecoverOverlapWall()
	local pos = self.recover_pos or self.inst:GetPosition()
	local x, y, z = pos:Get()
	--local physrad_override = self.inst.components.heavyobstaclephysics and 0.45 or nil
	local physrad = self.physrad_override or self.recover_rad or self.inst:GetPhysicsRadius(0)
	local blockers_nearby = TheSim:FindEntities(x,y,z,math.sqrt(2)*(physrad + offset),{"blocker"})

	for k, v in ipairs (blockers_nearby) do
		if v ~= self.inst 
			and v.components.ngl_obstaclepfwall 
				--and not v.components.ngl_obstaclepfwall.gonna_remove then
				and v.components.ngl_obstaclepfwall:HasWall() then
			
			v.components.ngl_obstaclepfwall:UpdateWall()
			--print(v.prefab.." recover wall",x,0,z)
			
			
		end
			
	end
	self.recover_pos = nil
	self.recover_rad = nil

end


function NGL_ObstaclePFWall:UpdateWall(force)
	local pos = self.inst:GetPosition()
	local rad = self.inst:GetPhysicsRadius(0)
	if self.last_pos and self.last_rad 
		and (pos ~= self.last_pos or rad < self.last_rad) then
				self:RemoveWallSafely(force)
	end
		self:AddWallSafely()
	
end


function NGL_ObstaclePFWall:AddWallOnSpawn()
	--self.inst:DoTaskInTime(0,function()
								self:AddWallSafely()
	--						end)
	--we have waitted in init_task,we may dont need to wait again
end

function NGL_ObstaclePFWall:RemoveWallOnRemove()
	local _Remove = self.inst.Remove
	self.inst.Remove = function ()
		--self.gonna_remove = true
		self:RemoveWallSafely()
		return _Remove(self.inst)
	end
end

local function onispathfindingdirty(inst)
	local pfwall = inst.components.ngl_obstaclepfwall
	if pfwall ~= nil then
		if inst._ispathfinding:value() then
			pfwall:AddWallSafely()
		else
			pfwall:RemoveWallSafely()
		end
	end
end

function NGL_ObstaclePFWall:UpdateWallOnIsPathFindingDirty()
	self.inst:ListenForEvent("onispathfindingdirty",onispathfindingdirty)
	--print(self.inst.prefab.."add active listener")
end



function NGL_ObstaclePFWall:UpdateWallOnCarried()
	if TheWorld.ismastersim then
		self.inst:ListenForEvent("onputininventory",self.onputininventory)
		--Also,we should do it after position has been set 
		self.inst:ListenForEvent("ondropped",self.ondropped)
		self.heavy_listeners_server = true
											
	else --listen for ThePlayer instead in client(see tweak_avoid_obstacles.lua)
		-- self.inst:ListenForEvent("equip", self.onequip, ThePlayer)
		-- self.inst:ListenForEvent("unequip", self.onunequip, ThePlayer)
		-- self.heavy_listeners_client = true
		
	end

end


local alterable_obstacles_snowlevel = {["pond"] = true,["pond_mos"] = true}
local alterable_obstacles_sandstorm = {["oasislake"] = true}

local function is_alterable_obstacles(inst)
	return alterable_obstacles_snowlevel[inst.prefab] or alterable_obstacles_sandstorm[inst.prefab]
end



--TODO:It doesnt work in client,no fishable component in client
--maybe we should add a netvar(if we are in a server mod)
--and maybe we have another stupid way if we are in a client mod
function NGL_ObstaclePFWall:UpdateWallOnFreeze()
	-- if TheWorld.ismastersim then
		-- local fishable = self.inst.components.fishable
		-- if fishable == nil then return end
		
		-- local _Freeze = fishable.Freeze
		-- local _Unfreeze = fishable.Unfreeze
		
		-- fishable.Freeze = function()
			-- self:RemoveWallSafely()
			-- return _Freeze(self.inst)
		-- end
		
		-- fishable.Unfreeze = function()
			-- self:AddWallSafely()
			-- return _Unfreeze(self.inst)
		-- end
	-- else
		if alterable_obstacles_snowlevel[self.inst.prefab] then
			self:WatchWorldState("snowlevel", self.frozenfn_snowlevel)
			self.frozenfn_snowlevel(self,TheWorld.state.snowlevel)
			self.watching_frozen = true
		elseif alterable_obstacles_sandstorm[self.inst.prefab] then
			self:WatchWorldState("issummer", self.sandstormfn_issummer)
			self:WatchWorldState("wetness", self.sandstormfn_wetness)
			self:WatchWorldState("snowlevel", self.sandstormfn_snowlevel)
			self.sandstormfn_issummer(self,TheWorld.state.issummer)
			self.sandstormfn_wetness(self,TheWorld.state.wetness)
			self.sandstormfn_snowlevel(self,TheWorld.state.snowlevel)
			-- self.inst:ListenForEvent("weathertick", self.on_sandstorm)
			-- self.inst:ListenForEvent("seasontick", self.on_sandstorm)
			-- local state = TheWorld.state
			-- self.on_sandstorm(self.inst, {season = state.season, wetness = state.wetness, snowlevel = state.snowlevel})
			self.watching_sandstorm = true
		end
	-- end
end

function NGL_ObstaclePFWall:Init()
	self:AddWallOnSpawn()
	self:RemoveWallOnRemove()
	if self.inst._ispathfinding then
		self:UpdateWallOnIsPathFindingDirty()
		
	end
	 
	if self.inst.components.heavyobstaclephysics or self.inst:HasTag("heavy") then
		self:UpdateWallOnCarried()
	end
	if self.inst.components.fishable or is_alterable_obstacles(self.inst) then
		self:UpdateWallOnFreeze()
		--print(self.inst.prefab.."added freeze listener")
	end
end

function NGL_ObstaclePFWall:OnRemoveFromEntity()
	
	if self.init_task ~= nil then
		self.init_task:Cancil()
		self.init_task = nil
	end
	--server heavyobstacle-carry task
	if self.lift_task ~= nil then
		self.lift_task:Cancil()
		self.lift_task = nil
	end
	if self.drop_task ~= nil then
		self.drop_task:Cancil()
		self.drop_task = nil
	end
	--client heavyobstacle-carry task
	if self.equip_task ~= nil then
		self.equip_task:Cancil()
		self.equip_task = nil
	end
	if self.unequip_task ~= nil then
		self.unequip_task:Cancil()
		self.unequip_task = nil
	end
	-- if self.freeze_task ~= nil then
		-- self.freeze_task:Cancil()
		-- self.freeze_task = nil
	-- end
	-- if self.unfreeze_task ~= nil then
		-- self.unfreeze_task:Cancil()
		-- self.unfreeze_task = nil	
	-- end
	-- if self.fill_task ~= nil then
		-- self.fill_task:Cancil()
		-- self.fill_task = nil
	-- end
	-- if self.unfill_task ~= nil then
		-- self.unfill_task:Cancil()
		-- self.unfill_task = nil
	-- end
	if self.watching_frozen then
		self:StopWatchingWorldState("snowlevel",self.frozenfn_snowlevel)
	end
	if self.watching_sandstorm then
		self:StopWatchingWorldState("issummer",self.sandstormfn_issummer)
		self:StopWatchingWorldState("wetness",self.sandstormfn_wetness)
		self:StopWatchingWorldState("snowlevel",self.sandstormfn_snowlevel)
	end
	-- if self.heavy_listeners_client then
		-- self.inst:RemoveEventCallback("equip",self.onequip,ThePlayer)
		-- self.inst:RemoveEventCallback("onunequip",self.onunequip,ThePlayer)
	-- end
	if self.heavy_listeners_server then
		self.inst:RemoveEventCallback("onputininventory",self.onputininventory)
		self.inst:RemoveEventCallback("ondropped",self.ondropped)
	end
	
	self:RemoveWallSafely()
end
return NGL_ObstaclePFWall