if not CLIENT then return end

-- ConVars
local CONVARS = {
    SHOW_3DSKY_WARNING = CreateClientConVar("rtx_show_3dsky_warning", "1", true, false, "Show warning when enabling r_3dsky")
}

hook.Add( "PopulateToolMenu", "RTXOptionsClient", function()
    spawnmenu.AddToolMenuOption( "Utilities", "RTX Remix", "RTX_Client", "#Base Options", "", "", function( panel )
        panel:ClearControls()

        panel:CheckBox( "Pseudoplayer Enabled", "rtx_pseudoplayer" )
        panel:ControlHelp( "Pseudoplayer allows you to see your own playermodel, this when marked as a 'Playermodel Texture' in remix allows you to see your own shadow and reflection." )
        panel:CheckBox( "Pseudoweapon Enabled", "rtx_pseudoweapon" )
        panel:ControlHelp( "Similar to above, but for the weapon you're holding." )

        panel:AddControl("Header", {Description = "Render Options:"})
        panel:CheckBox("Show Render Debug HUD", "rtx_render_debug")
        panel:CheckBox("2D Skybox", "rtx_sky2d_enable")
        panel:CheckBox("Entity Anti-Culling", "rtx_rearview_enabled")
        panel:NumSlider("Distance (units)", "rtx_rearview_off_forward", 100, 5000, 0)
        panel:Help("This can severely impact performance")
    end )
end )

local function Show3DSkyWarning()
    -- Don't show if user has disabled warnings
    if not CONVARS.SHOW_3DSKY_WARNING:GetBool() then return end
    
    -- Create the warning panel
    local frame = vgui.Create("DFrame")
    frame:SetTitle("RTX Remix Fixes 2")
    frame:SetSize(400, 200)
    frame:Center()
    frame:MakePopup()
    
    local warningText = vgui.Create("DLabel", frame)
    warningText:SetPos(20, 40)
    warningText:SetSize(360, 80)
    warningText:SetText("You have enabled r_3dsky which may cause rendering issues with RTX Remix due how the engine culls the skybox. It's recommended to keep r_3dsky disabled for best results.")
    warningText:SetWrap(true)
    
    local dontShowAgain = vgui.Create("DCheckBoxLabel", frame)
    dontShowAgain:SetPos(20, 130)
    dontShowAgain:SetText("Don't show this warning again")
    dontShowAgain:SetValue(false)
    dontShowAgain.OnChange = function(self, val)
        if val then
            RunConsoleCommand("rtx_show_3dsky_warning", "0")
        else
            RunConsoleCommand("rtx_show_3dsky_warning", "1")
        end
    end
    
    local okButton = vgui.Create("DButton", frame)
    okButton:SetText("OK")
    okButton:SetPos(150, 160)
    okButton:SetSize(100, 25)
    okButton.DoClick = function()
        frame:Close()
    end
end

cvars.AddChangeCallback("r_3dsky", function(_, _, newValue)
    if newValue == "1" then
        Show3DSkyWarning()
    end
end)