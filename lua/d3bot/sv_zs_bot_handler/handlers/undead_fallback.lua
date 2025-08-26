D3bot.Handlers.Undead_Fallback = D3bot.Handlers.Undead_Fallback or {}
local HANDLER = D3bot.Handlers.Undead_Fallback

HANDLER.AngOffshoot = 30
HANDLER.BotTgtFixationDistMin = 250
HANDLER.BotClasses = {
	"Zombie", "Zombie", "Zombie",
	"Gore Blaster Zombie","Gore Blaster Zombie","Gore Blaster Zombie",
	"Chem Burster","Chem Burster",
	"Ghoul","Ghoul",
	"Elder Ghoul","Elder Ghoul",
	"Noxious Ghoul","Noxious Ghoul",
	"Wraith", "Wraith", "Wraith",
	"Skeletal Shambler",
	"Skeletal Walker","Skeletal Walker",
	"Shadow Walker","Shadow Walker","Shadow Walker",
	"Shadow Lurker",
	"Bloated Zombie", "Bloated Zombie", "Bloated Zombie",
	"Fast Zombie", "Fast Zombie", "Fast Zombie", "Fast Zombie","Fast Zombie","Fast Zombie","Fast Zombie",
	"Slingshot Zombie","Slingshot Zombie","Slingshot Zombie",
	"Poison Zombie", "Poison Zombie", "Poison Zombie",
	"Wild Poison Zombie","Wild Poison Zombie",
	"Zombine", "Zombine", "Zombine", "Zombine", "Zombine",
	"Charger","Charger","Charger",
}

HANDLER.RandomSecondaryAttack = {
	Ghoul = {MinTime = 5, MaxTime = 7},
	["Elder Ghoul"] = {MinTime = 5, MaxTime = 7},
	["Noxious Ghoul"] = {MinTime = 5, MaxTime = 7},
	["Frigid Revenant"] = {MinTime = 5, MaxTime = 7},
	["Devourer"] = {MinTime = 5, MaxTime = 7},
	Charger = {MinTime = 4, MaxTime = 5, SeeTarget = true},
	["Poison Zombie"] = {MinTime = 5, MaxTime = 7, SeeTarget = true, Range = 100}, -- Slows them too much
	["Wild Poison Zombie"] = {MinTime = 5, MaxTime = 7, SeeTarget = true, Range = 100}, -- Slows them too much
}
HANDLER.PrimaryAttack = {
	["Chem Burster"] = {AttackBarricade = true,NearTarget = true,Stuck = false}
}

HANDLER.CreateMoves = {
	Charger = function (pl, cmd)
		local wep = pl:GetActiveWeapon()
		if wep:IsValid() and wep.m_ViewAngles and ((wep.GetChargeStart and wep:GetChargeStart() ~= 0) or wep.IsCharging) then
			local maxdiff = FrameTime() * 15
			local mindiff = -maxdiff
			local originalangles = wep.m_ViewAngles
			local viewangles = cmd:GetViewAngles()

			local diff = math.AngleDifference(viewangles.yaw, originalangles.yaw)
			if diff > maxdiff or diff < mindiff then
				viewangles.yaw = math.NormalizeAngle(originalangles.yaw + math.Clamp(diff, mindiff, maxdiff))
			end

			wep.m_ViewAngles = viewangles

			cmd:SetViewAngles(viewangles)
		end
	end
}

HANDLER.Fallback = true
function HANDLER.SelectorFunction(zombieClassName, team)
	return team == TEAM_UNDEAD
end

---Updates the bot move data every frame.
---@param bot GPlayer|table
---@param cmd GCUserCmd
function HANDLER.UpdateBotCmdFunction(bot, cmd)
	cmd:ClearButtons()
	cmd:ClearMovement()

	-- Fix knocked down bots from sliding around. (Workaround for the NoxiousNet codebase, as ply:Freeze() got removed from status_knockdown, status_revive, ...)
	-- Bug: We need to check the type of bot.Revive, as there is probably a bug in ZS that sets this value to a function instead of userdata
	if bot.KnockedDown and IsValid(bot.KnockedDown) or bot.Revive and type(bot.Revive) ~= "function" and IsValid(bot.Revive) then
		return
	end

	if not bot:Alive() then
		-- Get back into the game.
		cmd:SetButtons(IN_ATTACK)
		return
	end

	local mem = bot.D3bot_Mem

	bot:D3bot_UpdatePathProgress()
	D3bot.Basics.SuicideOrRetarget(bot)

	local trynest = false

	local result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.PounceAuto(bot, false)
	if not result then
		if bot:GetZombieClassTable().Name == "Flesh Creeper" and bot:Alive() then 
			local cannest,node = D3bot.Basics.FindNestPoint(bot)
			if cannest then
				trynest = true
				bot:D3bot_SetNodeTgtOrNil(node)
			else
				if mem.NodeTgtOrNil then 
					mem.NodeTgtOrNil = nil
				end
			end
			result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
			if not result then 
				return 
			end
		else
			result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
			if not result then
				return
			end
		end
	end

	-- If facesHindrance is true, let the bot search for nearby barricade objects.
	-- But only if the bot didn't do damage for some time.
	if facesHindrance and CurTime() - (bot.D3bot_LastDamage or 0) > 2 then
		local entity, entityPos = bot:D3bot_FindBarricadeEntity(1) -- One random line trace per frame.
		if entity and entityPos then
			mem.BarricadeAttackEntity, mem.BarricadeAttackPos = entity, entityPos
		end
	end

	actions = actions or {}

	-- Simple hack for throwing poison randomly.
	-- TODO: Only throw if possible target is close enough. Aiming. Timing.
	local secAttack = HANDLER.RandomSecondaryAttack[GAMEMODE.ZombieClasses[bot:GetZombieClass()].Name]
	if secAttack then
		local inRange = false
		local range = secAttack.Range or 0
		local origin = bot:GetShootPos()
		local attackPos = bot:D3bot_GetAttackPosOrNilFuture(nil, math.Rand(0, D3bot.BotAimPosVelocityOffshoot))
		if attackPos and attackPos:DistToSqr(origin) < math.pow(range, 2) then
			inRange = true
		end

		local targetvel = IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetVelocity():Length() or 0
		if (not secAttack.SeeTarget or bot:D3bot_CanSeeTargetCached()) and (not secAttack.Range or inRange) and (not secAttack.TargetVelMax or secAttack.TargetVelMax >= targetvel) then
			if not mem.NextThrowPoisonTime or mem.NextThrowPoisonTime <= CurTime() then
				mem.NextThrowPoisonTime = CurTime() + secAttack.MinTime + math.random() * (secAttack.MaxTime - secAttack.MinTime)
				actions.Attack = false
				actions.Attack2 = true
			end
		end
	end

	local primAttack = HANDLER.PrimaryAttack[GAMEMODE.ZombieClasses[bot:GetZombieClass()].Name]
	if primAttack then 
		local can = false
		if IsValid(mem.BarricadeAttackEntity) and primAttack.AttackBarricade then 
			can = true
		end

		if facesHindrance and primAttack.Stuck then 
			can = true
		end

		if primAttack.NearTarget then
			local weapon = bot:GetActiveWeapon()
			local range = (IsValid(weapon) and weapon.MeleeReach or 75) + 25 -- Either MeleeReach + 25, or 100.
			-- We don't have a case that can be handled by the basic walk handler.
			-- So we just attack something directly.
			local origin = bot:GetShootPos() -- Attack origin of the bot.
			local attackPos = bot:D3bot_GetAttackPosOrNilFuture(nil, math.Rand(0, D3bot.BotAimPosVelocityOffshoot)) -- Target attack position, for aiming.
			if attackPos and attackPos:DistToSqr(origin) < math.pow(range, 2) then
				can = true
			end
		end

		if actions and not can then actions.Attack = false end

		if actions.Attack and primAttack.SecondaryAttack then actions.Attack = false actions.Attack2 = true end
	end

	if (trynest and facesHindrance) and bot:Alive() then actions.Attack = false actions.Attack2 = true actions.Jump = false majorStuck = false end

	local wep = bot:GetActiveWeapon()
	if IsValid(wep) and wep.GetBattlecry then 
		local canhowl = true
		if wep.GetNextHowl and (wep:GetNextHowl() > CurTime()) then canhowl = false end
		if wep:GetNextSecondaryFire() > CurTime() then canhowl = false end
		if (actions.Attack) and canhowl then
			actions.Attack2 = true
			actions.Attack = false
		end
	end

	local buttons
	if actions then
		buttons = bit.bor(actions.MoveForward and IN_FORWARD or 0, actions.MoveBackward and IN_BACK or 0, actions.MoveLeft and IN_MOVELEFT or 0, actions.MoveRight and IN_MOVERIGHT or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0)
	end

	if majorStuck and GAMEMODE:GetWaveActive() then bot:Kill() end

	if aimAngle then bot:SetEyeAngles(aimAngle)	cmd:SetViewAngles(aimAngle) end
	if forwardSpeed then cmd:SetForwardMove(forwardSpeed) end
	if sideSpeed then cmd:SetSideMove(sideSpeed) end
	if upSpeed then cmd:SetUpMove(upSpeed) end
	cmd:SetButtons(buttons)


	local createMove = HANDLER.CreateMoves[GAMEMODE.ZombieClasses[bot:GetZombieClass()].Name]
	--uncomment to make bots stop cheating
	--if createMove then createMove(bot, cmd) end
end

local targetPriorities = {
	["player"] = 500,
	["prop_obj_sigil"] = 100,
}

function HANDLER.TargetScore(bot,target,botPos,maxDist)
	if not IsValid(target) then return -math.huge end
	botPos = botPos or bot:GetPos()
	local dist = botPos:DistToSqr(target:GetPos())
	local score = ((maxDist or 500*500) - math.min(maxDist or 500*500,dist)) * 0.5
		+ (targetPriorities[target:GetClass()] or 0)
	return score
end

---Called every frame.
---@param bot GPlayer
function HANDLER.ThinkFunction(bot)
	local mem = bot.D3bot_Mem

	local botPos = bot:GetPos()

	if mem.nextUpdateSurroundingPlayers and mem.nextUpdateSurroundingPlayers < CurTime() or not mem.nextUpdateSurroundingPlayers then
		if not mem.TgtOrNil or IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(botPos) > HANDLER.BotTgtFixationDistMin then
			mem.nextUpdateSurroundingPlayers = CurTime() + 0.9 + math.random() * 0.2
			local targets = player.GetAll() -- TODO: Filter targets before sorting
			table.sort(targets, function(a, b) return HANDLER.TargetScore(bot,a,botPos) > HANDLER.TargetScore(bot,b,botPos) end)
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
		mem.nextUpdateOffshoot = CurTime() + 0.4 + math.random() * 0.2
		bot:D3bot_UpdateAngsOffshoot(HANDLER.AngOffshoot)
	end

	local pathCostFunction

	if D3bot.UsingSourceNav then
		if not pathCostFunction then
			pathCostFunction = function( cArea, nArea, link )
				local linkMetaData = link:GetMetaData()
				local linkPenalty = linkMetaData and linkMetaData.ZombieDeathCost or 0
				return linkPenalty * ( mem.ConsidersPathLethality and 1 or 0 )
			end
		end
	else
		if not pathCostFunction then
			pathCostFunction = function( node, linkedNode, link )
				local linkMetadata = D3bot.LinkMetadata[link]
				local linkPenalty = linkMetadata and linkMetadata.ZombieDeathCost or 0
				return linkPenalty * (mem.ConsidersPathLethality and 1 or 0)
			end
		end
	end

	if mem.nextUpdatePath and mem.nextUpdatePath < CurTime() or not mem.nextUpdatePath then
		mem.nextUpdatePath = CurTime() + 0.9 + math.random() * 0.2
		bot:D3bot_UpdatePath( pathCostFunction, nil )
	end
end

---Called when the bot takes damage.
---@param bot GPlayer
---@param dmg GCTakeDamageInfo
function HANDLER.OnTakeDamageFunction(bot, dmg)
	local attacker = dmg:GetAttacker()
	if not HANDLER.CanBeTgt(bot, attacker) then return end
	local mem = bot.D3bot_Mem
	if IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():DistToSqr(bot:GetPos()) <= math.pow(HANDLER.BotTgtFixationDistMin, 2) then return end
	mem.TgtOrNil = attacker
	--bot:Say("Ouch! Fuck you "..attacker:GetName().."! I'm gonna kill you!")
end

---Called when the bot damages something.
---@param bot GPlayer -- The bot that caused the damage.
---@param ent GEntity -- The entity that took damage.
---@param dmg GCTakeDamageInfo -- Information about the damage.
function HANDLER.OnDoDamageFunction(bot, ent, dmg)
	local mem = bot.D3bot_Mem

	-- If the zombie hits a barricade prop, store that hit position for the next attack.
	if ent and ent:IsValid() and ent:D3bot_IsBarricade() then
		mem.BarricadeAttackEntity, mem.BarricadeAttackPos = ent, dmg:GetDamagePosition()
	end

	--ClDebugOverlay.Sphere(GetPlayerByName("D3"), dmg:GetDamagePosition(), 2, 1, Color(255,255,255), false)
	--bot:Say("Gotcha!")
end

---Called when the bot dies.
---@param bot GPlayer
function HANDLER.OnDeathFunction(bot)
	--bot:Say("rip me!")
	bot:D3bot_RerollClass(HANDLER.BotClasses) -- TODO: Situation depending reroll of the zombie class
	HANDLER.RerollTarget(bot)
end

-----------------------------------
-- Custom functions and settings --
-----------------------------------

local potTargetEntClasses = {"prop_*turret*", "prop_arsenalcrate", "prop_manhack*", "prop_obj_sigil", "prop_zapper*"}
local potEntTargets = nil

---Returns whether a target is valid.
---@param bot GPlayer
---@param target GPlayer|GEntity|any
function HANDLER.CanBeTgt(bot, target)
	if not target or not IsValid(target) then return end
	if target:IsPlayer() and target ~= bot and (target:Team() ~= TEAM_UNDEAD or GAMEMODE:GetEndRound()) and target:GetObserverMode() == OBS_MODE_NONE and not target:IsFlagSet(FL_NOTARGET) and target:Alive() then return true end
	if target:GetClass() == "prop_obj_sigil" and target:GetSigilCorrupted() then return false end -- Special case to ignore corrupted sigils.
	if potEntTargets and table.HasValue(potEntTargets, target) then return true end

	return false
end

---Rerolls the bot's target.
---@param bot GPlayer
function HANDLER.RerollTarget(bot)

	local mem = bot.D3bot_Mem

	if IsValid(mem.TargetAfterSpawned) then --We need to target it again.
		bot:D3bot_SetTgtOrNil(mem.TargetAfterSpawned, false, nil)
		mem.TargetAfterSpawned = nil
		return
	end

	-- Get humans or non zombie players or any players in this order.
	local players = D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_HUMAN))
	if #players == 0 and TEAM_UNDEAD then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
		players = D3bot.From(players):Where(function(k, v) return v:Team() ~= TEAM_UNDEAD end).R
	end
	if #players == 0 then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
	end
	potEntTargets = D3bot.GetEntsOfClss(potTargetEntClasses)
	local potTargets = table.Add(players, potEntTargets)
	table.sort(potTargets, function(a, b) return HANDLER.TargetScore(bot,a,_,65536) > HANDLER.TargetScore(bot,b,_,65536) end)
	bot:D3bot_SetTgtOrNil(potTargets[1], false, nil)
end
