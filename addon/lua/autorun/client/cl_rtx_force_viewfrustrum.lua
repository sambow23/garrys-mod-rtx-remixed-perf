if not CLIENT then return end

-- ConVars - Only keeping static mode options
local cv_enabled = CreateClientConVar("fr_enabled", "1", true, false, "Enable large render bounds for all entities")
local cv_static_regular_bounds = CreateClientConVar("fr_static_regular_bounds", "256", true, false, "Size of static render bounds for regular entities")
local cv_static_rtx_bounds = CreateClientConVar("fr_static_rtx_bounds", "256", true, false, "Size of static render bounds for RTX lights")
local cv_static_env_bounds = CreateClientConVar("fr_static_env_bounds", "32768", true, false, "Size of static render bounds for environment lights")
local cv_debug = CreateClientConVar("fr_debug_messages", "0", true, false, "Enable debug messages for view frustum forcing")

-- Disable engine static props since we're creating our own
RunConsoleCommand("r_drawstaticprops", "0")

-- Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache for static props
local staticProps = {}
local originalBounds = {}

local SPECIAL_ENTITIES = {
    ["hdri_cube_editor"] = true,
    ["rtx_lightupdater"] = true,
    ["rtx_lightupdatermanager"] = true
}

local LIGHT_TYPES = {
    POINT = "light",
    SPOT = "light_spot",
    DYNAMIC = "light_dynamic",
    ENVIRONMENT = "light_environment"
}

local REGULAR_LIGHT_TYPES = {
    [LIGHT_TYPES.POINT] = true,
    [LIGHT_TYPES.SPOT] = true,
    [LIGHT_TYPES.DYNAMIC] = true
}

local SPECIAL_ENTITY_BOUNDS = {
    ["prop_door_rotating"] = {
        size = 256,
        description = "Door entities",
    }
}

local PRESET_ORDER = {"Low", "Medium", "High", "Very High"}
local PRESETS = {
    ["Low"] = {
        regular = 256,
        rtx = 256,
        env = 32768
    },
    ["Medium"] = {
        regular = 1024,
        rtx = 256,
        env = 32768
    },
    ["High"] = {
        regular = 4096,
        rtx = 1024,
        env = 32768
    },
    ["Very High"] = {
        regular = 8096,
        rtx = 2048,
        env = 65536
    }
}

local MAP_PRESETS = {}

local function CreateStaticProps()
    -- Clear existing static props
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then
            prop:Remove()
        end
    end
    staticProps = {}

    if cv_enabled:GetBool() and NikNaks and NikNaks.CurrentMap then
        local regularSize = math.min(cv_static_regular_bounds:GetFloat(), 8192) -- Cap maximum size
        local props = NikNaks.CurrentMap:GetStaticProps()
        
        -- Pre-calculate bounds vectors
        local smallBounds = Vector(1024, 0, 0)  -- For small props
        local mediumBounds = Vector(2048, 0, 0) -- For medium props
        local largeBounds = Vector(regularSize, 0, 0) -- For large props
        
        for _, propData in pairs(props) do
            local prop = ClientsideModel(propData:GetModel())
            if IsValid(prop) then
                prop:SetPos(propData:GetPos())
                prop:SetAngles(propData:GetAngles())
                
                -- Determine bounds based on model size
                local mins, maxs = prop:GetModelBounds()
                if mins and maxs then
                    local size = maxs.x - mins.x
                    -- Use appropriate bounds based on model size
                    if size < 256 then
                        prop:SetRenderBounds(-smallBounds, smallBounds)
                    elseif size < 1024 then
                        prop:SetRenderBounds(-mediumBounds, mediumBounds)
                    else
                        prop:SetRenderBounds(-largeBounds, largeBounds)
                    end
                else
                    -- Fallback to medium bounds if we can't determine size
                    prop:SetRenderBounds(-mediumBounds, mediumBounds)
                end
                
                prop:SetColor(propData:GetColor())
                prop:SetModelScale(propData:GetScale())
                table.insert(staticProps, prop)
            end
        end
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Fixes] Created %d static props using tiered bounds system", #staticProps))
        end
    end
end

-- Helper function to identify RTX updaters
local function IsRTXUpdater(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return SPECIAL_ENTITIES[class] or 
           (ent:GetModel() and RTX_UPDATER_MODELS[ent:GetModel()])
end

-- Set bounds for a single entity
local function SetEntityBounds(ent)
    if not IsValid(ent) then return end
    
    -- Get static bounds sizes
    local regularSize = cv_static_regular_bounds:GetFloat()
    local rtxSize = cv_static_rtx_bounds:GetFloat()
    local envSize = cv_static_env_bounds:GetFloat()
    
    -- Special entity classes first
    local specialBounds = SPECIAL_ENTITY_BOUNDS[ent:GetClass()]
    if specialBounds then
        local size = specialBounds.size
        local bounds = Vector(size, size, size)
        ent:SetRenderBounds(-bounds, bounds)
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Fixes] Special entity bounds (%s): %d", 
                ent:GetClass(), size))
        end
    -- HDRI cube editor handling
    elseif ent:GetClass() == "hdri_cube_editor" then
        local bounds = Vector(envSize, envSize, envSize)
        ent:SetRenderBounds(-bounds, bounds)
        ent:DisableMatrix("RenderMultiply")
        ent:SetNoDraw(false)
    -- RTX updater handling
    elseif IsRTXUpdater(ent) then
        if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
            local bounds = Vector(envSize, envSize, envSize)
            ent:SetRenderBounds(-bounds, bounds)
        else
            local bounds = Vector(rtxSize, rtxSize, rtxSize)
            ent:SetRenderBounds(-bounds, bounds)
        end
        ent:DisableMatrix("RenderMultiply")
        
        -- Use consistent render mode and opacity
        if GetConVar("rtx_lightupdater_show"):GetBool() then
            ent:SetRenderMode(0)  // RENDERMODE_NORMAL
            ent:SetColor(Color(255, 255, 255, 255))
        else
            ent:SetRenderMode(2)  // RENDERMODE_TRANSALPHA
            ent:SetColor(Color(255, 255, 255, 1))
        end
    -- Regular entities
    else
        local bounds = Vector(regularSize, regularSize, regularSize)
        ent:SetRenderBounds(-bounds, bounds)
    end
end

-- Update all entities
local function UpdateAllEntities()
    for _, ent in ipairs(ents.GetAll()) do
        SetEntityBounds(ent)
    end
end

local function LoadMapPresets()
    local saved = util.JSONToTable(file.Read("rtx_map_presets.txt", "DATA") or "{}") or {}
    MAP_PRESETS = saved
    if cv_debug:GetBool() then
        print("[RTX Fixes] Loaded map presets:", table.Count(MAP_PRESETS), "entries")
    end
end

-- Save map presets
local function SaveMapPresets()
    file.Write("rtx_map_presets.txt", util.TableToJSON(MAP_PRESETS, true))
    if cv_debug:GetBool() then
        print("[RTX Fixes] Saved map presets")
    end
end

-- Get current map name
local function GetCurrentMap()
    return game.GetMap():lower()
end

-- Function to apply a specific preset
local function ApplyPreset(presetName)
    local preset = PRESETS[presetName]
    if preset then
        RunConsoleCommand("fr_static_regular_bounds", tostring(preset.regular))
        RunConsoleCommand("fr_static_rtx_bounds", tostring(preset.rtx))
        RunConsoleCommand("fr_static_env_bounds", tostring(preset.env))
        
        if cv_debug:GetBool() then
            print(string.format("[RTX Fixes] Applied preset: %s (Regular: %d, RTX: %d, Env: %d)", 
                presetName, preset.regular, preset.rtx, preset.env))
        end
        
        -- Update entities with new bounds
        UpdateAllEntities()
        CreateStaticProps()
    end
end

-- Apply preset for current map
local function ApplyMapPreset()
    local currentMap = GetCurrentMap()
    local preset = MAP_PRESETS[currentMap] or "Low" -- Default to Low if no preset is set
    
    if cv_debug:GetBool() then
        print(string.format("[RTX Fixes] Applying map preset: %s for map: %s", preset, currentMap))
    end
    
    ApplyPreset(preset)
end

-- Hook for new entities
hook.Add("OnEntityCreated", "SetLargeRenderBounds", function(ent)
    if not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if IsValid(ent) and cv_enabled:GetBool() then
            SetEntityBounds(ent)
        end
    end)
end)

-- Initial setup
hook.Add("InitPostEntity", "InitialBoundsSetup", function()
    timer.Simple(1, function()
        if cv_enabled:GetBool() then
            RunConsoleCommand("r_drawstaticprops", "0") -- Ensure engine props are disabled
            UpdateAllEntities()
            CreateStaticProps()
        end
    end)
end)

hook.Add("OnReloaded", "RefreshStaticProps", function()
    -- Remove existing static props
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then
            prop:Remove()
        end
    end
    staticProps = {}
    
    -- Recreate if enabled
    if cv_enabled:GetBool() then
        timer.Simple(1, CreateStaticProps)
    end
end)

-- Handle enable/disable
cvars.AddChangeCallback("fr_enabled", function(_, _, new)
    if tobool(new) then
        RunConsoleCommand("r_drawstaticprops", "0") -- Disable engine props when enabled
        UpdateAllEntities()
        CreateStaticProps()
    else
        RunConsoleCommand("r_drawstaticprops", "1") -- Re-enable engine props when disabled
        -- Remove static props when disabled
        for _, prop in pairs(staticProps) do
            if IsValid(prop) then
                prop:Remove()
            end
        end
        staticProps = {}
    end
end)

-- ConCommand to refresh all entities' bounds
concommand.Add("fr_refresh", function()
    if cv_enabled:GetBool() then
        UpdateAllEntities()
        print("Refreshed render bounds for all entities with static bounds")
    end
end)

-- Settings Panel
local function CreateSettingsPanel(panel)
    panel:ClearControls()
    
    panel:CheckBox("Enable Static Render Bounds", "fr_enabled")
    panel:ControlHelp("Enables forced static render bounds for all entities")
    
    panel:Help("")
    
    -- Static bounds settings
    local boundsForm = vgui.Create("DForm", panel)
    boundsForm:Dock(TOP)
    boundsForm:SetName("Static Bounds Settings")
    
    -- Add preset dropdown
    local presetCombo = boundsForm:ComboBox("Presets")
    presetCombo:SetSortItems(false)
    presetCombo:Clear()
    
    for i, presetName in ipairs(PRESET_ORDER) do
        presetCombo:AddChoice(presetName, nil, i == 1)
    end
    
    presetCombo:SetValue("Select a preset...")
    
    -- Handle preset selection
    function presetCombo:OnSelect(index, value)
        ApplyPreset(value)
    end
    
    boundsForm:Help("The static render bounds dictate how far entities should be culled around the player.")
    boundsForm:Help("The higher the values, the further they cull, at the cost of performance depending on the map.")
    
    local regularSlider = boundsForm:NumSlider("Regular Entity Bounds", "fr_static_regular_bounds", 256, 32000, 0)
    regularSlider:SetTooltip("Size of render bounds for regular entities")
    
    local rtxSlider = boundsForm:NumSlider("Standard Light Bounds", "fr_static_rtx_bounds", 256, 32000, 0)
    rtxSlider:SetTooltip("Size of render bounds for RTX lights")
    
    local envSlider = boundsForm:NumSlider("Environment Light Bounds", "fr_static_env_bounds", 16384, 65536, 0)
    envSlider:SetTooltip("Size of render bounds for environment lights")
    
    -- Add map preset management
    boundsForm:Help("\nMap Preset Management")
    
    -- Map list
    local mapList = vgui.Create("DListView", boundsForm)
    mapList:SetHeight(150)
    mapList:AddColumn("Map")
    mapList:AddColumn("Preset")
    
    -- Populate map list
    local function RefreshMapList()
        mapList:Clear()
        for mapname, preset in pairs(MAP_PRESETS) do
            mapList:AddLine(mapname, preset)
        end
    end
    
    RefreshMapList()
    
    -- Add map button
    local addBtn = vgui.Create("DButton", boundsForm)
    addBtn:SetText("Add Current Map")
    addBtn:SetSize(150, 25)
    
    function addBtn:DoClick()
        local currentMap = GetCurrentMap()
        local selectedPreset = presetCombo:GetValue()
        
        if selectedPreset and selectedPreset ~= "Select a preset..." then
            MAP_PRESETS[currentMap] = selectedPreset
            SaveMapPresets()
            RefreshMapList()
            surface.PlaySound("buttons/button14.wav")
        end
    end
    
    -- Remove map button
    local removeBtn = vgui.Create("DButton", boundsForm)
    removeBtn:SetText("Remove Selected")
    removeBtn:SetSize(150, 25)
    
    function removeBtn:DoClick()
        local selected = mapList:GetSelected()
        if #selected > 0 then
            local mapname = selected[1]:GetValue(1)
            MAP_PRESETS[mapname] = nil
            SaveMapPresets()
            RefreshMapList()
            surface.PlaySound("buttons/button14.wav")
        end
    end
    
    -- Add buttons to form
    local buttonPanel = vgui.Create("DPanel", boundsForm)
    buttonPanel:SetHeight(30)
    buttonPanel:Dock(TOP)
    buttonPanel.Paint = function() end
    
    addBtn:SetParent(buttonPanel)
    addBtn:Dock(LEFT)
    addBtn:DockMargin(0, 0, 5, 0)
    
    removeBtn:SetParent(buttonPanel)
    removeBtn:Dock(LEFT)
    
    boundsForm:AddItem(mapList)
    boundsForm:AddItem(buttonPanel)
end

hook.Add("Initialize", "LoadRTXMapPresets", LoadMapPresets)

-- Apply map preset when joining a map
hook.Add("InitPostEntity", "ApplyRTXMapPreset", function()
    timer.Simple(1, function()
        ApplyMapPreset()
    end)
end)

-- Apply map preset when changing maps
hook.Add("OnGamemodeLoaded", "ApplyRTXMapPreset", function()
    timer.Simple(1, function()
        ApplyMapPreset()
    end)
end)

-- Add to Utilities menu
hook.Add("PopulateToolMenu", "RTXFrustumOptimizationMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_OVF", "#RTX View Frustum", "", "", function(panel)
        CreateSettingsPanel(panel)
    end)
end)

-- Apply bounds when static values change
local function ApplyBoundsChange()
    if cv_enabled:GetBool() then
        UpdateAllEntities()
    end
end

cvars.AddChangeCallback("fr_static_regular_bounds", function()
    if cv_enabled:GetBool() then
        UpdateAllEntities()
        CreateStaticProps() -- Recreate static props with new bounds
    end
end)

cvars.AddChangeCallback("fr_static_rtx_bounds", function() ApplyBoundsChange() end)
cvars.AddChangeCallback("fr_static_env_bounds", function() ApplyBoundsChange() end)