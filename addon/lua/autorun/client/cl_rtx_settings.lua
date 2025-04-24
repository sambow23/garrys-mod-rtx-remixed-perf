if not CLIENT then return end

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
            RunConsoleCommand("rtx_fd_enable_current_map")
        end
        
        local disableButton = vgui.Create("DButton", buttonsPanel)
        disableButton:SetText("Disable")
        disableButton.DoClick = function()
            RunConsoleCommand("rtx_fd_disable_current_map")
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
        
        panel:ControlHelp("Enables/Disables 'mat_forcedynamic' for the current map and remembers the setting for future loads of this map. This helps fix map rendering issues.")

    end )
end )