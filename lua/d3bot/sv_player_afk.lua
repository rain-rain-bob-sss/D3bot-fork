if not D3bot.AFKEnabled then 
    util.AddNetworkString("D3bot_unafk")
    net.Receive("D3bot_unafk",function() end)
    return
end

local function Control(ply)
    if ply.D3bot_Mem then return end
    ply:D3bot_InitializeOrReset("afk")
    ply.D3bot_Mem.Type = "afk"
    local message = translate.ClientGet(ply, "D3bot_afk")
    ply:ChatPrint(message)
    ply:PrintMessage(HUD_PRINTCENTER, message)
end

local function UnControl(ply)
    if not ply.D3bot_Mem then return end
    if ply.D3bot_Mem.Type ~= "afk" then return end
    ply:D3bot_Deinitialize()
    local message = translate.ClientGet(ply, "D3bot_unafk")
    ply:ChatPrint(message)
    ply:PrintMessage(HUD_PRINTCENTER, message)
    local ang = ply:EyeAngles() --no roll
    ang.r = 0
    ply:SetEyeAngles(ang)
end

util.AddNetworkString("D3bot_unafk")
net.Receive("D3bot_unafk",function(_,ply)
    ply.D3bot_AFK = CurTime() + 180
end)

hook.Add("PlayerPostThink","D3bot_AFK",function(ply)
    if ply:IsBot() then return end
    if ply:GetMoveType() == MOVETYPE_NOCLIP then return end
    if ply:Team() == TEAM_HUMAN then ply.D3bot_AFK = CurTime() + 60 UnControl(ply) return end
    if GAMEMODE:GetWave() <= 0 then return end
    if not ply.D3bot_AFK then ply.D3bot_AFK = CurTime() + 30 end
    if ply.D3bot_AFK < CurTime() then 
        Control(ply)
    else
        UnControl(ply)
    end
end)
