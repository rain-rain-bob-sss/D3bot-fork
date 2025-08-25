local function UnAfk()
    net.Start("D3bot_unafk")
    net.SendToServer()
end

hook.Add("PlayerBindPress","D3bot_unafk",UnAfk)
hook.Add("InputMouseApply","D3bot_unafk",function(_,x,y,_)
    if (math.abs(x) + math.abs(y)) < 0.5 then return end
    UnAfk()
end)