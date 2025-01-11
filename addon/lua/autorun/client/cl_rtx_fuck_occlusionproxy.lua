-- -- Hacky version of the previous crash protection function. Makes engine/occlusionproxy error spam go away and maps render correctly now.
-- -- Configuration
-- local ADDON = ADDON or {}
-- ADDON.Config = {
--     EnableWorldRendering = true,
--     EnableEntities = true,
--     EnableViewmodel = false,
--     EnableEffects = true,
--     EnableHUD = true,
--     SafeMode = false
-- }

-- -- Preserve critical render functions
-- local originalRenderOverride = render.RenderView
-- local originalRenderScene = render.RenderScene
-- local originalDrawHUD = _G.GAMEMODE and _G.GAMEMODE.HUDPaint

-- -- Only block dangerous render operations
-- local function SafeRenderProcessing()
--     -- Restore basic rendering but maintain safety
--     render.RenderView = function(viewData)
--         if not viewData then return end
--         return originalRenderOverride(viewData)
--     end
    
--     render.RenderScene = function(origin, angles, fov)
--         return originalRenderScene(origin, angles, fov)
--     end
    
--     -- Block problematic effects
--     hook.Add("RenderScreenspaceEffects", "BlockEffects", function()
--         return true
--     end)
-- end

-- -- Simple entity processing (keeping it minimal)
-- local function SelectiveEntityProcessing()
--     local dangerousClasses = {
--         ["env_fire"] = true,
--         ["env_explosion"] = true,
--         ["env_smoketrail"] = true,
--         ["env_shooter"] = true,
--         ["env_spark"] = true,
--         ["entityflame"] = true,
--         ["env_spritetrail"] = true,
--         ["beam"] = true,
--         ["_firesmoke"] = true,
--         ["_explosionfade"] = true
--     }

--     hook.Add("Think", "SelectiveBlock", function()
--         for _, ent in ipairs(ents.GetAll()) do
--             if IsValid(ent) and dangerousClasses[ent:GetClass()] then
--                 ent:SetNoDraw(true)
--                 ent:SetNotSolid(true)
--                 ent:SetMoveType(MOVETYPE_NONE)
--             end
--         end
--     end)
-- end

-- -- Safe engine settings
-- local function ConfigureEngineSettings()
--     RunConsoleCommand("r_drawworld", "1")
--     RunConsoleCommand("r_drawstaticprops", "1")
--     RunConsoleCommand("r_drawentities", "1")
--     RunConsoleCommand("cl_drawhud", "1")
--     RunConsoleCommand("r_drawparticles", "1")	
    
--     -- Keep these disabled for safety
--     RunConsoleCommand("r_3dsky", "0")
--     RunConsoleCommand("r_shadows", "0")
-- end

-- -- Block only dangerous effects
-- hook.Add("PostProcessPermitted", "BlockDangerousEffects", function(element)
--     return false
-- end)


-- -- Initialize
-- SafeRenderProcessing()
-- SelectiveEntityProcessing()
-- ConfigureEngineSettings()

-- -- Simple cleanup timer
-- timer.Create("SafeCleanup", 1, 0, function()
--     for _, ent in ipairs(ents.GetAll()) do
--         if IsValid(ent) and ent.GetClass and ent:GetClass():find("effect") then
--             ent:Remove()
--         end
--     end
-- end)

-- -- Restore HUD rendering
-- hook.Add("HUDPaint", "RestoreHUD", function()
--     if originalDrawHUD then
--         originalDrawHUD(_G.GAMEMODE)
--     end
-- end)