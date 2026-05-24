D3bot.Handlers.Undead_Fallback = D3bot.Handlers.Undead_Fallback or {}
local HANDLER = D3bot.Handlers.Undead_Fallback

HANDLER.AngOffshoot = 30
HANDLER.BotTgtFixationDistMin = 250

--function to more effectively edit which classes should bots use
local function addToSelectClasses(class, times)
	for i=1,times do
		HANDLER.BotClasses[#HANDLER.BotClasses + 1] = class
	end
end
HANDLER.BotClasses = {}
addToSelectClasses("Agile Dead", 2)
addToSelectClasses("Zombie", 4)
addToSelectClasses("Gore Blaster Zombie", 3)
addToSelectClasses("Chem Burster", 2)
addToSelectClasses("Ghoul", 2)
addToSelectClasses("Elder Ghoul", 2)
addToSelectClasses("Noxious Ghoul", 2)
addToSelectClasses("Wraith", 3)
addToSelectClasses("Skeletal Walker", 2)
addToSelectClasses("Skeletal Shambler", 1)
addToSelectClasses("Frigid Ghoul", 2)
addToSelectClasses("Shadow Walker", 3)
addToSelectClasses("Shadow Lurker", 1)
addToSelectClasses("Frigid Revenant", 2)
addToSelectClasses("Bloated Zombie", 3)
addToSelectClasses("Fast Zombie", 7)
addToSelectClasses("Slingshot Zombie", 3)
addToSelectClasses("Poison Zombie", 3)
addToSelectClasses("Wild Poison Zombie", 2)
addToSelectClasses("Zombine", 5)
addToSelectClasses("Charger", 3)

HANDLER.RandomSecondaryAttack = {
	Ghoul = {MinTime = 5, MaxTime = 7},
	["Elder Ghoul"] = {MinTime = 5, MaxTime = 7},
	["Noxious Ghoul"] = {MinTime = 5, MaxTime = 7},
	["Frigid Ghoul"] = {MinTime = 5, MaxTime = 7},
	["Frigid Revenant"] = {MinTime = 5, MaxTime = 7},
	["Devourer"] = {MinTime = 5, MaxTime = 7},
	Charger = {MinTime = 4, MaxTime = 5, SeeTarget = true},
	["Deadly Charger"] = {MinTime = 4, MaxTime = 5, SeeTarget = true}, --zs improved
	["Poison Zombie"] = {MinTime = 5, MaxTime = 7, SeeTarget = true, Range = 100}, -- Slows them too much
	["Wild Poison Zombie"] = {MinTime = 5, MaxTime = 7, SeeTarget = true, Range = 100}, -- Slows them too much
	["Devourer"] = {MinTime = 1, MaxTime = 1, SeeTarget = true},
	["Howler"] = {MinTime = 4, MaxTime = 12},
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

HANDLER.StatusCreateMoves = {
	["disorientation"] = function(self, pl, cmd)
		local curtime = CurTime()
		local frametime = FrameTime()
		local power = self and (self.GetPower and self:GetPower() * 2) or 80
		power = power * 4

		local ang = cmd:GetViewAngles()
		ang.pitch = math.Clamp(ang.pitch + math.sin(curtime) * 40 * frametime * power, -89, 89)
		ang.yaw = math.NormalizeAngle(ang.yaw + math.cos(curtime + (self and self.Seed or 99)) * 50 * frametime * power)

		cmd:SetViewAngles(ang)
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

	if bot:IsFrozen() then return end

	if not bot:Alive() then
		-- Get back into the game.
		cmd:SetButtons(math.random(1,10) == 1 and IN_RELOAD or IN_ATTACK2) --NEAREST
		return
	end

	local mem = bot.D3bot_Mem

	bot:D3bot_UpdatePathProgress()
	D3bot.Basics.SuicideOrRetarget(bot)

	local trynest = false
	local nestNode

	local fleshcreeper = bot:GetZombieClassTable().Name == "Flesh Creeper"

	if fleshcreeper then 
		local cannest,node,pos = D3bot.Basics.FindNestPoint(bot)
		if cannest then
			nestNode = node
			trynest = true
			bot:D3bot_SetNodeTgtOrNil(node)
			--bot:D3bot_SetPosTgtOrNil(pos)
		else
			--if mem.PosTgtOrNil then 
			--	mem.PosTgtOrNil = nil
			--end
			if mem.NodeTgtOrNil then 
				mem.NodeTgtOrNil = nil
			end
		end
	end
	
	local result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.PounceAuto(bot, false, fleshcreeper and mem.NodeOrNil ~= nestNode)
	if fleshcreeper then
		if (mem.LastPounceTime or 0) + 5 > CurTime() then
			result = false
		end
	end
	if result and fleshcreeper and actions.Reload and IsValid(bot:GetActiveWeapon()) then bot:GetActiveWeapon():Reload() mem.LastPounceTime = CurTime() end --WHAT THE FUCK,STUPID HACK
	if not result then
		result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
		if not result then
			return
		end
	end

	forwardSpeed,sideSpeed = D3bot.Basics.AirStrafe(bot,forwardSpeed,sideSpeed)

	-- If facesHindrance is true, let the bot search for nearby barricade objects.
	-- But only if the bot didn't do damage for some time.
	if facesHindrance then
		if CurTime() - (bot.D3bot_LastDamage or 0) > 2 then
			local entity, entityPos = bot:D3bot_FindBarricadeEntity(1) -- One random line trace per frame.
			if entity and entityPos then
				mem.BarricadeAttackEntity, mem.BarricadeAttackPos = entity, entityPos
			end
		end

		local entity, entityPos = bot:D3bot_FindDoor(3)
		if entity and entityPos then
			mem.DoorPos = entityPos
			mem.Door = entity
		else
			mem.Door = nil
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
				mem.ThrowingPoison = CurTime() + 2
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

	if (trynest and mem.NodeOrNil == nestNode) then 
		actions.Attack = false 
		actions.Attack2 = true 
		actions.Jump = false 
		majorStuck = false 
	end

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

	if bot:GetLegDamage() >= 0.5 then
		actions.Jump = false
	end

	local buttons
	if actions then
		buttons = bit.bor(actions.MoveForward and IN_FORWARD or 0, actions.MoveBackward and IN_BACK or 0, actions.MoveLeft and IN_MOVELEFT or 0, actions.MoveRight and IN_MOVERIGHT or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0, actions.Reload and IN_RELOAD or 0)
	end

	if majorStuck and GAMEMODE:GetWaveActive() and not bot:GetZombieClassTable().Boss then bot:Kill() end

	if aimAngle then bot:SetEyeAngles(aimAngle)	cmd:SetViewAngles(aimAngle) end
	if forwardSpeed then cmd:SetForwardMove(forwardSpeed) end
	if sideSpeed then cmd:SetSideMove(sideSpeed) end
	if upSpeed then cmd:SetUpMove(upSpeed) end
	cmd:SetButtons(buttons)


	local createMove = HANDLER.CreateMoves[GAMEMODE.ZombieClasses[bot:GetZombieClass()].Name]
	--uncomment to make bots stop cheating
	--if createMove then createMove(bot, cmd) end

	for name, func in pairs(HANDLER.StatusCreateMoves) do
		if (IsValid(bot:GetStatus(name)) or (name == "disorientation" and bot._NextLeadPipeEffect and bot._NextLeadPipeEffect > CurTime())) then
			func(bot:GetStatus(name), bot, cmd)
		end
	end
	bot:SetEyeAngles(cmd:GetViewAngles())
end

local targetPriorities = {
	["player"] = 500,
	["prop_obj_sigil"] = 100,
}

function HANDLER.TargetScore(bot,target,botPos,maxDist,ignoreDist)
	if (not IsValid(target)) then return -math.huge end
	botPos = botPos or bot:GetPos()
	local dist = ignoreDist and 1 or (isvector(botPos) and botPos:DistToSqr(target:GetPos()) or bot:GetPos():DistToSqr(target:GetPos()))
	if not ignoreDist and (dist > math.pow(maxDist or 500,2)) then
		return -math.huge
	end
	local score = -dist * 0.1
		+ (targetPriorities[target:GetClass()] or 0)
	for _,otherbot in ipairs(player.GetAll())do 
		if otherbot ~= bot and otherbot.D3bot_Mem then
			local mem = otherbot.D3bot_Mem
			if IsValid(mem.TgtOrNil) and mem.TgtOrNil == target then
				score = score - 300
			end
		end
	end

	local mem = bot.D3bot_Mem

	if mem.TargetedAmounts and mem.TargetedAmounts[target] then
		score = score - mem.TargetedAmounts[target] * 150
	end

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
		bot:D3bot_UpdateAngsOffshoot((mem.ThrowingPoison and mem.ThrowingPoison > CurTime()) and 0 or HANDLER.AngOffshoot)
	end

	if mem.nextUpdateCadeAttackStrat and mem.nextUpdateCadeAttackStrat < CurTime() or not mem.nextUpdateCadeAttackStrat then
		mem.nextUpdateCadeAttackStrat = CurTime() + math.Rand(4,7)
		mem.CadeAttackStrat = math.min(1,math.random(0,3))
		--print("strat: ",mem.CadeAttackStrat)
	end

	if mem.nextUpdateAttackStrat and mem.nextUpdateAttackStrat < CurTime() or not mem.nextUpdateAttackStrat then
		mem.AttackStrat = math.min(3,math.random(0,3))
		mem.nextUpdateAttackStrat = (mem.AttackStrat == 0) and (CurTime() + 2 + math.Rand(1,4)) or (CurTime() + 4 + math.Rand(4,7))
		--print("strat: ",mem.AttackStrat)
	end

	if mem.nextUpdateAttackStrat3 and mem.nextUpdateAttackStrat3 < CurTime() or not mem.nextUpdateAttackStrat3 then
		mem.nextUpdateAttackStrat3 = CurTime() + math.Rand(2,6)
		mem.AttackStrat3Dir = (mem.AttackStrat3Dir or 1) * - 1
	end

	if not mem.BHOPModeEnableTimer or (mem.BHOPModeEnableTimer < CurTime()) then
		mem.BHOPModeEnableTimer = CurTime() + math.Rand(7,16)
		mem.BHOPModeEnable = CurTime() + math.Rand(4,6)
	end

	if mem.BHOPModeEnable and mem.BHOPModeEnable > CurTime() then
		if not bot:OnGround() then
			local vel2d = bot:GetVelocity():Length2DSqr()
			if vel2d <= math.pow(bot:GetWalkSpeed() * 0.9,2) then
				mem.BHOPModeEnable = mem.BHOPModeEnable - FrameTime() * 2
			end
		end
	end

	if mem.TargetedAmounts and (not mem.ResetTargetedAmounts or mem.ResetTargetedAmounts < CurTime()) then
		mem.TargetedAmounts = {}
		mem.ResetTargetedAmounts = CurTime() + math.Rand(50,250)
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
	if IsValid(mem.TgtOrNil) then
		if mem.TgtOrNil ~= attacker and HANDLER.CanBeTgt(bot,attacker) and (HANDLER.TargetScore(bot,mem.TgtOrNil,bot:GetPos(),5000,true) < HANDLER.TargetScore(bot,attacker,bot:GetPos(),5000,true)) then
			if ((mem.LastChangeTgt or 0)) + 10 > CurTime() then return end
			mem.TgtOrNil = attacker
			mem.LastChangeTgt = CurTime()
		end
		--bot:Say("Ouch! Fuck you "..attacker:GetName().."! I'm gonna kill you!")
	end
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

local potTargetEntClasses = {"prop_*turret*", "prop_arsenalcrate", "prop_resupplybox", "prop_remantler", "prop_manhack*", "prop_obj_sigil", "prop_zapper*"}
local potTargetEntClasses_Obj = {"prop_*turret*", "prop_zapper*"}

local potEntTargets2 = {}

---Returns whether a target is valid.
---@param bot GPlayer
---@param target GPlayer|GEntity|any
function HANDLER.CanBeTgt(bot, target, potEntTargets)
	potEntTargets = potEntTargets or potEntTargets2
	if not target or not IsValid(target) then return false end
	if target:IsPlayer() and target ~= bot and (target:Team() ~= TEAM_UNDEAD or GAMEMODE:GetEndRound()) and target:GetObserverMode() == OBS_MODE_NONE and not target:IsFlagSet(FL_NOTARGET) and target:Alive() and not target:GetStatus("d3botredeem") then return true end
	if target:GetClass() == "prop_obj_sigil" and (LASTHUMAN or target:GetSigilCorrupted()) then return false end -- Special case to ignore useless sigils.
	if potEntTargets and potEntTargets[target] then return true end

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
	local players = D3bot.RemoveObsDeadTgts(GAMEMODE:GetEndRound() and player.GetAll() or team.GetPlayers(TEAM_HUMAN))
	if #players == 0 and TEAM_UNDEAD then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
		players = D3bot.From(players):Where(function(k, v) return (v:Team() ~= TEAM_UNDEAD  or GAMEMODE:GetEndRound()) end).R
	end
	if #players == 0 then
		players = D3bot.RemoveObsDeadTgts(player.GetAll())
	end
	table.Empty(potEntTargets2)
	local potEntTargets = D3bot.GetEntsOfClss(GAMEMODE.ObjectiveMap and potTargetEntClasses_Obj or potTargetEntClasses, function(class)
		local _ents = {}
		local c = 0
		for _,v in ipairs(ents.FindByClass(class)) do 
			c = c + 1
			_ents[c] = v
			potEntTargets2[v] = true
		end
		return _ents
	end)

	local potTargets = table.Add(players, potEntTargets)
	table.sort(potTargets, function(a, b) return HANDLER.TargetScore(bot,a,_,65536) > HANDLER.TargetScore(bot,b,_,65536) end)
	
	local tgt
	for i,v in pairs(potTargets) do
		if HANDLER.CanBeTgt(bot, v, potEntTargets2) then
			tgt = v
			break
		end
	end

	if not tgt then return end
	mem.TargetedAmounts[tgt] = (mem.TargetedAmounts[tgt] or 0) + 1
	bot:D3bot_SetTgtOrNil(tgt, false, nil)
end
