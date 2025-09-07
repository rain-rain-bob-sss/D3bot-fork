D3bot.Handlers.Survivor_Fallback = D3bot.Handlers.Survivor_Fallback or {}
local HANDLER = D3bot.Handlers.Survivor_Fallback

HANDLER.angOffshoot = 5

HANDLER.Fallback = true
function HANDLER.SelectorFunction(zombieClassName, team)
	return team == TEAM_SURVIVOR
end

---Updates the bot move data every frame.
---@param bot GPlayer|table
---@param cmd GCUserCmd
function HANDLER.UpdateBotCmdFunction(bot, cmd)
	cmd:ClearButtons()
	cmd:ClearMovement()
	
	-- Fix knocked down bots from sliding around. (Workaround for the NoxiousNet codebase, as ply:Freeze() got removed from status_knockdown, status_revive, ...)
	-- Bug: We need to check the type of bot.Revive, as there is probably a bug in ZS that sets this value to a function in stead of a status entity
	if bot.KnockedDown and IsValid(bot.KnockedDown) or bot.Revive and type(bot.Revive) ~= "function" and IsValid(bot.Revive) then
		return
	end
	
	bot:D3bot_UpdatePathProgress()
	local mem = bot.D3bot_Mem
	local botPos = bot:GetPos()

	local nodeOrNil = mem.NodeOrNil
	local nextNodeOrNil = mem.NextNodeOrNil
	local currentLinkOrNil
	if D3bot.UsingSourceNav then
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil:SharesLink(nodeOrNil)
	else
		currentLinkOrNil = nodeOrNil and nextNodeOrNil and nextNodeOrNil.LinkByLinkedNode[nodeOrNil]
	end

	local memAngs = mem.Angs or angle_zero
	local result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.Walk(bot, nextNodeOrNil and nextNodeOrNil.Pos or bot:GetPos(), nil)--D3bot.Basics.WalkAttackAuto(bot)
	local result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2
	if result and (math.abs(forwardSpeed or 0) + math.abs(sideSpeed or 0) + math.abs(upSpeed or 0)) >= 30 then
		if not mem.InDanger then
			local walkAngs = mem.Angs
			mem.Angs = memAngs
			result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2 = D3bot.Basics.AimAndShoot(bot, mem.AttackTgtOrNil, mem.MaxShootingDistance)
			if not result2 then
				--result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2 = D3bot.Basics.LookAround(bot)
				--if not result then return end
				result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2 = D3bot.Basics.Reload(bot)
				mem.Angs = walkAngs
			else
				aimAngle = aimAngle2
				mem.Angs = aimAngle2
			end
			actions.Attack = actions2.Attack
			actions.Attack2 = actions2.Attack2
			actions.Reload = actions2.Reload
		else
			result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2 = D3bot.Basics.Reload(bot)
			actions.Reload = actions2.Reload
		end
	else
		result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle = D3bot.Basics.AimAndShoot(bot, mem.AttackTgtOrNil, mem.MaxShootingDistance) -- TODO: Make bots walk backwards while shooting
		if not result then
			result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle = D3bot.Basics.LookAround(bot)
			result2, actions2, forwardSpeed2, sideSpeed2, upSpeed2, aimAngle2 = D3bot.Basics.Reload(bot)
			actions.Reload = actions2.Reload
			if not result then return end
		end
	end
	
	actions = actions or {}
	
	if bot:WaterLevel() == 3 and not mem.NextNodeOrNil then
		actions.Jump = true
	end
	
	if facesHindrance and HANDLER.FacesBarricade(bot) then
		mem.PhaseTime = CurTime()
	end
	if mem.PhaseTime and mem.PhaseTime > CurTime() - 1 and math.random(2) == 1 then
		if not mem.TgtOrNil and not mem.PosTgtOrNil and not mem.NodeTgtOrNil then
			-- If ghosting but there is no target, set nearby player as target
			local friends = D3bot.From(player.GetHumans()):Where(function(k, v) return HANDLER.IsFriend(bot, v) and botPos:DistToSqr(v:GetPos()) < 500*500 end).R
			bot:D3bot_SetTgtOrNil(table.Random(friends), true, nil)
		end
		actions.Phase = true
	end
	
	local buttons
	if actions then
		buttons = bit.bor(actions.MoveForward and IN_FORWARD or 0, actions.MoveBackward and IN_BACK or 0, actions.MoveLeft and IN_MOVELEFT or 0, actions.MoveRight and IN_MOVERIGHT or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Reload and IN_RELOAD or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0, actions.Phase and IN_ZOOM or 0)
	end

	forwardSpeed,sideSpeed = D3bot.Basics.AirStrafe(bot,forwardSpeed,sideSpeed)
	
	if aimAngle then bot:SetEyeAngles(aimAngle)	cmd:SetViewAngles(aimAngle) end
	if forwardSpeed then cmd:SetForwardMove(forwardSpeed) end
	if sideSpeed then cmd:SetSideMove(sideSpeed) end
	if upSpeed then cmd:SetUpMove(upSpeed) end
	if buttons then cmd:SetButtons(buttons) end
end

---Called every frame.
---@param bot GPlayer
function HANDLER.ThinkFunction(bot)
	local mem = bot.D3bot_Mem
	local botPos = bot:GetPos()
	
	if not HANDLER.IsEnemy(bot, mem.AttackTgtOrNil) then mem.AttackTgtOrNil = nil end

	-- Disable any human survivor logic when using source navmeshes, as it would need aditional adjustments to get it working.
	-- It's not worth the effort for survivor bots.
	if D3bot.UsingSourceNav then return end
	
	if mem.nextUpdateSurroundingPlayers and mem.nextUpdateSurroundingPlayers < CurTime() or not mem.nextUpdateSurroundingPlayers then
		mem.nextUpdateSurroundingPlayers = CurTime() + 0.4 + math.random() * 0.2
		local enemies = D3bot.From(player.GetAll()):Where(function(k, v) return HANDLER.IsEnemy(bot, v) end).R
		local closeEnemies = D3bot.From(enemies):Where(function(k, v) return botPos:DistToSqr(v:GetPos()) < 1000*1000 end).R -- TODO: Constant for the distance
		local closerEnemies = D3bot.From(closeEnemies):Where(function(k, v) return botPos:DistToSqr(v:GetPos()) < 600*600 end).R -- TODO: Constant for the distance
		local ownTeam = bot:Team()
		local canDamageTeam = PlayerCanDamageTeam or function() end
		local dangerdist = (100 * math.Clamp(1 / 1 - (bot:Health() / bot:GetMaxHealth()),1,2)) ^ 2
		local dangercloseEnemies = D3bot.From(closerEnemies):Where(function(k, v) return (botPos:DistToSqr(v:GetPos()) < dangerdist) or v.SpawnProtection end).R -- TODO: Constant for the distance
		local newAttackTarget = table.Random(dangercloseEnemies)
		local try = function(e)
			if not HANDLER.CanShootTarget(bot, newAttackTarget) then
				newAttackTarget = table.Random(e)
			end
		end
		try(closerEnemies)
		try(closeEnemies)
		try(enemies)
		if HANDLER.CanShootTarget(bot, newAttackTarget) then mem.AttackTgtOrNil = newAttackTarget end

		mem.dangercloseEnemies = dangercloseEnemies

		if table.Count(dangercloseEnemies) > 0 then
			local faster = false
			local speed = bot:GetWalkSpeed()
			for _, v in ipairs(dangercloseEnemies) do
				if v:GetWalkSpeed() >= speed then
					faster = true
					break
				end
			end
			mem.InDanger = not faster
			local rand = table.Random(dangercloseEnemies)
			--if HANDLER.CanShootTarget(bot, rand) then
				mem.AttackTgtOrNil = rand
			--end
			-- Check if undead can see/walk to bot, and then calculate escape path.
			if mem.AttackTgtOrNil:D3bot_CanSeeTarget(nil, bot) and (not mem.NextNodeOrNil or (mem.lastEscapePath or 0) < CurTime() - 2) then
				mem.lastEscapePath = CurTime()
				local escapePath = HANDLER.FindEscapePath(bot, D3bot.MapNavMesh:GetNearestNodeOrNil(botPos), closerEnemies)
				if escapePath then
					--D3bot.Debug.DrawPath(GetPlayerByName("D3"), escapePath, nil, nil, true)
					mem.holdPathTime = CurTime() + 2
					bot:D3bot_SetPath(escapePath, false)
				end
			end
		else
			mem.InDanger = false
			if not mem.holdPathTime or mem.holdPathTime < CurTime() then
				bot:D3bot_ResetTgt()
			end
			if not mem.NextNodeOrNil and ((mem.nextHumanPath or 0) < CurTime() or bot:WaterLevel() == 3) then
				mem.nextHumanPath = CurTime() + 2
				local path = (table.Count(closeEnemies) > 0) and HANDLER.FindEscapePath(bot, D3bot.MapNavMesh:GetNearestNodeOrNil(botPos), (table.Count(closerEnemies) > 0) and closerEnemies or closeEnemies) or HANDLER.FindPathToRandomNode(D3bot.MapNavMesh:GetNearestNodeOrNil(botPos))
				if path then
					mem.holdPathTime = CurTime() + 2
					bot:D3bot_SetPath(path, false)
				end
			end
		end
	end
	
	if mem.nextUpdateOffshoot and mem.nextUpdateOffshoot < CurTime() or not mem.nextUpdateOffshoot then
		mem.nextUpdateOffshoot = CurTime() + 0.4 + math.random() * 0.2
		bot:D3bot_UpdateAngsOffshoot(HANDLER.angOffshoot)
	end
	
	local function pathCostFunction(node, linkedNode, link)
		local nodeMetadata = D3bot.NodeMetadata[linkedNode]
		local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		return playerFactorByUndead * 3000 - playerFactorBySurvivors * 4000
	end
	if mem.nextUpdatePath and mem.nextUpdatePath < CurTime() or not mem.nextUpdatePath then
		mem.nextUpdatePath = CurTime() + 0.4
		bot:D3bot_UpdatePath(pathCostFunction, nil) -- This will not do anything as long as there is no target set (TgtOrNil, PosTgtOrNil, NodeTgtOrNil), the real magic happens in this handlers think function.
	end
	
	-- Change held weapon based on target distance
	if not mem.nextHeldWeaponUpdate or (mem.nextHeldWeaponUpdate and mem.nextHeldWeaponUpdate < CurTime()) then
		mem.nextHeldWeaponUpdate = CurTime() + 1 + 10 * math.Rand(0.1,1)
		local weapons = bot:GetWeapons()
		local filteredWeapons = {}
		local bestRating, bestWeapon, bestMaxDistance = 0, nil, nil
		local enemyDistance = mem.AttackTgtOrNil and mem.AttackTgtOrNil:GetPos():Distance(bot:GetPos()) or 300
		for _, v in pairs(weapons) do
			if v.DeployClass then 
				filteredWeapons[#filteredWeapons + 1] = v
				continue 
			end
			local weaponType, rating, maxDistance = HANDLER.WeaponRatingFunction(v, enemyDistance)

			rating = rating + math.random(-5,5)
			
			local ammoType = v:GetPrimaryAmmoType()
			local ammo = v:Clip1() + bot:GetAmmoCount(ammoType)
			if enemyDistance < maxDistance and bestRating < rating and weaponType == HANDLER.Weapon_Types.RANGED then
				bestRating, bestWeapon, bestMaxDistance = rating, v.ClassName, maxDistance
			end
		end

		if bestWeapon then
			bot:SelectWeapon(bestWeapon)
			mem.MaxShootingDistance = math.max(1000,bestMaxDistance)
		end

		if bot:IsBot() then
			for i,item in ipairs(GAMEMODE.Items) do
				if item.SWEP and item.PointShop and GAMEMODE:GetInventoryItemType(item.SWEP) ~= INVCAT_TRINKETS and not item.CanMakeFromScrap and not bot:HasWeapon(item.SWEP) and math.random(1,5) == 1 then HANDLER.Purchase(bot,tostring(i)) if math.random(1,10) == 1 then break end end
			end
		end
	end

	local weapon = bot:GetActiveWeapon()
	if IsValid(weapon) then
		local ammoType = weapon:GetPrimaryAmmoType()
		local ammo = bot:GetAmmoCount(ammoType)
		-- Silly cheat to prevent bots from running out of ammo TODO: Add buy logic
		if ammo <= 15 then
			bot:SetAmmo(100, ammoType)
		end
	end
	
	-- Win the game by escaping via sigil doors
	if GAMEMODE:GetWave() >= GAMEMODE:GetNumberOfWaves() then
		if mem.nextEscapeUpdate and mem.nextEscapeUpdate < CurTime() or not mem.nextEscapeUpdate then
			mem.nextEscapeUpdate = CurTime() + 4 + math.random() * 2
			
			local escapeDoors = D3bot.GetEntsOfClss({"prop_obj_exit"})
			local closestDoor, bestDistanceSqr = nil, math.huge
			for k, v in pairs(escapeDoors) do
				local distSqr = v:GetPos():DistToSqr(botPos)
				if bestDistanceSqr > distSqr then
					closestDoor, bestDistanceSqr = v, distSqr
				end
			end
			if closestDoor then
				bot:D3bot_SetTgtOrNil(closestDoor, true, 0)
			end
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
	local sweptable = weapons.GetStored(weapon.ClassName) or weapon:GetTable()
	local weaponType = HANDLER.Weapon_Types.MELEE
	if not weapon.IsMelee then
		weaponType = HANDLER.Weapon_Types.RANGED
	end
	
	--local targetDiameter = 6
	--local targetArea = math.pi * math.pow(targetDiameter / 2, 2)
	
	local numShots = sweptable.Primary.NumShots or 1
	local damage = (sweptable.Damage or sweptable.Primary.Damage or 0)
	local delay = sweptable.Primary.Delay or 1
	local cone = weapon.GetCone and weapon:GetCone() or ((weapon.ConeMax or 45) + (weapon.ConeMin or 45)*6) / 7
	
	local dmgPerSec = damage * numShots / delay -- TODO: Use more parameters like reload time.
	--local maxDistance = targetDiameter / math.tan(math.rad(cone)) / 2
	--local spreadArea = math.pi * math.pow(math.tan(math.rad(cone)) * targetDistance, 2)
	
	--local areaIntersection = math.min(targetArea, spreadArea) / spreadArea
	
	local rating = dmgPerSec - (cone * 0.06 * math.min(3,targetDistance / 500))-- * areaIntersection
	
	return weaponType, rating, weaponType == HANDLER.Weapon_Types.MELEE and 32 or 2048 --maxDistance
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
		local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		local cost = -playerFactorBySurvivors * 50 + playerFactorByUndead * 150 + (tempNodePenalty[linkedNode] or 0) * 500 + (directionPenalty or 0)
		--for _, enemy in pairs(enemies) do
		--	cost = cost + 100 / (LerpVector(0.5, node.Pos, linkedNode.Pos):Distance(enemy:GetPos()) + 100) * 0.1 * node.Pos:Distance(linkedNode.Pos) -- Weight by link length
		--end
		return cost-- + node.Pos:Distance(linkedNode.Pos) * 2
	end
	local function heuristicCostFunction(node)
		local nodeMetadata = D3bot.NodeMetadata[node]
		--local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		return playerFactorByUndead * 150 + (tempNodePenalty[node] or 0) * 10
	end
	return D3bot.GetEscapeMeshPathOrNil(startNode, 50, pathCostFunction, heuristicCostFunction, {Walk = true})
end

function HANDLER.FindPathToHuman(node)
	local function pathCostFunction(node, linkedNode, link)
		return node.Pos:Distance(linkedNode.Pos) * 0.1
	end
	local function heuristicCostFunction(node)
		local nodeMetadata = D3bot.NodeMetadata[node]
		local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		return -playerFactorBySurvivors * 1600000 + playerFactorByUndead * 500000
	end
	--D3bot.Debug.DrawNodeMetadata(GetPlayerByName("D3"), D3bot.NodeMetadata, 5)
	--D3bot.Debug.DrawPath(GetPlayerByName("D3"), D3bot.GetEscapeMeshPathOrNil(node, 400, pathCostFunction, heuristicCostFunction, {Walk = true}), 5, Color(255, 0, 0), true)
	return D3bot.GetEscapeMeshPathOrNil(node, 400, pathCostFunction, heuristicCostFunction, {Walk = true})
end

function HANDLER.FindPathToRandomNode(node)
	local function pathCostFunction(node, linkedNode, link)
		return node.Pos:Distance(linkedNode.Pos) * 0.1
	end
	local function heuristicCostFunction(node)
		local nodeMetadata = D3bot.NodeMetadata[node]
		local playerFactorBySurvivors = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_SURVIVOR] or 0
		local playerFactorByUndead = nodeMetadata and nodeMetadata.PlayerFactorByTeam and nodeMetadata.PlayerFactorByTeam[TEAM_UNDEAD] or 0
		for _, ent in ipairs(ents.FindByClass("zombiegasses")) do
			if ent:GetPos():DistToSqr(node.Pos) <= math.pow(ent:GetRadius(),2) then
				return 5000000
			end
		end
		return math.random(-99999,99999) - playerFactorBySurvivors * 50000 * math.Rand(0.5,1) + playerFactorByUndead * 1000000 * math.Rand(0.5,1)
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
		mask = MASK_SHOT
	})
	return not tr.Hit
end

function HANDLER.FacesBarricade(bot)
	local tr = bot:GetEyeTrace()
	local entity = tr.Entity
	local distanceSqr = bot:EyePos():DistToSqr(tr.HitPos)
	if not IsValid(entity) or not entity:IsNailed() then return end
	return distanceSqr < 100*100
end

function HANDLER.IsEnemy(bot, ply)
	if not IsValid(ply) then return false end
	local ownTeam = bot:Team()
	local canDamageTeam = PlayerCanDamageTeam and PlayerCanDamageTeam(bot,ply)
	local testTarget = D3bot.TestTarget
	if IsValid(testTarget) and ply ~= testTarget then return false end
	if bot ~= ply and ply:IsPlayer() and (ply:Team() ~= ownTeam or canDamageTeam) and ply:GetObserverMode() == OBS_MODE_NONE and ply:Alive() --[[and not ply:IsFlagSet(FL_NOTARGET)]] then return true end
end

function HANDLER.IsFriend(bot, ply)
	local ownTeam = bot:Team()
	local canDamageTeam = PlayerCanDamageTeam and PlayerCanDamageTeam(bot,ply)
	if IsValid(ply) and bot ~= ply and ply:IsPlayer() and (ply:Team() == ownTeam and not canDamageTeam) and ply:GetObserverMode() == OBS_MODE_NONE and ply:Alive() --[[and not ply:IsFlagSet(FL_NOTARGET)]] then return true end
end

function HANDLER.CanBeAttackTgt(bot, target)
	if not target or not IsValid(target) then return end
	local ownTeam = bot:Team()
	local canDamageTeam = PlayerCanDamageTeam and PlayerCanDamageTeam(bot,target)
	local testTarget = D3bot.TestTarget
	if IsValid(testTarget) and target ~= testTarget then return false end
	if target:IsPlayer() and target ~= bot and (target:Team() ~= ownTeam or canDamageTeam) and target:GetObserverMode() == OBS_MODE_NONE and target:Alive() --[[and not target:IsFlagSet(FL_NOTARGET)]] then return true end
end

function HANDLER.Purchase(bot,item,scrap)
	bot.ArsenalZone = bot
	concommand.Run(bot,"zs_pointsshopbuy",{item,scrap})
end

hook.Add("PlayerCanPurchase",D3bot.BotHooksId,function(bot)
	if bot:IsBot() then return true end
end)