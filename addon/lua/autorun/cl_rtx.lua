if not CLIENT then return end

-- ConVars
local cv_enabled = CreateClientConVar("rtx_pseudoplayer", 1, true, false)
local cv_pseudoweapon = CreateClientConVar("rtx_pseudoweapon", 1, true, false)
local cv_disablevertexlighting = CreateClientConVar("rtx_disablevertexlighting", 0, true, false)
local cv_disablevertexlighting_old = CreateClientConVar("rtx_disablevertexlighting_old", 0, true, false)
local cv_fixmaterials = CreateClientConVar("rtx_fixmaterials", 1, true, false)
local cv_experimental_manuallight = CreateClientConVar("rtx_experimental_manuallight", 0, true, false)
local cv_experimental_mightcrash_combinedlightingmode = CreateClientConVar("rtx_experimental_mightcrash_combinedlightingmode", 0, false, false)
local cv_disable_when_unsupported = CreateClientConVar("rtx_disable_when_unsupported", 1, false, false)
local cv_debug = CreateClientConVar("rtx_rt_debug", "0", true, false, "Enable debug messages for RT States")

-- Light system cache
local lastLightUpdate = 0
local LIGHT_UPDATE_INTERVAL = 1.0

-- Initialize NikNaks
require("niknaks")

-- Utility function to concatenate tables
local function TableConcat(t1, t2)
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end
    return t1
end

-- Helper function for debug printing
local function DebugPrint(message)
    if cv_debug:GetBool() then
        print(message)
    end
end

-- Material management
local bannedmaterials = {
    "materials/particle/warp3_warp_noz.vmt",
    "materials/particle/warp4_warp.vmt",
    "materials/particle/warp4_warp_noz.vmt",
    "materials/particle/warp5_warp.vmt",
    "materials/particle/warp5_explosion.vmt",
    "materials/particle/warp_ripple.vmt"
}

local function FixupMaterial(filepath)
    -- Skip banned materials
    for _, v in pairs(bannedmaterials) do
        if v == filepath then return end
    end

    local mattrim = (filepath:sub(0, #"materials/") == "materials/") and filepath:sub(#"materials/" + 1) or filepath
    local matname = mattrim:gsub(".vmt" .. "$", "")
    local mat = Material(matname)

    if mat:IsError() then
        DebugPrint("[RTXF2 - Material Fixup] - This texture loaded as an error? Trying to fix anyways but this shouldn't happen.")
    end

    if mat:GetString("$addself") ~= nil then
        mat:SetInt("$additive", 1)
    end

    if mat:GetString("$basetexture") == nil then
        local blankmat = Material("debug/particleerror")
        mat:SetTexture("$basetexture", blankmat:GetTexture("$basetexture"))
    end
end

local function MaterialFixupInDir(dir)
    DebugPrint("[RTXF2 - Material Fixup] - Starting root material fixup in " .. dir)
    local _, allfolders = file.Find(dir .. "*", "GAME")
    
    -- Fix materials in root directory
    local allfiles, _ = file.Find(dir .. "*.vmt", "GAME")
    for _, v in pairs(allfiles) do
        FixupMaterial(dir .. v)
    end

    -- Fix materials in subdirectories
    for _, folder in pairs(allfolders) do
        local subfiles, _ = file.Find(dir .. folder .. "/*.vmt", "GAME")
        for _, v in pairs(subfiles) do
            FixupMaterial(dir .. folder .. "/" .. v)
        end
    end
end

local function MaterialFixups()
    MaterialFixupInDir("materials/particle/")
    MaterialFixupInDir("materials/effects/")

    -- Fix GUI materials
    local function FixupGUIMaterial(mat)
        -- Check if mat is a valid material object
        if not isstring(mat) and not isnumber(mat) and mat.SetTexture then
            local blankmat = Material("rtx/guiwhite")
            -- Make sure blankmat is also valid
            if not isstring(blankmat) and not isnumber(blankmat) and blankmat.GetTexture then
                mat:SetTexture("$basetexture", blankmat:GetTexture("$basetexture"))
            end
        end
    end

    local guiMaterials = {
        Material("vgui/white"),
        Material("vgui/white_additive"),
        Material("vgui/black"),
        Material("white"),
        Material("VGUI_White"),
        Material("!VGUI_White"),
        Material("!white")
    }

    for _, mat in ipairs(guiMaterials) do
        FixupGUIMaterial(mat)
    end
end

-- Entity management
local function DrawFix(self, flags)
    if cv_experimental_manuallight:GetBool() then return end
    render.SuppressEngineLighting(cv_disablevertexlighting:GetBool())

    -- Handle material overrides
    if self:GetMaterial() ~= "" then
        render.MaterialOverride(Material(self:GetMaterial()))
    end

    -- Handle submaterials
    for k, _ in pairs(self:GetMaterials()) do
        if self:GetSubMaterial(k - 1) ~= "" then
            render.MaterialOverrideByIndex(k - 1, Material(self:GetSubMaterial(k - 1)))
        end
    end

    -- Draw the model with static lighting
    self:DrawModel(flags + STUDIO_STATIC_LIGHTING)
    render.MaterialOverride(nil)
    render.SuppressEngineLighting(false)
end

local function FixupEntity(ent)
    if IsValid(ent) and ent:GetClass() ~= "procedural_shard" then
        ent.RenderOverride = DrawFix
    end
end

local function FixupEntities()
    for _, ent in pairs(ents.GetAll()) do
        FixupEntity(ent)
    end
end

-- RTX initialization
local function RTXLoad()
    DebugPrint("[RTXF2] - Initializing Client")

    -- Set up console commands
    RunConsoleCommand("r_radiosity", "0")
    RunConsoleCommand("r_PhysPropStaticLighting", "1")
    RunConsoleCommand("r_colorstaticprops", "0")
    RunConsoleCommand("r_lightinterp", "0")
    RunConsoleCommand("mat_fullbright", cv_experimental_manuallight:GetBool() and "1" or "0")

    -- Create entities
    local pseudoply = ents.CreateClientside("rtx_pseudoplayer")
    pseudoply:Spawn()

    local flashlightent = ents.CreateClientside("rtx_flashlight_ent")
    flashlightent:SetOwner(LocalPlayer())
    flashlightent:Spawn()

    -- Initialize systems
    FixupEntities()
    halo.Add = function() end

    if cv_fixmaterials:GetBool() then
        MaterialFixups()
    end
end

-- Render hooks
local function PreRender()
    if render.SupportsVertexShaders_2_0() then return end

    render.SuppressEngineLighting(
        cv_disablevertexlighting_old:GetBool() or 
        cv_experimental_manuallight:GetBool()
    )

    if cv_experimental_mightcrash_combinedlightingmode:GetBool() then
        render.SuppressEngineLighting(false)
    end

    if cv_experimental_manuallight:GetBool() then
        DoCustomLights()
    end
end

-- Register hooks
hook.Add("InitPostEntity", "RTXReady", RTXLoad)
hook.Add("PreRender", "RTXPreRender", PreRender)
hook.Add("PreDrawOpaqueRenderables", "RTXPreRenderOpaque", PreRender)
hook.Add("PreDrawTranslucentRenderables", "RTXPreRenderTranslucent", PreRender)
hook.Add("OnEntityCreated", "RTXEntityFixups", FixupEntity)

-- Console commands
concommand.Add("rtx_fixnow", RTXLoad)
concommand.Add("rtx_fixmaterials_fixnow", MaterialFixups)
concommand.Add("rtx_force_no_fullbright", function()
    render.SetLightingMode(0)
end)

-- Toggle RT -- 
if jit.arch == "x64" then
    local isRaytracingDisabledBySpawnmenu = false
    local spawnIconTimerName = "RTXFixes_ReenableRaytracingTimer"
    
    -- Hook into SpawniconGenerated: Disable RT while icons are generating
    hook.Add("SpawniconGenerated", "RTXFixes_HandleSpawniconGenerated", function(lastmodel, imagename, modelsleft)
        DebugPrint(string.format("[RTXF2] SpawniconGenerated hook called. Models left: %s, isRaytracingDisabledBySpawnmenu = %s", tostring(modelsleft), tostring(isRaytracingDisabledBySpawnmenu)))
        
        -- First, always cancel any pending timers to re-enable RT
        if timer.Exists(spawnIconTimerName) then
            timer.Remove(spawnIconTimerName)
            DebugPrint("[RTXF2] Cancelled timer to re-enable RT (new icons are being generated)")
        end
    
        -- Disable RT if it hasn't already been disabled by us
        if not isRaytracingDisabledBySpawnmenu then
            DebugPrint("[RTXF2] SpawniconGenerated hook: Disabling RT for icon generation...")
            local success, err = pcall(SetEnableRaytracing, false)
            if success then
                DebugPrint("[RTXF2] SpawniconGenerated hook: SetEnableRaytracing(false) call succeeded.")
                isRaytracingDisabledBySpawnmenu = true
            else
                DebugPrint("[RTXF2] SpawniconGenerated hook: Warning: Failed to disable raytracing. Error: " .. tostring(err))
            end
        end
    
        -- Start a timer to re-enable RT after a delay (similar to how the progress UI works)
        -- This will get constantly reset as long as icons are being generated
        timer.Create(spawnIconTimerName, 3, 1, function()
            if isRaytracingDisabledBySpawnmenu then
                DebugPrint("[RTXF2] Timer: Re-enabling RT after icon generation completed...")
                local success, err = pcall(SetEnableRaytracing, true)
                if success then
                    DebugPrint("[RTXF2] Timer: SetEnableRaytracing(true) call succeeded.")
                    isRaytracingDisabledBySpawnmenu = false
                else
                    DebugPrint("[RTXF2] Timer: Warning: Failed to re-enable raytracing. Error: " .. tostring(err))
                    -- Even if the call fails, reset the flag
                    isRaytracingDisabledBySpawnmenu = false
                end
            else
                DebugPrint("[RTXF2] Timer: Skipped enabling RT (was not disabled by us).")
            end
        end)
    end)
    
    hook.Remove("FinishToolMode", "RTXFixes_EnableRTOnFinishToolMode")
    
    DebugPrint("[RTXF2] Spawnicon RT toggle hooks initialized (Using SpawniconGenerated + timer).")
    
    -- Test Toggle Command --
    local currentRaytracingState = true -- Assume it starts enabled (default)
    
    local function ToggleRaytracingCommand()
        currentRaytracingState = not currentRaytracingState -- Flip the state
        DebugPrint("[RTXF2] Toggling raytracing via command. Setting enabled to: " .. tostring(currentRaytracingState))
        local success, err = pcall(SetEnableRaytracing, currentRaytracingState) -- Call directly using pcall
        if success then
            DebugPrint("[RTXF2] Successfully called SetEnableRaytracing.")
        else
            DebugPrint("[RTXF2] Warning: Failed to toggle raytracing via command. Error: " .. tostring(err))
            -- Flip state back if the call failed, so the next toggle attempt is correct
            currentRaytracingState = not currentRaytracingState
        end
    end
    concommand.Add("rtx_toggle_raytracing", ToggleRaytracingCommand)
    DebugPrint("[RTXF2] Added console command: rtx_toggle_raytracing")
    
    -- HUD notification for RT disabled state
    hook.Add("HUDPaint", "RTXFixes_RTDisabledNotification", function()
        if isRaytracingDisabledBySpawnmenu then
            -- Get screen dimensions
            local scrW, scrH = ScrW(), ScrH()
            
            -- Set up font and text
            local message = "RT Disabled (Building Spawnicons)"
            local font = "DermaLarge" -- Large built-in font
            surface.SetFont(font)
            local textW, textH = surface.GetTextSize(message)
            
            -- Position: upper right corner with some padding
            local padding = 20
            local x = scrW - textW - padding
            local y = padding
            
            -- Draw background
            local bgPadding = 10
            surface.SetDrawColor(0, 0, 0, 200) -- Semi-transparent black
            surface.DrawRect(x - bgPadding, y - bgPadding, textW + (bgPadding * 2), textH + (bgPadding * 2))
            
            -- Draw text
            surface.SetTextColor(255, 100, 100, 255) -- Red text
            surface.SetTextPos(x, y)
            surface.DrawText(message)
        end
    end)
else
    DebugPrint("[RTXF2] RT toggle features disabled: x64 required (current: " .. jit.arch .. ")")
end