-- Dedicated Tool Menu for Remix API Lights runtime controls
-- Loaded automatically by autorun/cl_rtx.lua which includes all files under remixlua/cl/remixapi/

if not CLIENT then return end

hook.Add("PopulateToolMenu", "RemixAPILights", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_Remix_API_Lights", "Remix API Lights", "", "", function(panel)
        panel:ClearControls()

        -- Section: Actions
        panel:Help("Actions")
        panel:Button("Process Map Lights", "rtx_api_map_lights_process")
        panel:Button("Clear All RTX Lights", "rtx_api_map_lights_clear")
        panel:Button("Refresh Existing Lights", "rtx_api_map_lights_refresh")
        panel:CheckBox("Show Visual Handles", "rtx_api_map_lights_visual")

        panel:Help("")

        -- Section: Runtime Multipliers (apply instantly)
        panel:Help("Runtime Multipliers")
        panel:Help("Point Lights")
        panel:NumSlider("Point Brightness Mult", "rtx_api_map_lights_point_brightness_mult", 0, 10, 2)
        panel:NumSlider("Point Radius Mult", "rtx_api_map_lights_point_radius_mult", 0, 10, 2)
        local btnPointReset = panel:Button("Reset Point Multipliers", "")
        btnPointReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_point_brightness_mult", "1.0")
            RunConsoleCommand("rtx_api_map_lights_point_radius_mult", "1.0")
        end

        panel:Help("")
        panel:Help("Spot Lights")
        panel:NumSlider("Spot Brightness Mult", "rtx_api_map_lights_spot_brightness_mult", 0, 10, 2)
        panel:NumSlider("Spot Radius Mult", "rtx_api_map_lights_spot_radius_mult", 0, 10, 2)
        local btnSpotReset = panel:Button("Reset Spot Multipliers", "")
        btnSpotReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_spot_brightness_mult", "1.0")
            RunConsoleCommand("rtx_api_map_lights_spot_radius_mult", "1.0")
        end

        panel:Help("")
        panel:Help("Directional (light_environment)")
        panel:NumSlider("Env Brightness Mult", "rtx_api_map_lights_env_brightness_mult", 0, 10, 2)
        panel:NumSlider("Env Angular Mult", "rtx_api_map_lights_env_angular_mult", 0, 5, 2)
        panel:CheckBox("Flip Direction", "rtx_api_map_lights_env_dir_flip")
        panel:NumSlider("Env Max Brightness (0=disable clamp)", "rtx_api_map_lights_env_max_brightness", 0, 100, 0)
        local btnEnvReset = panel:Button("Reset Directional Settings", "")
        btnEnvReset.DoClick = function()
            RunConsoleCommand("rtx_api_map_lights_env_brightness_mult", "1.0")
            RunConsoleCommand("rtx_api_map_lights_env_angular_mult", "1.0")
            RunConsoleCommand("rtx_api_map_lights_env_dir_flip", "0")
            RunConsoleCommand("rtx_api_map_lights_env_max_brightness", "0")
        end

        panel:Help("")

        -- Section: Auto Process
        panel:Help("Auto Process")
        panel:CheckBox("Auto-convert lights on map start", "rtx_api_map_lights_autospawn")
        panel:NumSlider("Auto-process delay (s)", "rtx_api_map_lights_autospawn_delay", 0, 10, 1)

        panel:Help("")

        -- Section: Batch & Creation
        panel:Help("Creation Batching")
        panel:NumSlider("Batch Size", "rtx_api_map_lights_batch_size", 1, 64, 0)
        panel:NumSlider("Batch Delay (s)", "rtx_api_map_lights_batch_delay", 0, 1, 2)
        panel:NumSlider("Creation Interval per Light (s)", "rtx_api_map_lights_creation_delay", 0, 0.25, 3)

        panel:Help("")

        -- Section: Position Jitter
        panel:Help("Position Jitter (dedupe helper)")
        panel:CheckBox("Enable Jitter", "rtx_api_map_lights_position_jitter")
        panel:NumSlider("Jitter Amount", "rtx_api_map_lights_position_jitter_amount", 0, 2, 2)

        panel:Help("")

        -- Section: Debug
        panel:Help("Debug")
        panel:CheckBox("Verbose Debug Logs", "rtx_api_map_lights_debug")
        panel:CheckBox("Draw Debug Directions", "rtx_api_map_lights_debug_vis")
        panel:NumSlider("Spot Dir Basis (0=F,1=-F,2=U,3=-U,4=R,5=-R)", "rtx_api_map_lights_dir_basis", 0, 5, 0)
    end)
end)
