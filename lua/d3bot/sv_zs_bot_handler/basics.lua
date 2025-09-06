D3bot.Basics = {}

local toosmall = 1 / 1e9 / 1e9

local normalize2d = function(vec)
	local len = vec:Length2D()
	local lennormal = 1 / (toosmall + len)
	
	vec.x = vec.x * lennormal
	vec.y = vec.y * lennormal
	vec.z = 0
	
	return len
end

function D3bot.Basics.AirStrafe(bot, forwardSpeed, sideSpeed)
	sideSpeed = sideSpeed or 0
	forwardSpeed = forwardSpeed or 0
	if bot:GetGroundEntity() ~= NULL or bot:GetMoveType() ~= MOVETYPE_WALK then return forwardSpeed, sideSpeed end
	local vForward,vRight = bot:EyeAngles():Forward(),bot:EyeAngles():Right()
    normalize2d(vForward)
    normalize2d(vRight)
    
    local wishVel = Vector(vForward.x * forwardSpeed + vRight.x * sideSpeed,vForward.y * forwardSpeed + vRight.y * sideSpeed,0)
    local wishDir = wishVel:Angle()
    local curDir = bot:GetVelocity():Angle()
    local delta = math.NormalizeAngle(wishDir.y - curDir.y)

	if delta >= 170 then return forwardSpeed, sideSpeed end --stop doing these silly turns

    local rotation = math.rad((delta > 0 and -90 or 90) + delta)
    local cosrot = math.cos(rotation)
    local sinrot = math.sin(rotation)
    
    return cosrot * forwardSpeed - sinrot * sideSpeed,sinrot * forwardSpeed + cosrot * sideSpeed
end

---Let the bot suicide or retarget, based on the node parameters of the current and next node.
---@param bot GPlayer
function D3bot.Basics.SuicideOrRetarget(bot)
	local mem = bot.D3bot_Mem
	
	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil
	local currentLinkOrNil
	if D3bot.UsingSourceNav then
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil:SharesLink(nodeOrNil)
	else
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil.LinkByLinkedNode[nodeOrNil]
	end
	
	if D3bot.UsingSourceNav then return end
		
	if nodeOrNil and nextNodeOrNil then
		if nextNodeOrNil.Pos.z > nodeOrNil.Pos.z + 55 then
			local wallParam = nextNodeOrNil.Params.Wall
			if wallParam == "Retarget" then
				local handler = FindHandler(bot:GetZombieClass(), bot:Team())
				if handler and handler.RerollTarget then handler.RerollTarget(bot) end
				return
			elseif wallParam == "Suicide" then
				bot:Kill()
				return
			end
		end

		local classParam = nextNodeOrNil.Params.ForceClass
		if classParam then
			classParam = string.Replace(classParam,"_"," ")
			local bestclassindex = GAMEMODE:GetBestAvailableZombieClass(classParam)
			for i,class in pairs(GAMEMODE.ZombieClasses) do 
				if class.Index == bestclassindex then classParam = class.Name break end
			end
			if GAMEMODE:GetWaveActive() and bot:GetZombieClassTable().Name ~= classParam and not (GAMEMODE.ZombieEscape or GAMEMODE.PantsMode or GAMEMODE:IsClassicMode() or GAMEMODE:IsBabyMode()) and gamemode.Call("IsClassUnlocked", classParam) then
				mem.ForcedClass = classParam
				mem.TargetAfterSpawned = mem.TgtOrNil
				bot:Kill()
				return
			end
		end
	end
end

function D3bot.Basics.AttackStrat(bot,cade)
	local mem = bot.D3bot_Mem

	if D3bot.UsingSourceNav then return not cade end

	local target = bot.TgtOrNil

	if cade then
		if target and target:GetClass() == "prop_obj_sigil" then return 0 end
		return mem.CadeAttackStrat
	else
		local nodeOrNil = mem.NodeOrNil
		local nextNodeOrNil = mem.NextNodeOrNil
		local currentLinkOrNil
		if D3bot.UsingSourceNav then
			currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil:SharesLink(nodeOrNil)
		else
			currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil.LinkByLinkedNode[nodeOrNil]
		end

		if (nodeorNil and nodeOrNil.Params.AttackStrat == "Disabled") or (nextNodeOrNil and nextNodeOrNil.Params.AttackStrat == "Disabled") then
			return 0
		end
		return 1
	end
end

---Find nest point.
---@param bot GPlayer
---@return boolean Success
---@return any|nil Node
---@return GVector|nil NodePosition
function D3bot.Basics.FindNestPoint(bot,check)
	local mem = bot.D3bot_Mem
	
	if D3bot.UsingSourceNav then return false end

	local nestCount = 0
	local pnestCount = 0
	local nestedNodes = {}
	for i,v in pairs(ents.FindByClass("prop_creepernest")) do 
		if v:GetNestBuilt() then
			nestedNodes[D3bot.MapNavMesh:GetNearestNodeOrNil(v:GetPos())] = true
			local uid = bot:UniqueID()
			if v.OwnerUID == uid then
				pnestCount = pnestCount + 1
			end
		else
			local uid = bot:UniqueID()
			if v.OwnerUID == uid then
				local node = D3bot.MapNavMesh:GetNearestNodeOrNil(v:GetPos())
				local pos = v:GetPos()
				return true,node,pos
			end
		end
		nestCount = nestCount + 1
		if pnestCount >= 3 then return false end
		if nestCount >= 12 then return false end
	end

	if not check then
		for _, human in pairs(team.GetPlayers(TEAM_HUMAN)) do
			if human:IsFlagSet(FL_NOTARGET) then continue end
			if util.SkewedDistance(human:GetPos(), bot:GetPos(), 1.5) <= 500 and bot:D3bot_CanSeeTarget(0.5,human) then
				return false
			end
		end
	end

	for id, node in pairs(D3bot.MapNavMesh.NodeById) do
		if node.Params.Nest == "Enabled" and not nestedNodes[node] then 
			local pos = node:GetClosestPointOnArea(bot:GetPos())

			if not check and IsValid(bot.TgtOrNil) then
				local dist = bot.TgtOrNil:GetPos():Distance(pos)
				if (dist >= 1500) then continue end
			end

			local skip = false
			for _, ent in pairs(ents.FindByClass("prop_creepernest")) do
				if util.SkewedDistance(ent:GetPos(), pos, 1.5) <= GAMEMODE.CreeperNestDistBuildNest then
					skip = true break
				end
			end

			for _, sigil in pairs(ents.FindByClass("prop_obj_sigil")) do
				if sigil:GetSigilCorrupted() then continue end

				if util.SkewedDistance(sigil:GetPos(), pos, 1.5) <= GAMEMODE.CreeperNestDistBuildNest then
					skip = true break
				end
			end

			for _, human in pairs(team.GetPlayers(TEAM_HUMAN)) do
				if util.SkewedDistance(human:GetPos(), pos, 1.5) <= GAMEMODE.CreeperNestDistBuild then
					skip = true break
				end
			end

			if skip then continue end

			return true,node,pos
		end
	end

	return false
end

---Basic walking handler.
---@param bot GPlayer|table
---@param pos GVector -- Target position the bot should walk towards. Should be inside the current or next node.
---@param aimAngle GAngle? -- Target aim angle of the bot. If not set, the bot will aim to the walking direction.
---@param slowdown boolean? -- Set to true if the bot will slow down when it is close to its target.
---@param proximity number? -- The proxmimity where the bot starts to slow down.
---@return boolean valid -- True if the handler ran corrcetly.
---@return table actions -- Table with a set of actions.
---@return number? forwardSpeed -- The needed forwards speed for the bot.
---@return number? sideSpeed -- The needed side speed for the bot.
---@return number? upSpeed -- The needed upwards speed for the bot.
---@return GAngle aimAngle -- The resulting aim angle for the bot.
---@return boolean minorStuck -- True if the bot seems to be stuck on a ladder or similar.
---@return boolean majorStuck -- True if the bot seems to be stuck on props, or runs in circles.
---@return boolean facesHindrance -- True if the bot is walking slower than expected.
function D3bot.Basics.Walk(bot, pos, aimAngle, slowdown, proximity)
	local mem = bot.D3bot_Mem

	if mem.BlockMovementUntil then
		if mem.BlockMovementUntil >= CurTime() and mem.BlockedOnNode and mem.BlockedOnNode:GetContains(bot:GetPos(), nil) then
			return false, {}, nil, nil, nil, mem.Angs, false, false, false
		else
			mem.BlockMovementUntil = nil
			mem.BlockedOnNode = nil
		end
	end

	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil
	local currentLinkOrNil
	if D3bot.UsingSourceNav then
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil:SharesLink(nodeOrNil)
	else
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil.LinkByLinkedNode[nodeOrNil]
	end

	local offshootAngle = angle_zero
	local origin = bot:GetPos()
	local actions = {}

	-- Check if the bot needs to climb while being on a node or going towards a node. As maneuvering while climbing is different, this will change/override some movement actions.
	local shouldClimb
	if D3bot.UsingSourceNav then
		shouldClimb = (nodeOrNil and nodeOrNil:GetMetaData().Params.Climbing == "Needed") or (nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.Climbing == "Needed")
	else
		shouldClimb = (nodeOrNil and nodeOrNil.Params.Climbing == "Needed") or (nextNodeOrNil and nextNodeOrNil.Params.Climbing == "Needed")
	end

	-- Make bot aim straight when outside of current node area This should prevent falling down edges.
	local aimStraight = false
	if D3bot.UsingSourceNav then
		if nodeOrNil and not navmesh.GetNavArea(origin, 8) then aimStraight = true end
	else
		if nodeOrNil and not nodeOrNil:GetContains(origin, nil) then aimStraight = true end
	end

	local attackType = ""
	local posdiff = pos - origin

	if shouldClimb then
		---@type GWeapon|table
		local weapon = bot:GetActiveWeapon()
		if weapon and weapon.GetClimbing and weapon:GetClimbing() and weapon.GetClimbSurface then
			local tr = weapon:GetClimbSurface()
			if tr and tr.Hit then
				bot:D3bot_AngsRotateTo((-tr.HitNormal):Angle(), 1)
			end
		else
			bot:D3bot_AngsRotateTo(Vector(pos.x-origin.x, pos.y-origin.y, 0):Angle(), 0.5)
		end
	else
		if mem.BarricadeAttackEntity and mem.BarricadeAttackPos and mem.BarricadeAttackEntity:IsValid() and mem.BarricadeAttackPos:DistToSqr(origin) < 100*100 then
			-- We have a barricade entity to attack, so we aim for this one.
			offshootAngle = bot:D3bot_GetOffshoot(0.1)
			aimAngle = aimAngle or (mem.BarricadeAttackPos - bot:GetShootPos()):Angle()
			bot:D3bot_AngsRotateTo(aimAngle + offshootAngle, 0.5)
			--ClDebugOverlay.Line(GetPlayerByName("D3"), bot:GetShootPos(), mem.BarricadeAttackPos, 1, Color(0,255,0), false)
			attackType = "Cade"
			posdiff = mem.BarricadeAttackPos - origin
		else
			-- Target is invalid or too far away, forget about it.
			-- We will either use the given aim angle, or calculate it based on the walk position.
			offshootAngle = bot:D3bot_GetOffshoot(aimStraight and 0 or 1)
			aimAngle = aimAngle or (pos - origin):Angle()
			bot:D3bot_AngsRotateTo(aimAngle + offshootAngle, aimStraight and 1 or D3bot.BotAngLerpFactor)
			mem.BarricadeAttackPos, mem.BarricadeAttackEntity = nil, nil
		end
	end

	local duckParam, duckToParam, jumpParam, jumpToParam
	local maxHeightParam, nextMaxHeightParam
	local pathParam, ladderParam

	if D3bot.UsingSourceNav then
		duckParam = nodeOrNil and nodeOrNil:GetMetaData().Params.Duck
		duckToParam = nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.DuckTo
		jumpParam = nodeOrNil and nodeOrNil:GetMetaData().Params.Jump
		jumpToParam = nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.JumpTo
		maxHeightParam = nodeOrNil and nodeOrNil:GetMetaData().Params.MaxHeight
		nextMaxHeightParam = nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.MaxHeight
	else
		duckParam = nodeOrNil and nodeOrNil.Params.Duck
		duckToParam = nextNodeOrNil and nextNodeOrNil.Params.DuckTo
		jumpParam = nodeOrNil and nodeOrNil.Params.Jump
		jumpToParam = nextNodeOrNil and nextNodeOrNil.Params.JumpTo
		ladderParam = nodeOrNil and nodeOrNil.Params.Ladder
		pathParam = currentLinkOrNil and currentLinkOrNil.Params.Path

		if not jumpToParam and currentLinkOrNil and currentLinkOrNil.Params.Jumping == "Needed" and nextNodeOrNil and nodeOrNil and nextNodeOrNil.Pos.Z > nodeOrNil.Pos.Z then
			jumpToParam = "Close2"
		end

		maxHeightParam = nodeOrNil and nodeOrNil.Params.MaxHeight
		nextMaxHeightParam = nextNodeOrNil and nextNodeOrNil.Params.MaxHeight
	end

	-- Set up movement vector, which is relative to the player's 2D forward direction.
	-- Positive x is forward, positive y is left and positive z is upwards.
	---@type GVector
	local weapon = bot:GetActiveWeapon()
	local range = (weapon and weapon.MeleeReach or 75) + 25 -- Either MeleeReach + 25, or 100.

	local movementVector = pos - origin
	-- Slow down bot when close to target (2D distance).
	local invProximity = math.Clamp((movementVector:Length2D() - (proximity or 10)) / 60, 0.75, 1)
	local speed = bot:GetMaxSpeed() * (slowdown and invProximity or 1)
	--movementVector.z = 0
	movementVector:Normalize()
	movementVector:Mul(speed)
	movementVector:Rotate(Angle(0, offshootAngle.yaw - mem.Angs.yaw, 0))

	-- Antistuck when bot is possibly stuck crouching below something.
	if mem.AntiStuckTime and mem.AntiStuckTime > CurTime() then
		if not bot:Crouching() then
			mem.AntiStuckTime = nil
		else
			movementVector = -0.5 * movementVector
			actions.Jump = true
			actions.Attack = true
		end
	end

	local velocity = bot:GetVelocity():Length2D()
	local facesHindrance = velocity < 0.25 * speed
	local minorStuck, majorStuck = bot:D3bot_CheckStuck()

	if not facesHindrance then
		mem.lastNoHindrance = CurTime()
	end

	-- Special case: We are walking towards a node with MaxHeight set, and the bot's standing height is larger than that.
	-- This means we need to duck/crouch. Exception: If the navmesh has any other duck or jump parameters set, we do nothing.
	if not duckParam and not duckToParam and not jumpParam and not jumpToParam then
		if nextMaxHeightParam and nextMaxHeightParam < mem.Height then
			actions.Duck = true
		end
	end
	if duckParam == "Always" or duckToParam == "Always" then
		actions.Duck = true
	end
	if duckToParam == "Close" and nextNodeOrNil then
		local _, hullTop = bot:GetHull() -- Assume the hull is symmetrical.
		local hullX, hullY, _ = hullTop:Unpack()
		local halfHullWidth = math.max(hullX, hullY) + 5 -- Just add a small margin to let the bot duck/crouch before it "touches" the next node's area.

		---@type GVector
		local closestDiff = origin - nextNodeOrNil:GetClosestPointOnArea(origin)
		local closestDistSqr = closestDiff:Length2DSqr()
		if closestDistSqr <= halfHullWidth*halfHullWidth then
			actions.Duck = true
		end
	end

	if pathParam == "Ladder" then
		mem.IsOnLadder = true
	else
		if mem.IsOnLadder and ladderParam ~= "NoDismount" then
			actions.Use = true
			actions.Jump = true

			mem.BlockMovementUntil = CurTime() + 0.5
			if not D3bot.UsingSourceNav then mem.BlockedOnNode = nodeOrNil end
		end

		mem.IsOnLadder = false
	end

	if bot:GetMoveType() ~= MOVETYPE_LADDER then
		mem.IsOnLadder = false

		local botOnGround = bot:IsOnGround()
		if botOnGround or bot:WaterLevel() > 0 then
			-- If we should climb, jump while we're on the ground.
			if shouldClimb or jumpParam == "Always" or jumpToParam == "Always" then
				actions.Jump = true
			end
			-- If there is a JumpTo parameter with "Close" as the value, determine if we are close enough to jump.
			if (jumpToParam == "Close" or jumpToParam == "Close2") and nextNodeOrNil then
				local _, hullTop = bot:GetHull() -- Assume the hull is symmetrical.
				local hullX, hullY, _ = hullTop:Unpack()
				local halfHullWidth = (math.max(hullX, hullY) + 5) + (jumpToParam == "Close2" and 32 or 0) -- Just add a small margin to let the bot jump before it "touches" the next node's area.

				---@type GVector
				local closestDiff = origin - nextNodeOrNil:GetClosestPointOnArea(origin)
				local closestDistSqr = closestDiff:Length2DSqr()
				if closestDistSqr <= halfHullWidth*halfHullWidth then
					actions.Jump = true
				end
			end
			if facesHindrance then
				if math.random(D3bot.BotJumpAntichance) == 1 then
					actions.Jump = true
				end
				if math.random(D3bot.BotDuckAntichance) == 1 or (mem.TooTall and math.random(1,2) == 1) then
					actions.Duck = true
				end
			end
		else
			actions.Duck = true
		end

		if shouldClimb and not botOnGround then
			-- If we are airborne and should be climbing, try to climb the surface.
			actions.Attack2 = true
			-- Calculate climbing speeds.
			---@type GWeapon|table
			local weapon = bot:GetActiveWeapon()
			if weapon and weapon.GetClimbing and weapon:GetClimbing() then
				local yaw1 = bot:GetForward():Angle().yaw
				local yaw2 = Vector(pos.x-origin.x, pos.y-origin.y, 0):Angle().yaw
				movementVector.y = math.AngleDifference(yaw2, yaw1)
				movementVector.x = (pos.z - origin.z + 20) * 10
				if (math.abs(movementVector.x) < 20 or bot:GetVelocity():Length() < 10) and math.abs(movementVector.y) > 1 then movementVector.x = 0 end
			end
		end
		
	elseif minorStuck then
		-- Stuck on ladder
		actions.Jump = true
		actions.Duck = true
		actions.Use = true
	end

	if duckParam == "Disabled" or duckToParam == "Disabled" then
		actions.Duck = false
	end


	local canjump = not (jumpParam == "Disabled" or jumpToParam == "Disabled" or (not actions.Duck and bot:Crouching()))
	if math.random(1, 2) == 1 or not canjump then
		actions.Jump = false
	end

	-- Check if bot is possibly stuck below something.
	-- This is basically when the bot is slowly or not moving on ground, and is crouching even it shouldn't.
	if bot:GetMoveType() ~= MOVETYPE_LADDER and bot:IsOnGround() and bot:Crouching() and not actions.Duck and (not bot.D3bot_LastDamage or bot.D3bot_LastDamage < CurTime() - 2) and (not mem.lastNoHindrance or mem.lastNoHindrance < CurTime() - 2) then
		mem.AntiStuckCounter = (mem.AntiStuckCounter or 0) + 1
		if mem.AntiStuckCounter > 30 then
			mem.AntiStuckCounter = nil
			mem.AntiStuckTime = CurTime() + 1
		end
	else
		mem.AntiStuckCounter = nil
	end

	actions.Attack = facesHindrance and not shouldClimb or bot:IsHolding() -- If the bot should climb, but is using its primary attack, climing will fail.
	actions.Use = actions.Use or facesHindrance

	local canusestrat1 = weapon and ((weapon.MeleeDelay and weapon.MeleeDelay > 0.5) or (weapon.SwingTime and weapon.SwingTime > 0.5))

	local crouchJumpHeight = mem.CrouchJumpHeight
	local jumphit = util.TraceHull({
		start = bot:GetPos(),
		endpos = bot:GetPos() + vector_up * crouchJumpHeight,
		filter = function(ent) 
			if ent:IsPlayer() and bot:Team() == ent:Team() then return false end
			return (ent ~= bot)
		end,
		mins = mem.MinsHullDuck,
		maxs = mem.MaxsHullDuck,
	})

	--debugoverlay.Box(jumphit.HitPos,mem.MinsHullDuck,mem.MaxsHullDuck,0.08,Color(255,0,0))

	local jumpforward = util.TraceHull({
		start = jumphit.HitPos,
		endpos = jumphit.HitPos + bot:GetForward() * 64,
		filter = function(ent) 
			if ent:IsPlayer() and bot:Team() == ent:Team() then return false end
			return (ent ~= bot)
		end,
		mins = mem.MinsHullDuck,
		maxs = mem.MaxsHullDuck,
	})

	--debugoverlay.Box(jumpforward.HitPos,mem.MinsHullDuck,mem.MaxsHullDuck,0.08,Color(0,255,0))

	if attackType == "Cade" and not jumpforward.Hit and canjump then
		if ((mem.LastJumpTime or 0) + 4) < CurTime() then
			movementVector = posdiff
			local speed = bot:GetMaxSpeed()
			movementVector.z = 0
			movementVector:Normalize()
			movementVector:Mul(speed)
			movementVector:Rotate(Angle(0, offshootAngle.yaw - mem.Angs.yaw, 0))
			actions.Jump = true
			canusestrat1 = false
			mem.LastJumpTime = CurTime()
		end
	elseif D3bot.Basics.AttackStrat(bot,true) == 1 and canusestrat1 then
		actions.Jump = false
	end

	local swingendtime = weapon and (weapon.GetSwingEndTime and weapon:GetSwingEndTime()) or (weapon.GetSwingEnd and weapon:GetSwingEnd()) or 0
	local swingtime = math.Clamp(swingendtime - CurTime(),0,10)
	local meleedelay = (weapon.MeleeDelay and weapon.MeleeDelay) or (weapon.SwingTime and weapon.SwingTime)
	if bot:GetMoveType() ~= MOVETYPE_LADDER and attackType == "Cade" and (swingtime == 0 or swingtime > 0.5) and (D3bot.Basics.AttackStrat(bot,true) == 1) and canusestrat1 then 
		movementVector = -posdiff
		local speed = bot:GetMaxSpeed() * 0.5
		movementVector.z = 0
		movementVector:Normalize()
		movementVector:Mul(speed)
		movementVector:Rotate(Angle(0, offshootAngle.yaw - mem.Angs.yaw, 0))
		actions.Attack = true and not shouldClimb
	end

	if movementVector.x > 0 then actions.MoveForward = true end
	if movementVector.x < 0 then actions.MoveBackward = true end
	if movementVector.y < 0 then actions.MoveRight = true end
	if movementVector.y > 0 then actions.MoveLeft = true end

	return true, actions, movementVector.x, -movementVector.y, nil, mem.Angs, minorStuck, majorStuck, facesHindrance
end

---Basic walk and attack handler.
---@param bot GPlayer|table
---@return boolean valid -- True if the handler ran corrcetly.
---@return table actions -- Table with a set of actions.
---@return number? forwardSpeed -- The needed forwards speed for the bot.
---@return number? sideSpeed -- The needed side speed for the bot.
---@return number? upSpeed -- The needed upwards speed for the bot.
---@return GAngle aimDirection -- The wanted aim direction for the bot.
---@return boolean minorStuck -- True if the bot seems to be stuck on a ladder or similar.
---@return boolean majorStuck -- True if the bot seems to be stuck on props, or runs in circles.
---@return boolean facesHindrance -- True if the bot is walking slower than expected.
function D3bot.Basics.WalkAttackAuto(bot,offshoot)
	local mem = bot.D3bot_Mem

	if mem.BlockMovementUntil then
		if mem.BlockMovementUntil >= CurTime() and mem.BlockedOnNode and mem.BlockedOnNode:GetContains(bot:GetPos(), nil) then
			return false, {}, nil, nil, nil, mem.Angs, false, false, false
		else
			mem.BlockMovementUntil = nil
			mem.BlockedOnNode = nil
		end
	end

	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil
	local currentLinkOrNil
	if D3bot.UsingSourceNav then
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil:SharesLink(nodeOrNil)
	else
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil.LinkByLinkedNode[nodeOrNil]
	end

	local actions = {}

	-- Check if the bot needs to climb while being on a node or going towards a node.
	-- If so, ignore everything else, and use Basics.WalkAuto, which will handle everything fine.
	-- TODO: Put everything into its own basics function
	local shouldClimb
	if D3bot.UsingSourceNav then
		shouldClimb = ( nodeOrNil and nodeOrNil:GetMetaData().Params.Climbing == "Needed" ) or ( nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.Climbing == "Needed" )
	else
		shouldClimb = ( nodeOrNil and nodeOrNil.Params.Climbing == "Needed" ) or ( nextNodeOrNil and nextNodeOrNil.Params.Climbing == "Needed" )
	end

	-- Fall back to normal walking behavior if possible.
	if shouldClimb and nextNodeOrNil then
		-- Use walk handler for climing.
		-- Unless we don't have a next node, so the target is near a wall we need to climb.
		if D3bot.UsingSourceNav then
			return D3bot.Basics.Walk(bot, nextNodeOrNil:GetCenter(), nil)
		else
			return D3bot.Basics.Walk(bot, nextNodeOrNil.Pos, nil)
		end
	elseif not bot:D3bot_CanSeeTargetCached() and nextNodeOrNil then
		-- Target not visible, walk towards next node.
		if D3bot.UsingSourceNav then
			return D3bot.Basics.Walk(bot, nextNodeOrNil:GetCenter(), nil)
		else
			return D3bot.Basics.Walk(bot, nextNodeOrNil.Pos, nil)
		end

	elseif mem.TgtOrNil and mem.DontAttackTgt then
		-- There is a target entity, but the bot shouldn't attack it.
		return D3bot.Basics.Walk(bot, mem.TgtOrNil:GetPos(), nil, true, mem.TgtProximity)
	elseif mem.PosTgtOrNil then
		-- Go straight to position target, if there is one.
		return D3bot.Basics.Walk(bot, mem.PosTgtOrNil, nil, true, mem.PosTgtProximity)
	end

	---@type GWeapon|table
	local weapon = bot:GetActiveWeapon()
	local range = (weapon and weapon.MeleeReach or 75) + 25 -- Either MeleeReach + 25, or 100.

	-- We don't have a case that can be handled by the basic walk handler.
	-- So we just attack something directly.
	local facesTgt = false -- True if bot is close enough for attacks.
	local preattack = false
	local attackType = ""

	local meleedelay = (weapon.MeleeDelay and weapon.MeleeDelay) or (weapon.SwingTime and weapon.SwingTime) or 0


	local origin = bot:GetShootPos()
	local attackPos = bot:D3bot_GetAttackPosOrNilFuture(nil, math.Rand(0, D3bot.BotAimPosVelocityOffshoot)) -- Target attack position, for aiming.
	local movePos = attackPos or bot:GetPos() -- Target movement position.
	local diff = (movePos - origin - bot:D3bot_GetTargetVelocity() * meleedelay)

	if diff:Length() >= range then
		diff:Normalize() diff:Mul(range)
	end

	local origin2 = bot:GetShootPos() + (diff * meleedelay * 2) -- Attack origin of the bot.
	--debugoverlay.Box(origin,Vector(-10,-10,-10),Vector(10,10,10),0.08,Color(0,255,0,56))

	local inrange = attackPos and attackPos:DistToSqr(origin) < math.pow(range, 2)
	local shouldpreattack = (attackPos and attackPos:DistToSqr(origin2) < math.pow(range * 0.8, 2))
	if inrange or shouldpreattack then
		--ClDebugOverlay.Line(GetPlayerByName("D3"), bot:GetShootPos(), attackPos, 1, Color(255,255,0), false)

		-- We are within attack range.
		facesTgt = inrange
		preattack = shouldpreattack
		if attackPos.z < bot:GetPos().z + bot:GetViewOffsetDucked().z then
			actions.Duck = true
		end
		attackType = "Target"
		if mem.BarricadeAttackEntity and mem.BarricadeAttackPos then
			attackType = "Target-Cade"
		end
	elseif mem.BarricadeAttackEntity and mem.BarricadeAttackPos then
		-- We are not within attack range, but we have a barricade entity to attack.
		-- So we aim for this one, instead.
		if mem.BarricadeAttackEntity:IsValid() and mem.BarricadeAttackPos:DistToSqr(origin) < math.pow(range, 2) then
			attackPos = mem.BarricadeAttackPos
			facesTgt = true
			--ClDebugOverlay.Line(GetPlayerByName("D3"), bot:GetShootPos(), attackPos, 1, Color(0,0,255), false)
		else
			-- Target is invalid or too far away, forget about it.
			mem.BarricadeAttackPos, mem.BarricadeAttackEntity = nil, nil
		end
		attackType = "Cade"
	end

	--debugoverlay.Box(origin2,Vector(-10,-10,-10),Vector(10,10,10),0.08,preattack and Color(0,255,0) or Color(255,0,0,56))

	local offshootAngle = bot:D3bot_GetOffshoot(offshoot or (facesTgt and D3bot.FaceTargetOffshootFactor or 1))
	if attackPos then
		bot:D3bot_AngsRotateTo((attackPos - origin):Angle() + offshootAngle, D3bot.BotAttackAngLerpFactor)
	end

	local duckParam, duckToParam, jumpParam, jumpToParam
	local maxHeightParam, nextMaxHeightParam
	local pathParam, ladderParam

	if D3bot.UsingSourceNav then
		duckParam = nodeOrNil and nodeOrNil:GetMetaData().Params.Duck
		duckToParam = nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.DuckTo
		jumpParam = nodeOrNil and nodeOrNil:GetMetaData().Params.Jump
		jumpToParam = nextNodeOrNil and nextNodeOrNil:GetMetaData().Params.JumpTo
	else
		duckParam = nodeOrNil and nodeOrNil.Params.Duck
		duckToParam = nextNodeOrNil and nextNodeOrNil.Params.DuckTo
		jumpParam = nodeOrNil and nodeOrNil.Params.Jump
		jumpToParam = nextNodeOrNil and nextNodeOrNil.Params.JumpTo
		ladderParam = nodeOrNil and nodeOrNil.Params.Ladder
		pathParam = currentLinkOrNil and currentLinkOrNil.Params.Path

		if not jumpToParam and currentLinkOrNil and currentLinkOrNil.Params.Jumping == "Needed" and nextNodeOrNil and nodeOrNil and nextNodeOrNil.Pos.Z > nodeOrNil.Pos.Z then
			jumpToParam = "Close"
		end
	end

	-- Set up movement vector, which is relative to the player's 2D forward direction.
	-- Positive x is forward, positive y is left and positive z is upwards.
	---@type GVector
	local movePosOffset = (attackType == "Target" and D3bot.Basics.AttackStrat(bot) == 1) and (Vector(math.sin(CurTime() * 2.5 + bot:EntIndex() * 80),math.cos(CurTime() * 2.5 + bot:EntIndex() * 80)) * range * 0.65) or vector_origin
	local movementVector = (movePos + movePosOffset) - origin
	-- Slow down bot when close to target (2D distance).
	local invProximity = math.Clamp((movementVector:Length2D() - 10) / 60, 0.95, 1)
	local speed = bot:GetMaxSpeed() * invProximity
	--movementVector.z = 0
	movementVector:Normalize()
	movementVector:Mul(speed)
	movementVector:Rotate(Angle(0, offshootAngle.yaw - mem.Angs.yaw, 0))

	-- Antistuck when bot is possibly stuck crouching below something.
	if mem.AntiStuckTime and mem.AntiStuckTime > CurTime() then
		if not bot:Crouching() then
			mem.AntiStuckTime = nil
		else
			movementVector = -0.5 * movementVector
			actions.Jump = true
			actions.Attack = true
		end
	end

	local velocity = bot:GetVelocity():Length2D()
	local facesHindrance = velocity < 0.25 * speed
	local minorStuck, majorStuck = bot:D3bot_CheckStuck()

	if not facesHindrance then
		mem.lastNoHindrance = CurTime()
	end

	-- Special case: We are walking towards a node with MaxHeight set, and the bot's standing height is larger than that.
	-- This means we need to duck/crouch. Exception: If the navmesh has any other duck or jump parameters set, we do nothing.
	if not duckParam and not duckToParam and not jumpParam and not jumpToParam then
		if nextMaxHeightParam and nextMaxHeightParam < mem.Height then
			actions.Duck = true
		end
	end
	if duckParam == "Always" or duckToParam == "Always" then
		actions.Duck = true
	end
	if duckToParam == "Close" and nextNodeOrNil then
		local _, hullTop = bot:GetHull() -- Assume the hull is symmetrical.
		local hullX, hullY, _ = hullTop:Unpack()
		local halfHullWidth = math.max(hullX, hullY) + 5 -- Just add a small margin to let the bot duck/crouch before it "touches" the next node's area.

		---@type GVector
		local closestDiff = origin - nextNodeOrNil:GetClosestPointOnArea(origin)
		local closestDistSqr = closestDiff:Length2DSqr()
		if closestDistSqr <= halfHullWidth*halfHullWidth then
			actions.Duck = true
		end
	end

	if pathParam == "Ladder" then
		mem.IsOnLadder = true
	else
		if mem.IsOnLadder and ladderParam ~= "NoDismount" then
			actions.Use = true
			actions.Jump = true

			mem.BlockMovementUntil = CurTime() + 0.5
			if not D3bot.UsingSourceNav then mem.BlockedOnNode = nodeOrNil end
		end

		mem.IsOnLadder = false
	end

	if bot:GetMoveType() ~= MOVETYPE_LADDER then
		mem.IsOnLadder = false

		if bot:IsOnGround() or bot:WaterLevel() > 0 then
			if jumpParam == "Always" or jumpToParam == "Always" then
				actions.Jump = true
			end
			-- If there is a JumpTo parameter with "Close" as the value, determine if we are close enough to jump.
			if jumpToParam == "Close" and nextNodeOrNil then
				local _, hullTop = bot:GetHull() -- Assume the hull is symmetrical.
				local hullX, hullY, _ = hullTop:Unpack()
				local halfHullWidth = math.max(hullX, hullY) + 5 -- Just add a small margin to let the bot jump before it "touches" the next node's area.

				---@type GVector
				local closestDiff = origin - nextNodeOrNil:GetClosestPointOnArea(origin)
				local closestDistSqr = closestDiff:Length2DSqr()
				if closestDistSqr <= halfHullWidth*halfHullWidth then
					actions.Jump = true
				end
			end
			if facesHindrance then
				if math.random(D3bot.BotJumpAntichance) == 1 then
					actions.Jump = true
				end
				if math.random(D3bot.BotDuckAntichance) == 1 then
					actions.Duck = true
				end
			end

			if (((movementVector.z > (origin.z + 32)) or math.random(1,100) <= 10) and ((mem.LastJumpTime or 0) + math.Rand(0.5,1.9) < CurTime())) or D3bot.BHOPMode then
				actions.Jump = true
				mem.LastJumpTime = CurTime()
			end
		else
			actions.Duck = true
		end
	elseif minorStuck then
		-- Stuck on ladder
		actions.Jump = true
		actions.Duck = true
		actions.Use = true
	end

	if duckParam == "Disabled" or duckToParam == "Disabled" or D3bot.BHOPMode then
		actions.Duck = false
	end
	if math.random(1, 2) == 1 or jumpParam == "Disabled" or jumpToParam == "Disabled" or (not actions.Duck and bot:Crouching()) then
		actions.Jump = false
	end

	-- Check if bot is possibly stuck below something.
	-- This is basically when the bot is slowly or not moving on ground, and is crouching even it shouldn't.
	if bot:GetMoveType() ~= MOVETYPE_LADDER and bot:IsOnGround() and bot:Crouching() and not actions.Duck and (not bot.D3bot_LastDamage or bot.D3bot_LastDamage < CurTime() - 2) and (not mem.lastNoHindrance or mem.lastNoHindrance < CurTime() - 2) then
		mem.AntiStuckCounter = (mem.AntiStuckCounter or 0) + 1
		if mem.AntiStuckCounter > 30 then
			mem.AntiStuckCounter = nil
			mem.AntiStuckTime = CurTime() + 1
		end
	else
		mem.AntiStuckCounter = nil
	end
	actions.Attack = preattack or facesTgt or facesHindrance or bot:IsHolding()
	actions.Use = actions.Use or facesHindrance

	if movementVector.x > 0 then actions.MoveForward = true end
	if movementVector.x < 0 then actions.MoveBackward = true end
	if movementVector.y < 0 then actions.MoveRight = true end
	if movementVector.y > 0 then actions.MoveLeft = true end

	return true, actions, movementVector.x, -movementVector.y, nil, mem.Angs, minorStuck, majorStuck, facesHindrance
end

---Pouncing handler.
---@param bot GPlayer|table
---@param crab boolean
---@return boolean valid -- True if the handler ran corrcetly.
---@return table actions -- Table with a set of actions.
---@return number? speed -- The needed forwards speed for the bot.
---@return number? sideSpeed -- The needed side speed for the bot.
---@return number? upSpeed -- The needed upwards speed for the bot.
---@return GAngle aimDirection -- The wanted aim direction for the bot.
---@return boolean minorStuck -- True if the bot seems to be stuck on a ladder or similar.
---@return boolean majorStuck -- True if the bot seems to be stuck on props, or runs in circles.
---@return boolean facesHindrance -- True if the bot is walking slower than expected.
function D3bot.Basics.PounceAuto(bot, crab, fleshcreeper)
	local mem = bot.D3bot_Mem

	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil

	if not bot:IsOnGround() or bot:GetMoveType() == MOVETYPE_LADDER then return false, {}, nil, nil, nil, angle_zero, false, false, false end

	---@type GWeapon|table
	local weapon = bot:GetActiveWeapon()
	if not IsValid(weapon) or (not weapon.PounceVelocity and not crab and not fleshcreeper) then return false, {}, nil, nil, nil, angle_zero, false, false, false end

	-- Fill table with possible pounce target positions, ordered with increasing priority.

	local tempPos = bot:GetPos() -- Current position of the bot or a node.
	local tempDist = 0           -- Approximates the walking distance with the help of tempPos.
	local pounceTargetPositions = {}
	if nextNodeOrNil and D3bot.UsingSourceNav then
		tempDist = tempDist + tempPos:Distance(nextNodeOrNil:GetCenter())
		tempPos = nextNodeOrNil:GetCenter()
		table.insert(pounceTargetPositions, {
			Pos = nextNodeOrNil:GetCenter() + Vector(0, 0, 1),
			Dist = tempDist,
			TimeFactor = 1.1,
			ForcePounce = (nextNodeOrNil:SharesLink(nodeOrNil) and (crab and nextNodeOrNil:SharesLink(nodeOrNil):GetMetaData().Params.CrabPouncing == "Needed" or not crab and nextNodeOrNil:SharesLink(nodeOrNil):GetMetaData().Params.Pouncing == "Needed"))
		})
	elseif nextNodeOrNil then
		tempDist = tempDist + tempPos:Distance(nextNodeOrNil.Pos)
		tempPos = nextNodeOrNil.Pos
		table.insert(pounceTargetPositions, {
			Pos = nextNodeOrNil.Pos + Vector(0, 0, 1),
			Dist = tempDist,
			TimeFactor = 1.1,
			ForcePounce = (nextNodeOrNil.LinkByLinkedNode[nodeOrNil] and (crab and nextNodeOrNil.LinkByLinkedNode[nodeOrNil].Params.CrabPouncing == "Needed" or not crab and nextNodeOrNil.LinkByLinkedNode[nodeOrNil].Params.Pouncing == "Needed"))
		})
	end
	if D3bot.UsingSourceNav then
		for i, v in ipairs(mem.RemainingNodes) do -- TODO: Check if it behaves as expected
			tempDist = tempDist + tempPos:Distance(v:GetCenter())
			tempPos = v:GetCenter()
			table.insert(pounceTargetPositions, { Pos = v:GetCenter() + Vector(0, 0, 1), Dist = tempDist, TimeFactor = 1.1 })
			if i >= 2 then break end
		end
	else
		for i, v in ipairs(mem.RemainingNodes) do -- TODO: Check if it behaves as expected
			tempDist = tempDist + tempPos:Distance(v.Pos)
			tempPos = v.Pos
			table.insert(pounceTargetPositions, { Pos = v.Pos + Vector(0, 0, 1), Dist = tempDist, TimeFactor = 1.1 })
			if i >= 2 then break end
		end
	end
	local tempAttackPosOrNil = bot:D3bot_GetAttackPosOrNilFuturePlatforms(0, mem.pounceFlightTime or 0)
	if tempAttackPosOrNil then
		tempDist = tempDist + bot:GetPos():Distance(tempAttackPosOrNil)
		table.insert(pounceTargetPositions, { Pos = tempAttackPosOrNil + Vector(0, 0, 1), Dist = tempDist, TimeFactor = 0.8, HeightDiff = 100 }) -- TODO: Global bot 'IQ' level influences TimeFactor, the lower the more likely they will cut off the players path
	elseif mem.PosTgtOrNil then
		tempDist = tempDist + bot:GetPos():Distance(mem.PosTgtOrNil)
		table.insert(pounceTargetPositions, { Pos = mem.PosTgtOrNil + Vector(0, 0, 1), Dist = tempDist, TimeFactor = 0.8, HeightDiff = 100 })
	end

	-- Find best trajectory
	local trajectory
	for _, pounceTargetPos in ipairs(table.Reverse(pounceTargetPositions)) do
		local trajectories = bot:D3bot_CanPounceToPos(pounceTargetPos.Pos)
		local timeToTarget = pounceTargetPos.Dist / bot:GetMaxSpeed()
		if trajectories and (pounceTargetPos.ForcePounce or (pounceTargetPos.HeightDiff and pounceTargetPos.Pos.z - bot:GetPos().z > pounceTargetPos.HeightDiff) or timeToTarget > (trajectories[1].t1 + (weapon.PounceStartDelay or 0)) * pounceTargetPos.TimeFactor) then
			trajectory = trajectories[1]
			break
		end
	end

	local actions = {}

	if (trajectory and CurTime() >= weapon:GetNextPrimaryFire() and CurTime() >= weapon:GetNextSecondaryFire() and CurTime() >= (weapon.NextAllowPounce or weapon:GetNextPrimaryFire())) or mem.pouncing then
		if trajectory then
			mem.Angs = Angle(-math.deg(trajectory.pitch), math.deg(trajectory.yaw), 0)
			mem.pounceFlightTime = math.Clamp(trajectory.t1 + (mem.pouncingStartTime or CurTime()) - CurTime(), 0, 1) -- Store flight time, and use it to iteratively get close to the correct intersection point.
		end
		if not mem.pouncing then
			-- Started pouncing
			if not fleshcreeper then
				actions.Attack2 = crab and false or true
				actions.Attack = crab and true or false
			else
				actions.Reload = true
			end
			mem.pouncingTimer = CurTime() + 0.9 + math.random() * 0.2

			mem.pouncingStartTime = CurTime() + (weapon.PounceStartDelay or 0.5)
			mem.pouncing = true
		elseif mem.pouncingTimer and mem.pouncingTimer < CurTime() and (CurTime() - mem.pouncingTimer > 5 or bot:WaterLevel() >= 2 or bot:IsOnGround()) then
			-- Ended pouncing
			mem.pouncing = false
			mem.pounceFlightTime = nil
			bot:D3bot_UpdatePathProgress()
		end

		return true, actions, 0, nil, nil, mem.Angs, false, false, false
	end

	return false, {}, nil, nil, nil, angle_zero, false, false, false
end 

--????
local function get_function_source(fn)
	local info = debug.getinfo(fn)
	if info.short_src == "[C]" then
		return tostring(fn), "Native", -1, -1
	end

	local start_line, end_line = info.linedefined, info.lastlinedefined
	local file_path = info.source:gsub("^@", "")
	local content = file.Read(file_path, "MOD")
	if not content or #content:Trim() == 0 then return tostring(fn), "Anonymous", -1, -1 end

	local lines = ("\n"):Explode(content)
	local fn_source = table.concat(lines, "\n", start_line, end_line)
	return fn_source, file_path, start_line, end_line
end

---Basic aim and shoot handler for survivor bots.
---(Or anything that can hold a gun)
---@param bot GPlayer|table
---@param target GEntity
---@param maxDistance number
---@return boolean valid -- True if the handler ran corrcetly.
---@return table actions -- Table with a set of actions.
---@return number? speed -- The needed forwards speed for the bot.
---@return number? sideSpeed -- The needed side speed for the bot.
---@return number? upSpeed -- The needed upwards speed for the bot.
---@return GAngle aimDirection -- The wanted aim direction for the bot.
---@return boolean minorStuck -- True if the bot seems to be stuck on a ladder or similar.
---@return boolean majorStuck -- True if the bot seems to be stuck on props, or runs in circles.
---@return boolean facesHindrance -- True if the bot is walking slower than expected.

local aimTr = {
	mask = MASK_SHOT_HULL
}
function D3bot.Basics.AimAndShoot(bot, target, maxDistance)
	local mem = bot.D3bot_Mem

	if mem.BlockMovementUntil then
		if mem.BlockMovementUntil >= CurTime() then
			return false, {}, nil, nil, nil, mem.Angs, false, false, false
		else
			mem.BlockMovementUntil = nil
		end
	end

	local actions = {}
	local reloading

	if not IsValid(target) then return false, {}, nil, nil, nil, angle_zero, false, false, false end

	---@type GWeapon|table
	local weapon = bot:GetActiveWeapon()
	if not IsValid(weapon) then return false, {}, nil, nil, nil, angle_zero, false, false, false end
	if weapon:Clip1() <= 0 and not weapon.AmmoIfHas then reloading = true end
	if (weapon.GetNextReload and weapon:GetNextReload() or 0) > CurTime() - 0.5 then -- Subtract half a second, so it will re-trigger reloading if possible
		reloading = true
	end
	actions.Reload = reloading and math.random(5) == 1

	local origin = bot:GetShootPos()
	local bonePos = bot:D3bot_GetAttackPosOrNil(mem.AimHeightFactor or 1,target)

	local hitBones = {
		"ValveBiped.Bip01_Head1",
		"ValveBiped.Bip01_Spine",
	}

	for _,name in ipairs(hitBones) do
		local bone = target:LookupBone(name)
		if bone then
			bonePos = target:GetBonePosition(bone)
			break
		end
	end

	local targetPos = bonePos
	local dist = origin:DistToSqr(targetPos)

	if maxDistance and dist > math.pow(maxDistance, 2) then return false, {}, nil, nil, nil, angle_zero, false, false, false end

	-- TODO: Use fewer traces, cache result for a few frames
	aimTr.start = origin
	aimTr.endpos = targetPos
	aimTr.filter = player.GetAll()
	local tr = util.TraceLine(aimTr)
	local canShootTarget = not tr.Hit

	if not canShootTarget then mem.AimHeightFactor = math.Rand(0.5, 1) end

	actions.Attack = not reloading and bot:D3bot_IsLookingAt(targetPos, 0.9) and canShootTarget and not mem.WasPressingAttack and not target.SpawnProtection
	mem.WasPressingAttack = actions.Attack

	if targetPos and canShootTarget then
		bot:D3bot_AngsRotateTo((targetPos - origin):Angle(), D3bot.BotAngLerpFactor * 2)
	end

	if (not maxDistance or dist > math.pow(400,2)) and weapon.SecondaryAttack then
		local base = get_function_source(weapons.Get("weapon_zs_base").SecondaryAttack)
		local wep = get_function_source(weapon.SecondaryAttack)
		if base == wep then actions.Attack2 = true end
	end

	return (not reloading) and canShootTarget, actions, 0, nil, nil, mem.Angs, false, false, false
end

function D3bot.Basics.Reload(bot)
	local mem = bot.D3bot_Mem

	if mem.BlockMovementUntil then
		if mem.BlockMovementUntil >= CurTime() then
			return false, {}, nil, nil, nil, mem.Angs, false, false, false
		else
			mem.BlockMovementUntil = nil
		end
	end

	local actions = {}
	local reloading

	---@type GWeapon|table
	local weapon = bot:GetActiveWeapon()
	if not IsValid(weapon) then return false, {}, nil, nil, nil, angle_zero, false, false, false end
	if weapon:Clip1() <= weapon:GetMaxClip1() * 0.5 and not weapon.AmmoIfHas then reloading = true end
	if (weapon.GetNextReload and weapon:GetNextReload() or 0) > CurTime() - 0.5 then -- Subtract half a second, so it will re-trigger reloading if possible
		reloading = true
	end
	actions.Reload = reloading and math.random(5) == 1
	return true, actions, 0, nil, nil, mem.Angs, false, false, false
end

---Basic aim and shoot handler for survivor bots.
---(Or anything that can hold a gun)
---@param bot GPlayer|table
---@return boolean valid -- True if the handler ran corrcetly.
---@return table actions -- Table with a set of actions.
---@return number? speed -- The needed forwards speed for the bot.
---@return number? sideSpeed -- The needed side speed for the bot.
---@return number? upSpeed -- The needed upwards speed for the bot.
---@return GAngle aimDirection -- The wanted aim direction for the bot.
---@return boolean minorStuck -- True if the bot seems to be stuck on a ladder or similar.
---@return boolean majorStuck -- True if the bot seems to be stuck on props, or runs in circles.
---@return boolean facesHindrance -- True if the bot is walking slower than expected.
function D3bot.Basics.LookAround(bot)
	local mem = bot.D3bot_Mem

	if math.random(200) == 1 then 
		local randomplys = D3bot.From(player.GetAll()):Where(function(k, v) return bot:D3bot_CallHandlerFunction2("IsFriend",v) end).R
		mem.LookTarget = table.Random(randomplys)
	end

	if not IsValid(mem.LookTarget) then return false, {}, nil, nil, nil, angle_zero, false, false, false end

	local origin = bot:EyePos()

	bot:D3bot_AngsRotateTo((mem.LookTarget:EyePos()- origin):Angle(), D3bot.BotAngLerpFactor * 0.3)

	return true, {}, 0, nil, nil, mem.Angs, false, false, false
end
