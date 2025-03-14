-- -- Map Bounds Visualizer
-- -- Requires NikNaks to get map boundary data
-- if not CLIENT then return end

-- -- ConVars for customization
-- local enabled = CreateClientConVar("mapbounds_enabled", "0", true, false, "Enable map boundary visualization")
-- local color_r = CreateClientConVar("mapbounds_color_r", "0", true, false, "Red component of boundary color")
-- local color_g = CreateClientConVar("mapbounds_color_g", "255", true, false, "Green component of boundary color")
-- local color_b = CreateClientConVar("mapbounds_color_b", "0", true, false, "Blue component of boundary color")
-- local color_a = CreateClientConVar("mapbounds_color_a", "100", true, false, "Alpha component of boundary color")

-- -- Key variables
-- local mapBounds = {}
-- local initSuccess = false

-- -- Diagnostic check - this seems to help initialize NikNaks properly
-- local function ensureNikNaksLoaded()
--     if not NikNaks then
--         print("[MapBounds] NikNaks not found!")
--         return false
--     end
    
--     print("[MapBounds] NikNaks version: " .. tostring(NikNaks.VERSION))
    
--     if not NikNaks.CurrentMap then
--         print("[MapBounds] Attempting to load CurrentMap manually...")
--         -- Try to force-load the current map
--         if NikNaks.Map then
--             NikNaks.CurrentMap = NikNaks.Map()
--         end
--     end
    
--     if NikNaks.CurrentMap then
--         print("[MapBounds] CurrentMap loaded successfully")
--         return true
--     else
--         print("[MapBounds] Failed to get CurrentMap")
--         return false
--     end
-- end

-- -- Initialize the map bounds
-- local function InitBounds()
--     if not ensureNikNaksLoaded() then
--         return false
--     end
    
--     -- Get the map bounds from NikNaks
--     local min, max
    
--     -- Try WorldMin/Max first
--     if NikNaks.CurrentMap.WorldMin and NikNaks.CurrentMap.WorldMax then
--         min = NikNaks.CurrentMap:WorldMin()
--         max = NikNaks.CurrentMap:WorldMax()
--     end
    
--     -- If that failed, try GetBrushBounds
--     if (not min or not max) and NikNaks.CurrentMap.GetBrushBounds then
--         min, max = NikNaks.CurrentMap:GetBrushBounds()
--     end
    
--     -- Check if we have valid bounds
--     if not min or not max then
--         print("[MapBounds] Failed to get map boundaries")
--         return false
--     end
    
--     -- Store the bounds
--     mapBounds.min = min
--     mapBounds.max = max
    
--     print("[MapBounds] Map boundaries loaded:")
--     print("  Min: " .. tostring(min))
--     print("  Max: " .. tostring(max))
--     return true
-- end

-- -- Draw the bounding box
-- hook.Add("PostDrawTranslucentRenderables", "MapBoundsVisualization", function()
--     if not enabled:GetBool() then return end
    
--     -- Try to initialize bounds if needed
--     if not initSuccess and (not mapBounds.min or not mapBounds.max) then
--         initSuccess = InitBounds()
--         if not initSuccess then return end
--     end
    
--     -- Get color from ConVars
--     local color = Color(
--         color_r:GetInt(),
--         color_g:GetInt(),
--         color_b:GetInt(),
--         color_a:GetInt()
--     )
    
--     -- Draw wireframe box
--     render.SetColorMaterial()
--     render.DrawWireframeBox(
--         Vector(0, 0, 0),
--         Angle(0, 0, 0),
--         mapBounds.min,
--         mapBounds.max,
--         color,
--         false
--     )
    
--     -- Draw a very transparent box for easier visualization
--     local fillColor = Color(color.r, color.g, color.b, math.min(20, color.a))
--     render.DrawBox(
--         Vector(0, 0, 0),
--         Angle(0, 0, 0),
--         mapBounds.min, 
--         mapBounds.max,
--         fillColor,
--         false
--     )
-- end)

-- -- Add a menu to control the visualization
-- hook.Add("PopulateToolMenu", "MapBoundsMenu", function()
--     spawnmenu.AddToolMenuOption("Utilities", "User", "MapBounds", "Map Boundaries", "", "", function(panel)
--         panel:ClearControls()
        
--         panel:CheckBox("Enable Map Boundary Visualization", "mapbounds_enabled")
        
--         local colorMixer = vgui.Create("DColorMixer")
--         colorMixer:SetPalette(true)
--         colorMixer:SetAlphaBar(true)
--         colorMixer:SetWangs(true)
--         colorMixer:SetColor(Color(
--             color_r:GetInt(),
--             color_g:GetInt(),
--             color_b:GetInt(),
--             color_a:GetInt()
--         ))
--         colorMixer.ValueChanged = function(_, col)
--             RunConsoleCommand("mapbounds_color_r", tostring(col.r))
--             RunConsoleCommand("mapbounds_color_g", tostring(col.g))
--             RunConsoleCommand("mapbounds_color_b", tostring(col.b))
--             RunConsoleCommand("mapbounds_color_a", tostring(col.a))
--         end
--         panel:AddItem(colorMixer)
        
--         if mapBounds.min and mapBounds.max then
--             panel:Help("Map Bounds:")
--             panel:Help("Min: " .. tostring(mapBounds.min))
--             panel:Help("Max: " .. tostring(mapBounds.max))
            
--             local size = mapBounds.max - mapBounds.min
--             panel:Help("Size: " .. tostring(size))
--             panel:Help("Volume: " .. tostring(math.Round(size.x * size.y * size.z)) .. " units³")
--         else
--             panel:Help("Map bounds not loaded yet")
--             panel:Button("Manual Reload", "mapbounds_reload")
--         end
--     end)
-- end)

-- -- Console command to reload bounds
-- concommand.Add("mapbounds_reload", function()
--     initSuccess = InitBounds()
-- end)

-- -- Use multiple timers at different intervals to ensure initialization
-- timer.Simple(5, function()
--     initSuccess = InitBounds()
-- end)

-- timer.Simple(10, function()
--     if not initSuccess then
--         initSuccess = InitBounds()
--     end
-- end)

-- timer.Simple(15, function()
--     if not initSuccess then
--         initSuccess = InitBounds()
--     end
-- end)

-- -- Handle map changes
-- hook.Add("InitPostEntity", "MapBoundsInitAfterMapChange", function()
--     timer.Simple(5, function()
--         initSuccess = InitBounds()
--     end)
-- end)

-- print("[MapBounds] Map boundary visualization loaded")