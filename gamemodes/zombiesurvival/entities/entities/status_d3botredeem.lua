AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "status__base"

ENT.Ephemeral = true

AccessorFuncDT(ENT, "Duration", "Float", 0)
AccessorFuncDT(ENT, "StartTime", "Float", 4)

function ENT:PlayerSet(ply)
	self:SetStartTime(CurTime())
	if SERVER then 
		ply.OldFriction = ply:GetFriction()
		ply:SetFriction(1.5)
	end

	ply:CollisionRulesChanged()
end

if SERVER then
	function ENT:SetDie(fTime)
		if fTime == 0 or not fTime then
			self.DieTime = 0
		elseif fTime == -1 then
			self.DieTime = 999999999
		else
			self.DieTime = CurTime() + fTime
			self:SetDuration(fTime)
		end
	end

	function ENT:Think()
		self.BaseClass.Think(self)
		local pl = self:GetOwner()
		if pl:IsValidLivingHuman() then
			pl:RemoveStatus("confusion", false, true)
			pl:RemoveStatus("knockdown", false, true)
		end
	end
end

function ENT:Initialize()
	self.BaseClass.Initialize(self)

	hook.Add("Move", self, self.Move)
	if CLIENT then
		if self:GetOwner() == MySelf then
			util.WhiteOut(0.5)

			hook.Add("RenderScreenspaceEffects", self, self.RenderScreenspaceEffects)
			hook.Add("HUDPaint", self, self.HUDPaint)

			MySelf:EmitSound("ambient/energy/weld1.wav",100,155,1,CHAN_STATIC)
			MySelf:EmitSound("beams/beamstart5.wav",100,155,1,CHAN_STATIC)
			MySelf:EmitSound("weapons/physcannon/physcannon_charge.wav",100,75,1,CHAN_STATIC)

			util.ScreenShake(MySelf:GetPos(), 10, 0.5, 1.5, 800)
			util.ScreenShake(MySelf:GetPos(), 10, 0.5, 1.5, 800)
			util.ScreenShake(MySelf:GetPos(), 10, 0.5, 1.5, 800)
		end

		hook.Add("PrePlayerDraw", self, self.PrePlayerDraw)
	end

	hook.Add("PlayerFootstep", self, self.PlayerFootstep)

	if SERVER then
		hook.Add("EntityTakeDamage", self, self.EntityTakeDamage)
	end
end

function ENT:OnRemove()
	self.BaseClass.OnRemove(self)

	local owner = self:GetOwner()
	if IsValid(owner) then 
		if SERVER then
			owner:SetFriction(owner.OldFriction)
		elseif owner == MySelf then
			MySelf:EmitSound("weapons/physgun_off.wav",100,155,0.5,CHAN_STATIC)
			util.WhiteOut(0.5)
		end
	end
end

function ENT:Move(pl, move)
	if pl ~= self:GetOwner() then return end

	move:SetMaxSpeed(self:GetSpeed())
	move:SetMaxClientSpeed(move:GetMaxSpeed())
end

function ENT:PlayerFootstep(ply)
	if ply ~= self:GetOwner() then return end
	return true
end

function ENT:EntityTakeDamage(ent, dmginfo)
	local owner = self:GetOwner()
	if ent ~= owner then 
		local attacker = dmginfo:GetAttacker()
		if attacker == owner then
			dmginfo:ScaleDamage(2)
		end
		return
	end
	local attacker = dmginfo:GetAttacker()
	if attacker:IsWorld() or (IsValid(attacker) and attacker:IsPlayer()) or (dmginfo:IsDamageType(DMG_CRUSH)) then
		if attacker:IsPlayer() then
			--attacker:AddLegDamageExt(100, ent, self, SLOWTYPE_COLD)
			--attacker:AddArmDamage(50)
		end
		return true
	end
end

function ENT:GetSpeed()
	return 1000
end

if CLIENT then
	local tab = {
		["$pp_colour_addr"] = 0,
		["$pp_colour_addg"] = 0,
		["$pp_colour_addb"] = 0,
		["$pp_colour_brightness"] = 0,
		["$pp_colour_contrast"] = 1,
		["$pp_colour_colour"] = 1,
		["$pp_colour_mulr"] = 0,
		["$pp_colour_mulg"] = 0,
		["$pp_colour_mulb"] = 0
	}
	function ENT:RenderScreenspaceEffects()
		local f = math.Clamp(self:GetStartTime() + self:GetDuration() - CurTime(),0,1)
		local p = math.abs(math.sin((CurTime() - self:GetStartTime()) * 2.5)) * f
		tab["$pp_colour_addr"] = f * 0.1 + p * 0.1
		tab["$pp_colour_addg"] = f * 0.1 + p * 0.1
		tab["$pp_colour_brightness"] = math.ease.InQuad(f) * 0.02
		DrawColorModify( tab )
	end

	local texGradDown = surface.GetTextureID("vgui/gradient_down")
	function ENT:HUDPaint()
		local scale = BetterScreenScale()
		local w,h = 180 * scale, 20 * scale
		local x, y = ScrW() * 0.5 - w * 0.5, ScrH() * 0.6 - h * 0.5
		local f = math.Clamp(self:GetStartTime() + self:GetDuration() - CurTime(),0,self:GetDuration()) / self:GetDuration()
		surface.SetDrawColor(5, 5, 5, 180)
		surface.DrawRect(x, y, w, h)

		surface.SetDrawColor(255, 255, 0, 180)

		surface.SetTexture(texGradDown)
		surface.DrawTexturedRect(x, y, f * w, h)

		surface.SetDrawColor(255, 255, 0, 180)
		surface.DrawOutlinedRect(x, y, w, h)
	end

	function ENT:PrePlayerDraw(ply)
		if ply ~= self:GetOwner() then return end
		return true
	end
end

local function c(a,b)
	if a:IsPlayer() then
		local status = a:GetStatus("d3botredeem")
		if IsValid(status) then
			if b:IsPlayer() or b:IsBarricadeProp() or (b:GetClass() == "prop_door_rotating" and not b:GetNWBool("door_locked")) then
				return true
			end
		end
	end
end

hook.Add("ShouldCollide", "status_d3bot_redeem", function(a,b)
	if (c(a,b)) or (c(b,a)) then return false end
end)

if SERVER then
	hook.Add("Think","status_d3bot_redeem_fix_locked_door", function()
		if engine.TickCount() % 2 ~= 0 then return end
		for _,door in ipairs(ents.FindByClass("prop_door_rotating")) do
			local bool = b:GetNWBool("door_locked")
			door:SetNWBool("door_locked",door:IsDoorLocked())
			door:SetCustomCollisionCheck(true)
			if bool ~= door:IsDoorLocked() then
				door:CollisionRulesChanged()
			end
		end
	end)
end