-- discord: @sniperlaserdemon  roblox: SniperLaserDemon
-- This script is Finite State Machine for NPC

local Players = game:GetService("Players")

-- CONSTANTS --

const ATTACK_COOLDOWN = 1
const ATTACK_RANGE = 3
const MAX_VIEW_ANGLE = 100
const WANDER_TIME = 2
const MAX_WANDER_OFFSET = 30
const WAYPOINT_RADIUS_THRESHOLD = 1
const MAX_BLIND_PURSUIT_TIME = 4
const PATH_TO_TARGET_COMPUTE_DELAY = 1

-- This function is used to check when the player's character is not behind an obstacle
local function IsNotBehindObstacle(npc, npcHead, character, rootPart)
	local directionToPlayer = (rootPart.Position - npcHead.Position)
	
	local visibilityRaycast = workspace:Raycast(npcHead.Position, directionToPlayer, npc.RayParams) -- Cast ray from NPC's head to character's rootPart
	if visibilityRaycast then -- If raycast hit something
		local hitPart = visibilityRaycast.Instance -- Get part that raycast hit
		
		if hitPart:IsDescendantOf(character) then -- Check that the hitPart belongs to the player's character 
			return true
		else
			return false
		end
	end
	
	return true
end

-- This function checks whether the character is within the NPC's field of view
local function IsInFieldOfView(npcHead, lookPoint)
	local headLookDirection = npcHead.CFrame.LookVector -- NPC's head look direction
	local directionToPlayer = (lookPoint - npcHead.Position).Unit -- Normalized direction from NPC's head to lookPoint
	local lookDotProduct = headLookDirection:Dot(directionToPlayer) -- Get Dot product
	local lookAngle = math.deg(math.acos(lookDotProduct)) -- Get degrees from Dot product
	
	if lookAngle > MAX_VIEW_ANGLE then -- Check for max field of view
		return false
	end
	
	return true
end

-- This function search for nearest and visible player's character
local function SeekForCharacter(npc)
	local closest = nil -- Variable for storing a character
	local distance = math.huge -- For nearest character check
	
	for _, player in ipairs(Players:GetPlayers()) do -- Iterate through all players in game
		local character = player.Character
		if not character then continue end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then continue end
		
		local distanceToPlayer = (rootPart.Position - npc.HumanoidRootPart.Position).Magnitude -- Get distance from NPC to character
		
		if distanceToPlayer < distance then -- Check if distanceToPlayer lower than the last nearest distance
			if not IsInFieldOfView(npc.Head, rootPart.Position) then continue end -- Self-explanatory function names
			if not IsNotBehindObstacle(npc, npc.Head, character, rootPart) then continue end
			
			distance = distanceToPlayer -- set lowest distance to character
			closest = character -- Set nearest character
		end
	end
	
	return closest
end

-- This function gets random point around NPC
local function GetRandomPointNearNPC(npc)
	local offset = Vector3.new(
		math.random(-MAX_WANDER_OFFSET, MAX_WANDER_OFFSET), -- X random offset
		0, -- We dont need Y
		math.random(-MAX_WANDER_OFFSET, MAX_WANDER_OFFSET) -- Z random offset
	)
	
	local newPosition = npc.HumanoidRootPart.Position + offset -- Get random point around NPC
	local distance = (newPosition - npc.HumanoidRootPart.Position).Magnitude -- Get distance from random point to NPC
	if distance < 1 then return end -- If NPC soooo close to random point, return
	
	return newPosition
end

-- This function checks whether the destinationPoint isnt inside the object (if it is inside, NPC wont be able to reach it)
local function IsDestinationPointReachable(npc, destinationPoint)
	local npcModel = npc.Model
	local npcSize = npcModel:GetExtentsSize() -- Get NPC's model size
	
	-- Create bounding box and get parts withing it
	local boundingParts = workspace:GetPartBoundsInBox(
		CFrame.new(destinationPoint),
		npcSize,
		npc.OverlapParams -- We dont want NPC to touch the bounding box (FilterDescendantInstances = {npc.Model})
	)
	
	for _, part in ipairs(boundingParts) do -- For every part in bounding box
		if part.CanCollide then -- If collidable
			return false
		end
	end
	
	return true
end

-- This function computes path to destinationPoint
local function ComputePathToPoint(npc, destinationPoint)
	if npc.IsPathComputing then return end
	npc.IsPathComputing = true -- Using for debounce (because :ComputeAsync() is async method, but .Heartbeat runs every 1/60 secs)
	
	local path = npc.Path
	
	local success, errorMsg = pcall(function() -- Using pcall because :ComputeAsync() can fail and throw error
		path:ComputeAsync(npc.HumanoidRootPart.Position, destinationPoint)
	end)
	npc.IsPathComputing = false -- NPC can compute path again
	
	if success then
		if path.Status == Enum.PathStatus.Success then -- Check if path successful
			return true
		end
	else
		warn(errorMsg) -- Error message to console
	end
	
	return false
end

-- Just gets path waypoints
local function GetPathWaypoints(npc)
	return npc.Path:GetWaypoints()
end

-- Attack target with ATTACK_COOLDOWN
local function AttackTarget(npc, target)
	local targetHumanoid = target:FindFirstChild("Humanoid") -- Get target's humanoid
	if not targetHumanoid then return end
	
	-- Check for attack cooldown
	if (workspace:GetServerTimeNow() - npc.LastAttackTime) < ATTACK_COOLDOWN then return end
	npc.LastAttackTime = workspace:GetServerTimeNow() -- Set last attack time for cooldown
	
	targetHumanoid:TakeDamage(npc.Damage) -- Damage target
end

--[[
	State Machine behaviour functions
	
	Init = called in the :SetState() method once
	Update = called every frame in .Heartbeat event
]]
return {
	Idle = {
		Init = function(npc)
			if not npc.Humanoid then return end -- Check for NPC's humanoid
			
			npc.Humanoid:Move(Vector3.zero) -- Stop moving
		end,
		
		Update = function(npc)
			local targetCharacter = SeekForCharacter(npc) -- Get target
			
			if targetCharacter then -- If target was found
				npc:SetTarget(targetCharacter)
				npc:SetState("Pursuit") -- Change state to "Pursuit"
			else -- If target was not found
				local timeFromLastWander = (workspace:GetServerTimeNow() - npc.LastWanderTime) -- Get elapsed time from last wandering
				
				if timeFromLastWander >= WANDER_TIME then -- Check for time threshold
					local randomPointNearNPC = GetRandomPointNearNPC(npc) -- Get random point near NPC
					if not randomPointNearNPC then return end
					
					-- Just checks
					if not IsDestinationPointReachable(npc, randomPointNearNPC) then return end
					if not ComputePathToPoint(npc, randomPointNearNPC) then return end -- Using "if else" condition to check that a path has been found
					
					npc:SetPath(GetPathWaypoints(npc)) -- Set path waypoints to NPC
					npc:SetState("Wander") -- Change state to "Wander"
				end
			end
		end,
	},
	
	Wander = {
		Init = function(npc)
			if not npc.Humanoid then return end
			
			npc.Humanoid.WalkSpeed = 10 -- Change humanoid WalkSpeed
		end,
		
		Update = function(npc)
			-- Some checks
			if not npc.Humanoid then return end
			if not npc.HumanoidRootPart then return end
			
			local targetCharacter = SeekForCharacter(npc) -- Get target

			if targetCharacter then -- If target was found
				npc:SetTarget(targetCharacter)
				npc:SetState("Pursuit") -- Change state to "Pursuit"
			else -- If target was not found
				local nextWaypoint = npc.Waypoints[npc.NextWaypointIndex] -- Get next waypoint for move

				if nextWaypoint then
					local moveToPosition = nextWaypoint.Position
					moveToPosition = Vector3.new(moveToPosition.X, npc.HumanoidRootPart.Position.Y, moveToPosition.Z) -- Set moveToPosition at the same Y as the NPC
					
					local direction = (moveToPosition - npc.HumanoidRootPart.Position) -- Direction from NPC to moveToPosition
					local distance = direction.Magnitude -- Distance from NPC to moveToPosition

					if distance <= WAYPOINT_RADIUS_THRESHOLD then -- If close enough to waypoint
						if #npc.Waypoints >= (npc.NextWaypointIndex + 1) then -- If there are still waypoints
							npc.NextWaypointIndex += 1 -- Set next waypoint index
						else
							npc.LastWanderTime = workspace:GetServerTimeNow() -- Wandering has ended, so we set LastWanderTime
							npc:SetState("Idle") -- Change state to "Idle"
						end
					else
						npc.Humanoid:Move(direction) -- Move NPC towards the next waypoint
					end
				end
			end
		end,
	},
	
	Pursuit = {
		Init = function(npc)
			if not npc.Humanoid then return end -- Check for humanoid

			npc.Humanoid.WalkSpeed = 16 -- Change humanoid WalkSpeed
		end,
		
		Update = function(npc)
			if not npc.Humanoid then return end
			if not npc.HumanoidRootPart then return end
			if not npc.Head then return end
			
			local target = npc.Target
			local targetHumanoid = target:FindFirstChild("Humanoid")
			local targetRootPart = target:FindFirstChild("HumanoidRootPart")
			
			if not targetRootPart or not targetHumanoid or targetHumanoid.Health <= 0 then -- If target is dead or broken :/ , stop Pursuit and change state to Idle
				npc:SetState("Idle")
				return
			end
			
			local canPursuit = false
			
			local isInSight = IsInFieldOfView(npc.Head, targetRootPart.Position)
			local isNotBehindObstacle = IsNotBehindObstacle(npc, npc.Head, target, targetRootPart)
			
			if isInSight and isNotBehindObstacle then -- If target is visible and in field of view
				canPursuit = true
				npc.TargetLastSeenTime = workspace:GetServerTimeNow() -- Set last target seen time for "Blind pursuit" behaviour
			else
				local elapsedLastSeenTime = (workspace:GetServerTimeNow() - npc.TargetLastSeenTime) -- Get time elapsed from last target seen
				
				if elapsedLastSeenTime < MAX_BLIND_PURSUIT_TIME then -- If true, NPC continues to pursue character using "Blind Pursuit"
					canPursuit = true
				else
					canPursuit = false
				end
			end
			
			if canPursuit then
				if isNotBehindObstacle then
					-- If target is not behind the obstacle, NPC can head towards it without using Pathfinding,
					-- but we still set a path (with only a single endpoint)
					
					local waypoints = {
						nil, -- We dont need first waypoint, because moving starts at index 2
						{Position = targetRootPart.Position} -- Path endpoint
					}
					
					npc:SetPath(waypoints) -- Set path waypoint to NPC
				else
					-- If target is BEHIND the obstacle, NPC need to compute path to it
					if not ComputePathToPoint(npc, targetRootPart.Position) then return end
					
					-- This time check is necessary to prevent the path from being calculated too frequently
					if (workspace:GetServerTimeNow() - npc.LastPathToTargetCompute) >= PATH_TO_TARGET_COMPUTE_DELAY then
						npc.LastPathToTargetCompute = workspace:GetServerTimeNow()

						npc:SetPath(GetPathWaypoints(npc)) -- Set path waypoint to NPC
					end
				end
				
				--[[
					The movement logic was copied from the "Wander" Update function
					because implementing it as a single local function would make the code slightly harder to read and understand
				]]
				
				local nextWaypoint = npc.Waypoints[npc.NextWaypointIndex] -- Get next waypoint on path

				if nextWaypoint then
					local moveToPosition = nextWaypoint.Position
					moveToPosition = Vector3.new(moveToPosition.X, npc.HumanoidRootPart.Position.Y, moveToPosition.Z) -- Set moveToPosition at the same Y as the NPC
					
					local direction = (moveToPosition - npc.HumanoidRootPart.Position) -- Direction from NPC to moveToPosition
					local distance = direction.Magnitude
					
					if distance <= WAYPOINT_RADIUS_THRESHOLD then -- If close enough to waypoint
						if #npc.Waypoints >= (npc.NextWaypointIndex + 1) then -- If there are still waypoints
							npc.NextWaypointIndex += 1 -- Set next waypoint index
						end
					else
						npc.Humanoid:Move(direction) -- Move NPC towards the next waypoint
					end
				end
				
				local distanceToTarget = (npc.HumanoidRootPart.Position - targetRootPart.Position).Magnitude -- Distance from NPC to target
				if distanceToTarget <= ATTACK_RANGE then -- If target is within ATTACK_RANGE, attack
					AttackTarget(npc, target)
				end
			else
				-- NPC didnt find next waypoint
				npc:SetState("Idle") -- Change state to "Idle"
			end
		end,
	},
}
