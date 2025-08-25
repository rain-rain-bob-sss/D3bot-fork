local meta = FindMetaTable("Player")
meta.OldGetInfo_D3Bot = meta.OldGetInfo_D3Bot or meta.GetInfo

function meta:GetInfo(cvar,...)
    if self.D3bot_Mem then
        if cvar == "zs_nobosspick" and self:IsBot() then
            return "0"
        elseif cvar == "zs_bossclass" then
            if (self.RefreshBossClass or 0) < CurTime() then
                local bossclasses = {}
                for _, classtable in pairs(GAMEMODE.ZombieClasses) do
                    if classtable.Boss and not classtable.NoBotBoss then
                        table.insert(bossclasses, classtable.Name)
                    end
                end
                self.BotBossClass = bossclasses[math.random(1,#bossclasses)]
                self.RefreshBossClass = CurTime() + 3
            end
            return self.BotBossClass or "[RANDOM]"
        elseif (cvar == "cl_weaponcolor" or cvar == "cl_playercolor") and self:IsBot() then
            local col = cvar == "cl_weaponcolor" and self.D3bot_Mem.WeaponColor or self.D3bot_Mem.PlayerColor
            return table.concat(col or {0.24,0.34,0.41}," ")
        end
    end
    return self:OldGetInfo_D3Bot(cvar,...)
end