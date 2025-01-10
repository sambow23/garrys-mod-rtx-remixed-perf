if not CLIENT then return end
hook.Add("CalcView", "RTXNoVis", function()
    
end)


-- Debug command to print entity info
concommand.Add("debug_do_not_cull", function()

    DisableCulling()
end)