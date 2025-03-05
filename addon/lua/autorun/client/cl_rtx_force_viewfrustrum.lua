if not CLIENT then return end

-- ConVars
local cv_enabled = CreateClientConVar("fr_enabled", "1", true, false, "Enable large render bounds for all entities")
local cv_bounds_size = CreateClientConVar("fr_bounds_size", "4096", true, false, "Size of render bounds")
local cv_rtx_updater_distance = CreateClientConVar("fr_rtx_distance", "2048", true, false, "Maximum render distance for regular RTX light updaters")
local cv_environment_light_distance = CreateClientConVar("fr_environment_light_distance", "32768", true, false, "Maximum render distance for environment light updaters")
local cv_debug = CreateClientConVar("fr_debug_messages", "0", true, false, "Enable debug messages for RTX view frustum optimization")
local cv_show_advanced = CreateClientConVar("fr_show_advanced", "0", true, false, "Show advanced RTX view frustum settings")

-- Cache the bounds vectors
local boundsSize = cv_bounds_size:GetFloat()
local mins = Vector(-boundsSize, -boundsSize, -boundsSize)
local maxs = Vector(boundsSize, boundsSize, boundsSize)

-- Cache RTXMath functions
local RTXMath_IsWithinBounds = RTXMath.IsWithinBounds
local RTXMath_DistToSqr = RTXMath.DistToSqr
local RTXMath_LerpVector = RTXMath.LerpVector
local RTXMath_GenerateChunkKey = RTXMath.GenerateChunkKey
local RTXMath_ComputeNormal = RTXMath.ComputeNormal
local RTXMath_CreateVector = RTXMath.CreateVector
local RTXMath_NegateVector = RTXMath.NegateVector
local RTXMath_MultiplyVector = RTXMath.MultiplyVector

-- Constants and caches
local Vector = Vector
local IsValid = IsValid
local pairs = pairs
local ipairs = ipairs
local DEBOUNCE_TIME = 0.1
local boundsUpdateTimer = "FR_BoundsUpdate"
local rtxUpdateTimer = "FR_RTXUpdate"
local rtxUpdaterCache = {}
local rtxUpdaterCount = 0
local staticProps = {}
local originalBounds = {}
local mapBounds = {
    min = Vector(-16384, -16384, -16384),
    max = Vector(16384, 16384, 16384)
}
local boundsInitialized = false
local patternCache = {}
local weakEntityTable = {__mode = "k"} -- Allows garbage collection of invalid entities
originalBounds = setmetatable({}, weakEntityTable)
rtxUpdaterCache = setmetatable({}, weakEntityTable)
local managedTimers = {}

-- RTX Light Updater model list
local RTX_UPDATER_MODELS = {
    ["models/hunter/plates/plate.mdl"] = true,
    ["models/hunter/blocks/cube025x025x025.mdl"] = true
}

-- Cache for static props
local staticProps = {}
local originalBounds = {} -- Store original render bounds

local SPECIAL_ENTITIES = {
    ["hdri_cube_editor"] = true,
    ["rtx_lightupdater"] = true,
    ["rtx_lightupdatermanager"] = true
}

local LIGHT_TYPES = {
    POINT = "light",
    SPOT = "light_spot",
    DYNAMIC = "light_dynamic",
    ENVIRONMENT = "light_environment",
    DIRECTIONAL = "light_directional"
}

local REGULAR_LIGHT_TYPES = {
    [LIGHT_TYPES.POINT] = true,
    [LIGHT_TYPES.SPOT] = true,
    [LIGHT_TYPES.DYNAMIC] = true,
    [LIGHT_TYPES.DIRECTIONAL] = true
}

local SPECIAL_ENTITY_BOUNDS = {
    ["prop_door_rotating"] = {
        size = 512, -- Default size for doors
        description = "Door entities", -- For debug/documentation
    },

    ["func_door_rotating"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["func_physbox"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["func_breakable"] = {
        size = 512, -- Default size for doors
        description = "func_ entities", -- For debug/documentation
    },

    ["^npc_%w+"] = {
        size = 512,
        description = "All npc_ entities",
        isPattern = true
    },

    ["^_rope%w+"] = {
        size = 512,
        description = "All _rope entities",
        isPattern = true
    },

    ["prop_physics"] = {
        size = 512, -- Default size for doors
        description = "Prop entities", -- For debug/documentation
    },
    -- Add more entities here as needed:
    -- ["entity_class"] = { size = number, description = "description" }
}

-- Helper Functions

local function CreateManagedTimer(name, delay, repetitions, func)
    -- Remove existing timer if it exists
    if timer.Exists(name) then
        timer.Remove(name)
    end
    
    -- Create new timer
    timer.Create(name, delay, repetitions, func)
    managedTimers[name] = true
end

local function CleanupInvalidEntities()
    local removed = 0
    for ent in pairs(originalBounds) do
        if not IsValid(ent) then
            originalBounds[ent] = nil
            removed = removed + 1
        end
    end
    
    for ent in pairs(rtxUpdaterCache) do
        if not IsValid(ent) then
            RemoveFromRTXCache(ent)
            removed = removed + 1
        end
    end
    
    if cv_debug:GetBool() and removed > 0 then
        print("[RTX Fixes] Cleaned up " .. removed .. " invalid entity references")
    end
end

local function IsPointWithinBounds(point)
    return point:WithinAABox(mapBounds.min, mapBounds.max)
end

local function UpdateBoundsVectors(size)
    boundsSize = size
    local vec = RTXMath_CreateVector(size, size, size)
    mins = RTXMath_NegateVector(vec)
    maxs = vec
end

local function IsInBounds(pos, mins, maxs)
    return RTXMath_IsWithinBounds(pos, mins, maxs)
end

-- Distance check using native implementation
local function GetDistanceSqr(pos1, pos2)
    return RTXMath_DistToSqr(pos1, pos2)
end

-- Helper function to add new special entities
function AddSpecialEntityBounds(class, size, description)
    SPECIAL_ENTITY_BOUNDS[class] = {
        size = size,
        description = description
    }
    
    -- Update existing entities of this class if the optimization is enabled
    if cv_enabled:GetBool() then
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                SetEntityBounds(ent, false)
            end
        end
    end
end

local function GetSpecialBoundsForClass(className)
    -- First try direct lookup (fastest)
    local directMatch = SPECIAL_ENTITY_BOUNDS[className]
    if directMatch then
        return directMatch
    end
    
    -- Check cache for previous pattern match
    if patternCache[className] then
        return patternCache[className]
    end
    
    -- Try pattern matching
    for pattern, boundsInfo in pairs(SPECIAL_ENTITY_BOUNDS) do
        if boundsInfo.isPattern and string.match(className, pattern) then
            -- Cache the result for future lookups
            patternCache[className] = boundsInfo
            return boundsInfo
        end
    end
    
    -- No match found
    return nil
end

-- Helper function to identify RTX updaters
local function IsRTXUpdater(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return SPECIAL_ENTITIES[class] or 
           (ent:GetModel() and RTX_UPDATER_MODELS[ent:GetModel()])
end

-- Store original bounds for an entity
local function StoreOriginalBounds(ent)
    if not IsValid(ent) or originalBounds[ent] then return end
    local mins, maxs = ent:GetRenderBounds()
    originalBounds[ent] = {mins = mins, maxs = maxs}
end

-- RTX updater cache management functions
local function AddToRTXCache(ent)
    if not IsValid(ent) or rtxUpdaterCache[ent] then return end
    if IsRTXUpdater(ent) then
        rtxUpdaterCache[ent] = true
        rtxUpdaterCount = rtxUpdaterCount + 1
        
        -- Set initial RTX bounds
        local rtxDistance = cv_rtx_updater_distance:GetFloat()
        local rtxBoundsSize = Vector(rtxDistance, rtxDistance, rtxDistance)
        ent:SetRenderBounds(-rtxBoundsSize, rtxBoundsSize)
        ent:DisableMatrix("RenderMultiply")
        ent:SetNoDraw(false)
        
        -- Special handling for hdri_cube_editor to ensure it's never culled
        if ent:GetClass() == "hdri_cube_editor" then
            -- Using a very large value for HDRI cube editor
            local hdriSize = 32768 -- Maximum recommended size
            local hdriBounds = Vector(hdriSize, hdriSize, hdriSize)
            ent:SetRenderBounds(-hdriBounds, hdriBounds)
        end
    end
end

local function RemoveFromRTXCache(ent)
    if rtxUpdaterCache[ent] then
        rtxUpdaterCache[ent] = nil
        rtxUpdaterCount = rtxUpdaterCount - 1
    end
end

-- Set bounds for a single entity
function SetEntityBounds(ent, useOriginal)
    if not IsValid(ent) then return end
    
    -- Original bounds restoration code...
    if useOriginal then
        if originalBounds[ent] then
            ent:SetRenderBounds(originalBounds[ent].mins, originalBounds[ent].maxs)
        end
        return
    end
    
    StoreOriginalBounds(ent)
    
    local entPos = ent:GetPos()
    if not entPos then return end
    
    -- Use pattern-aware lookup
    local className = ent:GetClass()
    local specialBounds = GetSpecialBoundsForClass(className)
    
    if specialBounds then
        local size = specialBounds.size
        
        -- For doors, use our native implementation
        if className == "prop_door_rotating" then
            EntityManager.CalculateSpecialEntityBounds(ent, size)
        else
            -- Regular special entities
            local bounds = RTXMath_CreateVector(size, size, size)
            local negBounds = RTXMath_NegateVector(bounds)
            ent:SetRenderBounds(negBounds, bounds)
        end
        
        -- Debug output if enabled
        if cv_debug:GetBool() then
            local patternText = specialBounds.isPattern and " (via pattern)" or ""
            print(string.format("[RTX Fixes] Special entity bounds applied (%s): %d%s", 
                className, size, patternText))
        end
        return
        
    -- Then check other entity types
elseif ent:GetClass() == "hdri_cube_editor" then
    local hdriSize = 32768
    local hdriBounds = RTXMath_CreateVector(hdriSize, hdriSize, hdriSize)
    local negHdriBounds = RTXMath_NegateVector(hdriBounds)
        
        -- Use native bounds check
        if RTXMath_IsWithinBounds(entPos, negHdriBounds, hdriBounds) then
            ent:SetRenderBounds(negHdriBounds, hdriBounds)
            ent:DisableMatrix("RenderMultiply")
            ent:SetNoDraw(false)
        end
        
    elseif rtxUpdaterCache[ent] then
        -- Completely separate handling for environment lights
        if ent.lightType == LIGHT_TYPES.ENVIRONMENT then
            local envSize = cv_environment_light_distance:GetFloat()
            local envBounds = RTXMath_CreateVector(envSize, envSize, envSize)
            local negEnvBounds = RTXMath_NegateVector(envBounds)
            
            -- Use native bounds and distance check
            if RTXMath_IsWithinBounds(entPos, negEnvBounds, envBounds) then
                ent:SetRenderBounds(negEnvBounds, envBounds)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    local distSqr = RTXMath_DistToSqr(entPos, vector_origin)
                    print(string.format("[RTX Fixes] Environment light bounds: %d (Distance: %.2f)", 
                        envSize, math.sqrt(distSqr)))
                end
            end
            
        elseif REGULAR_LIGHT_TYPES[ent.lightType] then
            local rtxDistance = cv_rtx_updater_distance:GetFloat()
            local rtxBounds = RTXMath_CreateVector(rtxDistance, rtxDistance, rtxDistance)
            local negRtxBounds = RTXMath_NegateVector(rtxBounds)
            
            -- Use native bounds and distance check
            if RTXMath_IsWithinBounds(entPos, negRtxBounds, rtxBounds) then
                ent:SetRenderBounds(negRtxBounds, rtxBounds)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    local distSqr = RTXMath_DistToSqr(entPos, vector_origin)
                    print(string.format("[RTX Fixes] Regular light bounds (%s): %d (Distance: %.2f)", 
                        ent.lightType, rtxDistance, math.sqrt(distSqr)))
                end
            end
        end
        
        ent:DisableMatrix("RenderMultiply")
        if GetConVar("rtx_lightupdater_show"):GetBool() then
            ent:SetRenderMode(0)
            ent:SetColor(Color(255, 255, 255, 255))
        else
            ent:SetRenderMode(2)
            ent:SetColor(Color(255, 255, 255, 1))
        end
    else
        -- Default bounds with native check
        if RTXMath_IsWithinBounds(entPos, mins, maxs) then
            ent:SetRenderBounds(mins, maxs)
        end
    end
end

local function UpdateAllEntitiesBatched(useOriginal)
    local allEntities = ents.GetAll()
    local totalEntities = #allEntities
    local batchSize = 100
    local batches = math.ceil(totalEntities / batchSize)
    
    local function ProcessEntityBatch(batchNum)
        local startIdx = (batchNum - 1) * batchSize + 1
        local endIdx = math.min(batchNum * batchSize, totalEntities)
        
        local batchEntities = {}
        for i = startIdx, endIdx do
            local ent = allEntities[i]
            if IsValid(ent) then
                SetEntityBounds(ent, useOriginal)
            end
        end
        
        -- Process next batch if more remain
        if batchNum < batches then
            timer.Simple(0.05, function()
                ProcessEntityBatch(batchNum + 1)
            end)
        end
    end
    
    -- Start batch processing
    ProcessEntityBatch(1)
end

-- Create clientside static props
local function CreateStaticProps()
    -- Clean up existing props first
    for _, prop in pairs(staticProps) do
        if IsValid(prop) then prop:Remove() end
    end
    staticProps = {}
    
    -- Store original ConVar value
    local originalPropSetting = GetConVar("r_drawstaticprops"):GetInt()
    
    if not (cv_enabled:GetBool() and NikNaks and NikNaks.CurrentMap) then 
        return 
    end
    
    -- Create props in batches to prevent frame drops
    local props = NikNaks.CurrentMap:GetStaticProps()
    local batchSize = 50
    local propCount = 0
    local totalProps = #props
    local batches = math.ceil(totalProps / batchSize)
    
    local function ProcessBatch(batchNum)
        local startIndex = (batchNum - 1) * batchSize + 1
        local endIndex = math.min(batchNum * batchSize, totalProps)
        
        local playerPos = LocalPlayer():GetPos()
        local maxDistance = 16384
        local maxDistSqr = maxDistance * maxDistance
        
        for i = startIndex, endIndex do
            local propData = props[i]
            if propData then
                local propPos = propData:GetPos()
                if RTXMath_DistToSqr(propPos, playerPos) <= maxDistSqr then
                    -- Stagger individual prop creation to further reduce stuttering
                    timer.Simple((i - startIndex) * 0.01, function()
                        local prop = ClientsideModel(propData:GetModel())
                        if IsValid(prop) then
                            prop:SetPos(propPos)
                            prop:SetAngles(propData:GetAngles())
                            prop:SetRenderBounds(mins, maxs)
                            prop:SetColor(propData:GetColor())
                            prop:SetSkin(propData:GetSkin())
                            local scale = propData:GetScale()
                            if scale != 1 then
                                prop:SetModelScale(scale)
                            end
                            table.insert(staticProps, prop)
                            propCount = propCount + 1
                        end
                    end)
                end
            end
        end
        
        -- Process next batch if there are more
        if batchNum < batches then
            timer.Simple(0.5, function() ProcessBatch(batchNum + 1) end)
        else
            if cv_debug:GetBool() then
                print("[RTX Fixes] Created " .. propCount .. " static props")
            end
        end
    end
    
    -- Start batch processing
    ProcessBatch(1)
    
    -- Save original setting in a global to restore later
    RTX_FRUSTUM_ORIGINAL_PROP_SETTING = originalPropSetting
end

-- Update all entities
local function UpdateAllEntities(useOriginal)
    for _, ent in ipairs(ents.GetAll()) do
        SetEntityBounds(ent, useOriginal)
    end
end

-- Hook for new entities
hook.Add("OnEntityCreated", "SetLargeRenderBounds", function(ent)
    if not IsValid(ent) then return end
    
    timer.Simple(0, function()
        if IsValid(ent) then
            AddToRTXCache(ent)
            SetEntityBounds(ent, not cv_enabled:GetBool())
        end
    end)
end)
-- Initial setup
hook.Add("InitPostEntity", "InitialBoundsSetup", function()
    timer.Simple(1, function()
        if cv_enabled:GetBool() then
            UpdateAllEntitiesBatched(false)
            CreateStaticProps()
        end
    end)
end)

-- Map cleanup/reload handler
hook.Add("OnReloaded", "RefreshStaticProps", function()
    -- Clear bounds cache
    originalBounds = {}
    
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

-- Handle ConVar changes
cvars.AddChangeCallback("fr_enabled", function(_, _, new)
    local enabled = tobool(new)
    
    if enabled then
        UpdateAllEntitiesBatched(false)
        CreateStaticProps()
        
        -- Disable engine static props when enabled
        RunConsoleCommand("r_drawstaticprops", "1")
    else
        UpdateAllEntitiesBatched(true)
        -- Remove static props
        for _, prop in pairs(staticProps) do
            if IsValid(prop) then
                prop:Remove()
            end
        end
        staticProps = {}
        -- Re-enable engine static props when disabled
        RunConsoleCommand("r_drawstaticprops", "1")
    end
end)

cvars.AddChangeCallback("fr_bounds_size", function(_, _, new)
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        UpdateBoundsVectors(tonumber(new))
        
        if cv_enabled:GetBool() then
            UpdateAllEntitiesBatched(false)
            CreateStaticProps()
        end
    end)
end)


cvars.AddChangeCallback("fr_rtx_distance", function(_, _, new)
    if not cv_enabled:GetBool() then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        local rtxDistance = tonumber(new)
        local rtxBoundsSize = Vector(rtxDistance, rtxDistance, rtxDistance)
        
        -- Only update non-environment light updaters
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) then
                -- Explicitly skip environment lights
                if ent.lightType ~= "light_environment" then
                    ent:SetRenderBounds(-rtxBoundsSize, rtxBoundsSize)
                end
            else
                RemoveFromRTXCache(ent)
            end
        end
    end)
end)

-- Separate callback for environment light distance changes
cvars.AddChangeCallback("fr_environment_light_distance", function(_, _, new)
    if not cv_enabled:GetBool() then return end
    
    CreateManagedTimer(boundsUpdateTimer, DEBOUNCE_TIME, 1, function()
        local envDistance = tonumber(new)
        local envBoundsSize = Vector(envDistance, envDistance, envDistance)
        
        -- Only update environment light updaters
        for ent in pairs(rtxUpdaterCache) do
            if IsValid(ent) and ent.lightType == "light_environment" then
                ent:SetRenderBounds(-envBoundsSize, envBoundsSize)
                
                -- Only print if debug is enabled
                if cv_enabled:GetBool() and cv_debug:GetBool() then
                    print(string.format("[RTX Fixes] Updating environment light bounds to %d", envDistance))
                end
            end
        end
    end)
end)

-- ConCommand to refresh all entities' bounds
concommand.Add("fr_refresh", function()
    -- Clear bounds cache
    originalBounds = {}
    
    if cv_enabled:GetBool() then
        boundsSize = cv_bounds_size:GetFloat()
        mins = Vector(-boundsSize, -boundsSize, -boundsSize)
        maxs = Vector(boundsSize, boundsSize, boundsSize)
        
        UpdateAllEntitiesBatched(false)
        CreateStaticProps()
    else
        UpdateAllEntitiesBatched(true)
    end
    
    print("Refreshed render bounds for all entities" .. (cv_enabled:GetBool() and " with large bounds" or " with original bounds"))
end)

-- Entity cleanup
hook.Add("EntityRemoved", "CleanupRTXCache", function(ent)
    RemoveFromRTXCache(ent)
    originalBounds[ent] = nil
end)

-- Cleanup Timer
timer.Create("FR_EntityCleanup", 60, 0, CleanupInvalidEntities)

-- Debug command
concommand.Add("fr_debug", function()
    print("\nRTX Frustum Optimization Debug:")
    print("Enabled:", cv_enabled:GetBool())
    print("Bounds Size:", cv_bounds_size:GetFloat())
    print("RTX Updater Distance:", cv_rtx_updater_distance:GetFloat())
    print("Static Props Count:", #staticProps)
    print("Stored Original Bounds:", table.Count(originalBounds))
    print("RTX Updaters (Cached):", rtxUpdaterCount)
    
    -- Special entities debug info
    print("\nSpecial Entity Classes:")
    for class, data in pairs(SPECIAL_ENTITY_BOUNDS) do
        print(string.format("  %s: %d units (%s)", 
            class, 
            data.size, 
            data.description))
    end
end)

local function CreateSettingsPanel(panel)
    -- Clear the panel first
    panel:ClearControls()
    
    -- Main toggle
    panel:CheckBox("Enable RTX View Frustum", "fr_enabled")
    panel:ControlHelp("Enables optimized render bounds for all entities")
    
    panel:Help("")
    
    -- Advanced settings toggle
    local advancedToggle = panel:CheckBox("Show Advanced Settings", "fr_show_advanced")
    panel:ControlHelp("Enable manual control of render bounds (Use with caution!)")
    
    -- Create a container for advanced settings
    local advancedPanel = vgui.Create("DPanel", panel)
    advancedPanel:Dock(TOP)
    advancedPanel:DockMargin(8, 8, 8, 8)
    advancedPanel:SetPaintBackground(false)
    advancedPanel:SetVisible(cv_show_advanced:GetBool())
    advancedPanel:SetTall(200) -- Adjust height as needed
    
    -- Advanced settings content
    local advancedContent = vgui.Create("DScrollPanel", advancedPanel)
    advancedContent:Dock(FILL)
    
    -- Regular entity bounds
    local boundsGroup = vgui.Create("DForm", advancedContent)
    boundsGroup:Dock(TOP)
    boundsGroup:DockMargin(0, 0, 0, 5)
    boundsGroup:SetName("Entity Bounds")
    
    local boundsSlider = boundsGroup:NumSlider("Regular Entity Bounds", "fr_bounds_size", 256, 32000, 0)
    boundsSlider:SetTooltip("Size of render bounds for regular entities")

    -- Light settings
    local lightGroup = vgui.Create("DForm", advancedContent)
    lightGroup:Dock(TOP)
    lightGroup:DockMargin(0, 0, 0, 5)
    lightGroup:SetName("Light Settings")
    
    local rtxDistanceSlider = lightGroup:NumSlider("Regular Light Distance", "fr_rtx_distance", 256, 32000, 0)
    rtxDistanceSlider:SetTooltip("Maximum render distance for regular RTX light updaters")
    
    local envLightSlider = lightGroup:NumSlider("Environment Light Distance", "fr_environment_light_distance", 16384, 65536, 0)
    envLightSlider:SetTooltip("Maximum render distance for environment light updaters")
    
    -- Warning text
    local warningLabel = vgui.Create("DLabel", advancedContent)
    warningLabel:Dock(TOP)
    warningLabel:DockMargin(5, 5, 5, 5)
    warningLabel:SetTextColor(Color(255, 200, 0))
    warningLabel:SetText("Warning: Changing these values may affect performance and visual quality.")
    warningLabel:SetWrap(true)
    warningLabel:SetTall(40)
    
    -- Tools section
    local toolsGroup = vgui.Create("DForm", advancedContent)
    toolsGroup:Dock(TOP)
    toolsGroup:DockMargin(0, 0, 0, 5)
    toolsGroup:SetName("Tools")
    
    local refreshBtn = toolsGroup:Button("Refresh All Bounds")
    function refreshBtn:DoClick()
        RunConsoleCommand("fr_refresh")
        surface.PlaySound("buttons/button14.wav")
    end
    
    -- Debug settings
    panel:Help("\nDebug Settings")
    panel:CheckBox("Show Debug Messages", "fr_debug_messages")
    panel:ControlHelp("Show detailed debug messages in console")
    
    -- Update advanced panel visibility when the ConVar changes
    cvars.AddChangeCallback("fr_show_advanced", function(_, _, new)
        if IsValid(advancedPanel) then
            advancedPanel:SetVisible(tobool(new))
        end
    end)
end

-- Add to Utilities menu
hook.Add("PopulateToolMenu", "RTXFrustumOptimizationMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_OVF", "#RTX View Frustum", "", "", function(panel)
        CreateSettingsPanel(panel)
    end)
end)

concommand.Add("fr_add_special_entity", function(ply, cmd, args)
    if not args[1] or not args[2] then
        print("Usage: fr_add_special_entity <class> <size> [description]")
        return
    end
    
    local class = args[1]
    local size = tonumber(args[2])
    local description = args[3] or "Custom entity bounds"
    
    if not size then
        print("Size must be a number!")
        return
    end
    
    AddSpecialEntityBounds(class, size, description)
    print(string.format("Added special entity bounds for %s: %d units", class, size))
end)