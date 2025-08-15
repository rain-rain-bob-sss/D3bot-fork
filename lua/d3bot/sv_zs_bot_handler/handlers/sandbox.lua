D3bot.Handlers.Sandbox_Fallback = D3bot.Handlers.Sandbox_Fallback or {}
local HANDLER = D3bot.Handlers.Sandbox_Fallback

HANDLER.angOffshoot = 20

HANDLER.Fallback = true
function HANDLER.SelectorFunction(zombieClassName, team)
	return engine.ActiveGamemode() == "sandbox"
end

---Updates the bot move data every frame.
---@param bot GPlayer|table
---@param cmd GCUserCmd
function HANDLER.UpdateBotCmdFunction(bot, cmd)
	cmd:ClearButtons()
	cmd:ClearMovement()

	
	bot:D3bot_UpdatePathProgress()
	local mem = bot.D3bot_Mem
	local botPos = bot:GetPos()
	
	local result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
	if (result and math.abs(forwardSpeed or 0) > 30) then
		actions.Attack = false
	else
		result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle = D3bot.Basics.AimAndShoot(bot, mem.AttackTgtOrNil, mem.MaxShootingDistance) -- TODO: Make bots walk backwards while shooting
		if not result then
			result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle = D3bot.Basics.LookAround(bot)
			if not result then return end
		end
	end
	
	actions = actions or {}
	
	if bot:WaterLevel() == 3 and not mem.NextNodeOrNil then
		actions.Jump = true
	end

    if not bot:Alive() then actions.Attack = true end
	
	local buttons
	if actions then
		buttons = bit.bor(actions.MoveForward and IN_FORWARD or 0, actions.MoveBackward and IN_BACK or 0, actions.MoveLeft and IN_MOVELEFT or 0, actions.MoveRight and IN_MOVERIGHT or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Reload and IN_RELOAD or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0, actions.Phase and IN_ZOOM or 0)
	end
	
    aimAngle.r = 0
	if aimAngle then bot:SetEyeAngles(aimAngle)	cmd:SetViewAngles(aimAngle) end
	if forwardSpeed then cmd:SetForwardMove(forwardSpeed) end
	if sideSpeed then cmd:SetSideMove(sideSpeed) end
	if upSpeed then cmd:SetUpMove(upSpeed) end
	if buttons then cmd:SetButtons(buttons) end
end

---Called every frame.
---@param bot GPlayer

HANDLER.BotTgtFixationDistMin = 50
function HANDLER.ThinkFunction(bot)
	local mem = bot.D3bot_Mem
	local botPos = bot:GetPos()
	
    if HANDLER.CanShootTarget(bot, mem.TgtOrNil) then mem.AttackTgtOrNil = mem.TgtOrNil end
	if not HANDLER.IsEnemy(bot, mem.AttackTgtOrNil) then mem.AttackTgtOrNil = nil end

	-- Disable any human survivor logic when using source navmeshes, as it would need aditional adjustments to get it working.
	-- It's not worth the effort for survivor bots.
	if D3bot.UsingSourceNav then return end
	
	if mem.nextUpdateSurroundingPlayers and mem.nextUpdateSurroundingPlayers < CurTime() or not mem.nextUpdateSurroundingPlayers then
		if not mem.TgtOrNil or IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(botPos) > HANDLER.BotTgtFixationDistMin then
			mem.nextUpdateSurroundingPlayers = CurTime() + 0.5
			local targets = player.GetAll() -- TODO: Filter targets before sorting
			table.sort(targets, function(a, b) return botPos:DistToSqr(a:GetPos()) < botPos:DistToSqr(b:GetPos()) end)
			for k, v in ipairs(targets) do
				if IsValid(v) and botPos:DistToSqr(v:GetPos()) < 500*500 and HANDLER.CanBeTgt(bot, v) and bot:D3bot_CanSeeTarget(nil, v) then
					bot:D3bot_SetTgtOrNil(v, false, nil)
					mem.nextUpdateSurroundingPlayers = CurTime() + 5
					break
				end
				if k > 3 then break end
			end
		end
	end


	if mem.nextCheckTarget and mem.nextCheckTarget < CurTime() or not mem.nextCheckTarget then
		mem.nextCheckTarget = CurTime() + 0.9 + math.random() * 0.2
		if not HANDLER.CanBeTgt(bot, mem.TgtOrNil) then
			HANDLER.RerollTarget(bot)
		end
	end

    
	
	if mem.nextUpdateOffshoot and mem.nextUpdateOffshoot < CurTime() or not mem.nextUpdateOffshoot then
		mem.nextUpdateOffshoot = CurTime() + 0.2
		bot:D3bot_UpdateAngsOffshoot(HANDLER.angOffshoot)
	end
	
	local function pathCostFunction(node, linkedNode, link)
		local nodeMetadata = D3bot.NodeMetadata[linkedNode]
		local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		return playerFactorByUndead * 3000 - playerFactorBySurvivors * 4000
	end
	if mem.nextUpdatePath and mem.nextUpdatePath < CurTime() or not mem.nextUpdatePath then
		mem.nextUpdatePath = CurTime() + 0.9 + math.random() * 0.2
		bot:D3bot_UpdatePath(pathCostFunction, nil) -- This will not do anything as long as there is no target set (TgtOrNil, PosTgtOrNil, NodeTgtOrNil), the real magic happens in this handlers think function.
	end
	
	-- Change held weapon based on target distance
	if mem.nextHeldWeaponUpdate and mem.nextHeldWeaponUpdate < CurTime() or not mem.nextHeldWeaponUpdate then
		mem.nextHeldWeaponUpdate = CurTime() + 1 + math.random() * 1
		local weapons = bot:GetWeapons()
		local filteredWeapons = {}
		local bestRating, bestWeapon, bestMaxDistance = 0, nil, nil
		local enemyDistance = mem.AttackTgtOrNil and mem.AttackTgtOrNil:GetPos():Distance(bot:GetPos()) or 300
		for _, v in pairs(weapons) do
			local weaponType, rating, maxDistance = HANDLER.WeaponRatingFunction(v, enemyDistance)
			local ammoType = v:GetPrimaryAmmoType()
			local ammo = v:Clip1() + bot:GetAmmoCount(ammoType)
			-- Silly cheat to prevent bots from running out of ammo TODO: Add buy logic
			if ammo == 0 then
				bot:SetAmmo(50, ammoType)
			end
			
			if ammo > 0 and enemyDistance < maxDistance and bestRating < rating and weaponType == HANDLER.Weapon_Types.RANGED then
				bestRating, bestWeapon, bestMaxDistance = rating, v.ClassName, maxDistance
			end
		end
		if bestWeapon then
			bot:SelectWeapon(bestWeapon)
			mem.MaxShootingDistance = bestMaxDistance
		end
	end
end

---Called when the bot takes damage.
---@param bot GPlayer
---@param dmg GCTakeDamageInfo
function HANDLER.OnTakeDamageFunction(bot, dmg)
	local attacker = dmg:GetAttacker()
	if not HANDLER.CanBeAttackTgt(bot, attacker) then return end
	local mem = bot.D3bot_Mem
	--if IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(bot:GetPos()) <= D3bot.BotTgtFixationDistMin then return end
	mem.AttackTgtOrNil = attacker
	--bot:Say("Stop That! I'm gonna shoot you, "..attacker:GetName().."!")
	--bot:Say("help")
end

---Called when the bot damages something.
---@param bot GPlayer -- The bot that caused the damage.
---@param ent GEntity -- The entity that took damage.
---@param dmg GCTakeDamageInfo -- Information about the damage.
function HANDLER.OnDoDamageFunction(bot, ent, dmg)
	--bot:Say("Gotcha!")
end

---Called when the bot dies.
---@param bot GPlayer
function HANDLER.OnDeathFunction(bot)
	--bot:Say("rip me!")
end

-----------------------------------
-- Custom functions and settings --
-----------------------------------

HANDLER.Weapon_Types = {}
HANDLER.Weapon_Types.RANGED = 1
HANDLER.Weapon_Types.MELEE = 2

function HANDLER.WeaponRatingFunction(weapon, targetDistance)
	local sweptable = weapons.GetStored(weapon.ClassName)
    if not sweptable then
        return weapon.ClassName == "weapon_crowbar" and HANDLER.Weapon_Types.MELEE or HANDLER.Weapon_Types.RANGED,5,1000 
    end
	
	local targetDiameter = 6
	local targetArea = math.pi * math.pow(targetDiameter / 2, 2)
	
	local numShots = sweptable.Primary.NumShots or 1
	local damage = (sweptable.Damage or sweptable.Primary.Damage or 0)
	local delay = sweptable.Primary.Delay or 1
	local cone = 0.5
	
	local dmgPerSec = damage * numShots / delay -- TODO: Use more parameters like reload time.
	local maxDistance = targetDiameter / math.tan(math.rad(cone)) / 2
	local spreadArea = math.pi * math.pow(math.tan(math.rad(cone)) * targetDistance, 2)
	
	local areaIntersection = math.min(targetArea, spreadArea) / spreadArea
	
	local rating = dmgPerSec * areaIntersection
	
	return HANDLER.Weapon_Types.MELEE, rating, maxDistance
end

function HANDLER.FindEscapePath(bot, startNode, enemies)
	local tempNodePenalty = {}
	local escapeDirection = Vector()
	for _, enemy in pairs(enemies) do
		tempNodePenalty = D3bot.NeighbourNodeFalloff(D3bot.MapNavMesh:GetNearestNodeOrNil(enemy:GetPos()), 2, 1, 0.5, tempNodePenalty)
		escapeDirection:Add(bot:GetPos() - enemy:GetPos())
	end
	escapeDirection:Normalize()
	
	for _, enemy in pairs(enemies) do
		tempNodePenalty = D3bot.NeighbourNodeFalloff(D3bot.MapNavMesh:GetNearestNodeOrNil(enemy:GetPos()), 2, 1, 0.5, tempNodePenalty)
	end
	
	local function pathCostFunction(node, linkedNode, link)
		local directionPenalty
		if node == startNode then
			local direction = (linkedNode.Pos - node.Pos)
			directionPenalty = (1 - direction:Dot(escapeDirection)) * 1000
			--ClDebugOverlay.Line(GetPlayerByName("D3"), node.Pos, linkedNode.Pos, nil, Color(directionPenalty/2000*255, 0, 0), true)
		end
		local nodeMetadata = D3bot.NodeMetadata[linkedNode]
		local cost = (tempNodePenalty[linkedNode] or 0) * 500 + (directionPenalty or 0)
		return cost
	end
	local function heuristicCostFunction(node)
		local nodeMetadata = D3bot.NodeMetadata[node]
		return (tempNodePenalty[node] or 0) * 10
	end
	return D3bot.GetEscapeMeshPathOrNil(startNode, 50, pathCostFunction, heuristicCostFunction, {Walk = true})
end

function HANDLER.FindPathToHuman(node)
	local function pathCostFunction(node, linkedNode, link)
		return node.Pos:Distance(linkedNode.Pos) * 0.1
	end
	local function heuristicCostFunction(node)
		local nodeMetadata = D3bot.NodeMetadata[node]
		local playerFactor = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNASSIGNED or 0] or 0
		return -playerFactor * 5
	end
	--D3bot.Debug.DrawNodeMetadata(GetPlayerByName("D3"), D3bot.NodeMetadata, 5)
	--D3bot.Debug.DrawPath(GetPlayerByName("D3"), D3bot.GetEscapeMeshPathOrNil(node, 400, pathCostFunction, heuristicCostFunction, {Walk = true}), 5, Color(255, 0, 0), true)
	return D3bot.GetEscapeMeshPathOrNil(node, 400, pathCostFunction, heuristicCostFunction, {Walk = true})
end

function HANDLER.CanShootTarget(bot, target)
	if not IsValid(target) then return end
	local origin = bot:EyePos()
	local targetPos = target:EyePos()
	local tr = util.TraceLine({
		start = origin,
		endpos = targetPos,
		filter = player.GetAll(),
		mask = MASK_SHOT_HULL
	})
	return not tr.Hit
end

function HANDLER.FacesBarricade(bot)
	return false
end

function HANDLER.IsEnemy(bot, ply)
	if IsValid(ply) and bot ~= ply and ply:IsPlayer() and ply:GetObserverMode() == OBS_MODE_NONE and ply:Alive() then return true end
end

function HANDLER.IsFriend(bot, ply)
	return false
end

---Returns whether a target is valid.
---@param bot GPlayer
---@param target GPlayer|GEntity|any
function HANDLER.CanBeTgt(bot, target)
	return HANDLER.IsEnemy(bot,target)
end

---Rerolls the bot's target.
---@param bot GPlayer
function HANDLER.RerollTarget(bot)
	-- Get humans or non zombie players or any players in this order.
	local players = player.GetAll()
	bot:D3bot_SetTgtOrNil(table.Random(players), false, nil)
end


function HANDLER.CanBeAttackTgt(bot, target)
	if not target or not IsValid(target) then return end
	local ownTeam = bot:Team()
	if target:IsPlayer() and target ~= bot and target:GetObserverMode() == OBS_MODE_NONE and target:Alive() then return true end
end