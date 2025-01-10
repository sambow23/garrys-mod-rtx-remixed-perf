if not CLIENT then return end

hook.Add( "PopulateToolMenu", "RTXOptionsClient", function()
    spawnmenu.AddToolMenuOption( "Utilities", "User", "RTX_Client", "#RTX", "", "", function( panel )
        panel:ClearControls()
        
        --panel:ControlHelp( "Thanks for using RTX Remix Fixes! In order to allow me to continue to fix and support this addon while keeping it free, it would be nice if you could PLEASE consider donating to my patreon!" )
        --panel:ControlHelp("https://www.patreon.com/xenthio")

        panel:CheckBox( "Fix Materials on Load.", "rtx_fixmaterials" )
        panel:ControlHelp( "Fixup broken and unsupported materials, this fixes things like blank materials and particles." ) 
        
        panel:CheckBox( "Fix GUI on Load.", "rtx_fixgui" )
        panel:ControlHelp( "Fixup GUI materials to play nicer with RTX Remix." ) 

        --panel:CheckBox( "Pseudoplayer Enabled", "rtx_pseudoplayer" )
        --panel:ControlHelp( "Pseudoplayer allows you to see your own playermodel, this when marked as a 'Playermodel Texture' in remix allows you to see your own shadow and reflection." )
        --panel:CheckBox( "Pseudoweapon Enabled", "rtx_pseudoweapon" )
        --panel:ControlHelp( "Similar to above, but for the weapon you're holding." )

        panel:CheckBox( "Disable Vertex Lighting.", "rtx_disablevertexlighting" )
        panel:ControlHelp( "Disables vertex lighting on models and props, these look incorrect with rtx and aren't needed when lightupdaters are enabled." )

        panel:CheckBox( "Light Updater", "rtx_lightupdater")
        panel:ControlHelp( "Prevent lights from disappearing in remix, works well when 'Supress Light Keeping' in remix settings is on.") 
    end )
end )