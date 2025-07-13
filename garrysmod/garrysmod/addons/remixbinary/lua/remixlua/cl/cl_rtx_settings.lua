if not CLIENT then return end

-- ConVars
local CONVARS = {
    SHOW_3DSKY_WARNING = CreateClientConVar("rtx_show_3dsky_warning", "1", true, false, "Show warning when enabling r_3dsky")
}

hook.Add( "PopulateToolMenu", "RTXOptionsClient", function()
    spawnmenu.AddToolMenuOption( "Utilities", "User", "RTX_Client", "#RTX", "", "", function( panel )
        panel:ClearControls()

        panel:CheckBox( "Pseudoplayer Enabled", "rtx_pseudoplayer" )
        panel:ControlHelp( "Pseudoplayer allows you to see your own playermodel, this when marked as a 'Playermodel Texture' in remix allows you to see your own shadow and reflection." )
        panel:CheckBox( "Pseudoweapon Enabled", "rtx_pseudoweapon" )
        panel:ControlHelp( "Similar to above, but for the weapon you're holding." )

        panel:CheckBox( "Disable Vertex Lighting.", "rtx_disablevertexlighting" )
        panel:ControlHelp( "Disables vertex lighting on models and props, as these look incorrect with Remix" )
        panel:ControlHelp( "Breaks some lightupdaters when enabled." )

        -- Force Dynamic Buttons
        panel:Help( "Map Render Fixes" )

        -- Create a panel for the buttons
        local buttonsPanel = vgui.Create("DPanel", panel)
        buttonsPanel:SetTall(25)
        buttonsPanel:SetPaintBackground(false)
        panel:AddItem(buttonsPanel)
        
        -- Set margin and spacing
        local margin = 10  -- Margin from panel edges
        local spacing = 5  -- Space between buttons
        
        -- Create buttons without setting position/size yet
        local enableButton = vgui.Create("DButton", buttonsPanel)
        enableButton:SetText("Enable")
        enableButton.DoClick = function()
            RunConsoleCommand("rtx_mf_enable_current_map")
        end
        
        local disableButton = vgui.Create("DButton", buttonsPanel)
        disableButton:SetText("Disable")
        disableButton.DoClick = function()
            RunConsoleCommand("rtx_mf_disable_current_map")
        end
        
        -- Size and position buttons when the panel is laid out
        buttonsPanel.PerformLayout = function(self)
            local panelWidth = self:GetWide()
            local buttonWidth = (panelWidth - (2 * margin) - spacing) / 2
            
            enableButton:SetSize(buttonWidth, 25)
            disableButton:SetSize(buttonWidth, 25)
            
            enableButton:SetPos(margin, 0)
            disableButton:SetPos(margin + buttonWidth + spacing, 0)
        end
        
        panel:ControlHelp("Enables/Disables Map Fixes for the current map and remembers the setting for future loads of this map. This helps fix map rendering issues.")

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