AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "status__base"

ENT.Ephemeral = true

ENT.NextHeal = 0
ENT.NextBreakDoors = 0

AccessorFuncDT(ENT, "Duration", "Float", 0)
AccessorFuncDT(ENT, "StartTime", "Float", 4)

function ENT:PlayerSet(ply)
	self:SetStartTime(CurTime())
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
			if self.NextHeal < CurTime() then
				pl:SetHealth(math.min(math.max(pl:GetMaxHealth(),pl:Health()),pl:Health() + 25))
				self.NextHeal = CurTime() + 1
			end

			if self.NextBreakDoors < CurTime() then
				for _,ent in ipairs(util.BlastAlloc(self, pl, pl:GetPos(), 24)) do
					if ent:GetClass() == "prop_door_rotating" then
						ent:TakeDamage(200,pl,self)
					end
				end
				self.NextBreakDoors = CurTime() + 0.1
			end
		end
	end
end

function ENT:Initialize()
	self.BaseClass.Initialize(self)

	hook.Add("Move", self, self.Move)
	if CLIENT then
		if self:GetOwner() == MySelf then
			hook.Add("RenderScreenspaceEffects", self, self.RenderScreenspaceEffects)
			hook.Add("HUDPaint", self, self.HUDPaint)
		end
	end

	if SERVER then
		hook.Add("EntityTakeDamage", self, self.EntityTakeDamage)
	end
end

function ENT:EntityTakeDamage(ent, dmginfo)
	local owner = self:GetOwner()
	if ent ~= owner then 
		local attacker = dmginfo:GetAttacker()
		if attacker == owner then
			dmginfo:ScaleDamage(2)
		end
	end
end

function ENT:Move(pl, move)
	if pl ~= self:GetOwner() then return end

	move:SetMaxSpeed(move:GetMaxSpeed() * 1.35)
	move:SetMaxClientSpeed(move:GetMaxSpeed())
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
		tab["$pp_colour_addg"] = f * 0.05 + p * 0.05
		tab["$pp_colour_brightness"] = math.ease.InQuad(f) * 0.015
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

		surface.SetDrawColor(0, 255, 0, 180)

		surface.SetTexture(texGradDown)
		surface.DrawTexturedRect(x, y, f * w, h)

		surface.SetDrawColor(0, 255, 0, 180)
		surface.DrawOutlinedRect(x, y, w, h)
	end
end