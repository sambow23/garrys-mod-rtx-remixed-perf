if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if SERVER then return end

local RemixMapConfigs = {}

-- Configuration
local CONFIG_DIR = "remix_map_configs"
local BACKUP_FILE = CONFIG_DIR .. "/backup.txt"
local DEBUG_MODE = CreateClientConVar("rtx_conf_map_configs_debug", "0", true, false, "Enable debug output for map configs")
local AUTO_LOAD = CreateClientConVar("rtx_conf_map_configs_autoload", "1", true, false, "Automatically load map configs on map start")

local TRACKED_CONFIGS = {
    ---- Modify this list to add RTX parameters you want to save/load per map.
    
    "rtx.volumetrics.enable",
    "rtx.volumetrics.enableAtmosphere",
    "rtx.volumetrics.anisotropy",
    "rtx.volumetrics.depthOffset",
    "rtx.volumetrics.atmosphereHeightMeters",
    "rtx.volumetrics.atmosphereInverted",
    "rtx.volumetrics.atmospherePlanetRadiusMeters",
    "rtx.volumetrics.enableFogRemap",
    "rtx.volumetrics.enableFogColorRemap",
    "rtx.volumetrics.enableFogMaxDistanceRemap",
    "rtx.volumetrics.fogRemapColorMultiscatteringScale",
    "rtx.volumetrics.fogRemapMaxDistanceMaxMeters",
    "rtx.volumetrics.fogRemapMaxDistanceMinMeters",
    "rtx.volumetrics.fogRemapTransmittanceMeasurementDistanceMaxMeters",
    "rtx.volumetrics.fogRemapTransmittanceMeasurementDistanceMinMeters",
    "rtx.volumetrics.fogRemapColorMultiscatteringScale",
    "rtx.volumetrics.enableFogRemap",
    "rtx.volumetrics.enableFogColorRemap",
    "rtx.volumetrics.enableFogMaxDistanceRemap",
    "rtx.volumetrics.enableHeterogeneousFog",
    "rtx.volumetrics.noiseFieldDensityExponent",
    "rtx.volumetrics.noiseFieldDensityScale",
    "rtx.volumetrics.noiseFieldGain",
    "rtx.volumetrics.noiseFieldInitialFrequencyPerMeter",
    "rtx.volumetrics.noiseFieldLacunarity",
    "rtx.volumetrics.noiseFieldOctaves",
    "rtx.volumetrics.noiseFieldSubStepSizeMeters",
    "rtx.volumetrics.noiseFieldTimeScale",
    "rtx.volumetrics.froxelMaxDistanceMeters",
    "rtx.volumetrics.froxelDepthSlices",
    "rtx.volumetrics.froxelDepthSliceDistributionExponent",
    "rtx.volumetrics.froxelGridResolutionScale",
    "rtx.volumetrics.froxelFireflyFilteringLuminanceThreshold",
    "rtx.volumetrics.enableSpatialResampling",
    "rtx.volumetrics.enableTemporalResampling",
    "rtx.volumetrics.enableInitialVisibility",
    "rtx.volumetrics.visibilityReuse",
    "rtx.volumetrics.initialRISSampleCount",
    "rtx.volumetrics.maxAccumulationFrames",
    "rtx.volumetrics.restirFroxelDepthSlices",
    "rtx.volumetrics.restirGridGuardBandFactor",
    "rtx.volumetrics.restirGridScale",
    "rtx.volumetrics.spatialReuseMaxSampleCount",
    "rtx.volumetrics.spatialReuseSamplingRadius",
    "rtx.volumetrics.temporalReuseMaxSampleCount",
    "rtx.volumetrics.singleScatteringAlbedo",
    "rtx.volumetrics.transmittanceColor",
    "rtx.volumetrics.transmittanceMeasurementDistanceMeters",
    "rtx.volumetrics.enableInPortals",
    "rtx.volumetrics.enableReferenceMode",
    "rtx.volumetrics.debugDisableRadianceScaling",
    "rtx.bloom.enable",
    "rtx.bloom.burnIntensity",
    "rtx.autoExposure.enabled",
    "rtx.autoExposure.evMinValue",
    "rtx.autoExposure.evMaxValue", 
    "rtx.tonemap.exposureBias",
    "rtx.tonemap.dynamicRange",
    "rtx.tonemappingMode",
    "rtx.ignoreGamePointLights",
    "rtx.ignoreGameSpotLights",
    "rtx.ignoreGameDirectionalLights",
    "rtx.skyBrightness"
}

local TRACKED_SOURCE_COMMANDS = {
    ---- Modify this list to add Source engine console variables you want to save/load per map.
    ---- These are regular Source engine cvars like mat_*, r_*, fps_max, etc.
    
    "r_3dsky"
}

-- These probably shouldnt be hardcoded, but this will be changed later. // CR

-- Current map name
local currentMap = ""

-- Utility functions
local function DebugPrint(msg)
    if DEBUG_MODE:GetBool() then
        print("[RTXF2 - Remix API] " .. msg)
    end
end

local function GetCurrentMap()
    return game.GetMap() or ""
end

local function GetConfigPath(mapName)
    return CONFIG_DIR .. "/" .. mapName .. ".txt"
end

-- File I/O helper function
local function EnsureConfigDir()
    if not file.Exists(CONFIG_DIR, "DATA") then
        file.CreateDir(CONFIG_DIR)
        DebugPrint("Created config directory: " .. CONFIG_DIR)
    end
end

-- Backup and restore functions
local function BackupConfigVariables(rtxVariablesToBackup, sourceVariablesToBackup)
    EnsureConfigDir()
    
    local backupLines = {}
    local backupCount = 0
    
    -- Add header
    table.insert(backupLines, "# RTX Remix and Source engine settings backup")
    table.insert(backupLines, "# Created: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(backupLines, "# Settings backed up before applying map-specific config")
    table.insert(backupLines, "")
    
    -- Backup RTX variables
    if RemixConfig and rtxVariablesToBackup and #rtxVariablesToBackup > 0 then
        table.insert(backupLines, "# RTX Remix Settings")
        for _, configKey in ipairs(rtxVariablesToBackup) do
            local currentValue = RemixConfig.GetConfigVariable(configKey)
            if currentValue and currentValue ~= "" then
                table.insert(backupLines, "rtx:" .. configKey .. " = " .. currentValue)
                DebugPrint("Backed up RTX " .. configKey .. " = " .. currentValue)
                backupCount = backupCount + 1
            end
        end
        table.insert(backupLines, "")
    end
    
    -- Backup Source engine variables
    if sourceVariablesToBackup and #sourceVariablesToBackup > 0 then
        table.insert(backupLines, "# Source Engine Settings")
        for _, cvarName in ipairs(sourceVariablesToBackup) do
            local cvar = GetConVar(cvarName)
            if cvar then
                local currentValue = cvar:GetString()
                if currentValue and currentValue ~= "" then
                    table.insert(backupLines, "src:" .. cvarName .. " = " .. currentValue)
                    DebugPrint("Backed up Source " .. cvarName .. " = " .. currentValue)
                    backupCount = backupCount + 1
                end
            end
        end
        table.insert(backupLines, "")
    end
    
    if backupCount > 0 then
        local backupText = table.concat(backupLines, "\n")
        file.Write(BACKUP_FILE, backupText)
        DebugPrint("Backed up " .. backupCount .. " config variables to " .. BACKUP_FILE)
        print("[RTXF2 - Remix API] Backed up " .. backupCount .. " RTX and Source settings to backup file")
        return true
    else
        DebugPrint("No variables to backup")
        return false
    end
end

local function RestoreBackupConfig()
    if not file.Exists(BACKUP_FILE, "DATA") then
        DebugPrint("No backup file found: " .. BACKUP_FILE)
        return false
    end
    
    local backupText = file.Read(BACKUP_FILE, "DATA")
    if not backupText then
        DebugPrint("Failed to read backup file: " .. BACKUP_FILE)
        return false
    end
    
    DebugPrint("Restoring settings from backup file")
    
    local restoredCount = 0
    for line in string.gmatch(backupText, "[^\r\n]+") do
        line = string.Trim(line)
        
        -- Skip comments and empty lines
        if line ~= "" and not string.StartWith(line, "#") then
            -- Parse key = value
            local key, value = string.match(line, "^(%S+)%s*=%s*(.+)$")
            if key and value then
                -- Remove any trailing comments
                value = string.match(value, "^([^#]+)") or value
                value = string.Trim(value)
                
                -- Handle RTX config variables
                if string.StartWith(key, "rtx:") then
                    local rtxKey = string.sub(key, 5) -- Remove "rtx:" prefix
                    if RemixConfig and RemixConfig.SetConfigVariable(rtxKey, value) then
                        DebugPrint("Restored RTX " .. rtxKey .. " = " .. value)
                        restoredCount = restoredCount + 1
                    else
                        DebugPrint("Failed to restore RTX " .. rtxKey .. " = " .. value)
                    end
                -- Handle Source engine commands
                elseif string.StartWith(key, "src:") then
                    local cvarName = string.sub(key, 5) -- Remove "src:" prefix
                    RunConsoleCommand(cvarName, value)
                    DebugPrint("Restored Source " .. cvarName .. " = " .. value)
                    restoredCount = restoredCount + 1
                -- Handle legacy format (backwards compatibility)
                else
                    if RemixConfig and RemixConfig.SetConfigVariable(key, value) then
                        DebugPrint("Restored (legacy) " .. key .. " = " .. value)
                        restoredCount = restoredCount + 1
                    else
                        DebugPrint("Failed to restore (legacy) " .. key .. " = " .. value)
                    end
                end
            end
        end
    end
    
    print("[RTXF2 - Remix API] Restored " .. restoredCount .. " RTX and Source settings from backup")
    
    -- Clear the backup file after successful restoration
    if restoredCount > 0 then
        file.Delete(BACKUP_FILE)
        DebugPrint("Cleared backup file after successful restoration")
        print("[RTXF2 - Remix API] Backup file cleared - settings restored to original values")
    end
    
    return restoredCount > 0
end

local function ClearBackup()
    if file.Exists(BACKUP_FILE, "DATA") then
        file.Delete(BACKUP_FILE)
        DebugPrint("Deleted backup file: " .. BACKUP_FILE)
        print("[RTXF2 - Remix API] Backup file cleared")
        return true
    else
        DebugPrint("No backup file to clear")
        return false
    end
end

local function HasBackup()
    return file.Exists(BACKUP_FILE, "DATA")
end

local function ParseConfigFileVariables(mapName)
    local filePath = GetConfigPath(mapName)
    
    if not file.Exists(filePath, "DATA") then
        return {}, {}
    end
    
    local configText = file.Read(filePath, "DATA")
    if not configText then
        return {}, {}
    end
    
    local rtxVariables = {}
    local sourceVariables = {}
    
    for line in string.gmatch(configText, "[^\r\n]+") do
        line = string.Trim(line)
        
        -- Skip comments and empty lines
        if line ~= "" and not string.StartWith(line, "#") then
            -- Parse key = value to get the key
            local key = string.match(line, "^(%S+)%s*=")
            if key then
                if string.StartWith(key, "rtx:") then
                    table.insert(rtxVariables, string.sub(key, 5)) -- Remove "rtx:" prefix
                elseif string.StartWith(key, "src:") then
                    table.insert(sourceVariables, string.sub(key, 5)) -- Remove "src:" prefix
                else
                    -- Legacy format - assume RTX
                    table.insert(rtxVariables, key)
                end
            end
        end
    end
    
    return rtxVariables, sourceVariables
end

-- File I/O functions
local function SaveMapConfig(mapName)
    EnsureConfigDir()
    
    -- GetConfigVariable now reads directly from config file and defaults
    DebugPrint("Getting current config values...")
    
    local configData = {}
    local configLines = {}
    
    -- Add header
    table.insert(configLines, "# RTX Remix and Source Engine configuration for map: " .. mapName)
    table.insert(configLines, "# " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(configLines, "")
    table.insert(configLines, "# Note: These are current config values. Adjust RTX settings in-game,")
    table.insert(configLines, "# modify Source engine cvars, then save again or modify this file directly.")
    table.insert(configLines, "")
    
    local savedCount = 0
    
    -- Save RTX tracked config variables
    if RemixConfig and #TRACKED_CONFIGS > 0 then
        table.insert(configLines, "# RTX Remix Settings")
        for _, configKey in ipairs(TRACKED_CONFIGS) do
            local value = RemixConfig.GetConfigVariable(configKey)
            if value and value ~= "" then
                configData[configKey] = value
                table.insert(configLines, "rtx:" .. configKey .. " = " .. value)
                DebugPrint("Saved RTX " .. configKey .. " = " .. value)
                savedCount = savedCount + 1
            else
                DebugPrint("Skipped RTX " .. configKey .. " (no value)")
            end
        end
        table.insert(configLines, "")
    end
    
    -- Save Source engine tracked commands
    if #TRACKED_SOURCE_COMMANDS > 0 then
        table.insert(configLines, "# Source Engine Settings")
        for _, cvarName in ipairs(TRACKED_SOURCE_COMMANDS) do
            local cvar = GetConVar(cvarName)
            if cvar then
                local value = cvar:GetString()
                if value and value ~= "" then
                    configData[cvarName] = value
                    table.insert(configLines, "src:" .. cvarName .. " = " .. value)
                    DebugPrint("Saved Source " .. cvarName .. " = " .. value)
                    savedCount = savedCount + 1
                else
                    DebugPrint("Skipped Source " .. cvarName .. " (no value)")
                end
            else
                DebugPrint("Skipped Source " .. cvarName .. " (cvar not found)")
            end
        end
        table.insert(configLines, "")
    end
    
    -- Write to file
    local configText = table.concat(configLines, "\n")
    local filePath = GetConfigPath(mapName)
    
    file.Write(filePath, configText)
    
    DebugPrint("Saved config for map '" .. mapName .. "' to " .. filePath)
    print("[RTXF2 - Remix API] Saved " .. savedCount .. " RTX and Source settings for map: " .. mapName)
    
    if savedCount == 0 then
        print("[RTXF2 - Remix API] Warning: No config values were saved. Try adjusting RTX settings or Source cvars first.")
    end
    
    return savedCount > 0
end

local function LoadConfigFromFile(filePath, configName)
    if not file.Exists(filePath, "DATA") then
        return false, 0
    end
    
    local configText = file.Read(filePath, "DATA")
    if not configText then
        DebugPrint("Failed to read config file: " .. filePath)
        return false, 0
    end
    
    DebugPrint("Loading config: " .. configName)
    
    -- Parse config file and apply settings
    local loadedCount = 0
    for line in string.gmatch(configText, "[^\r\n]+") do
        line = string.Trim(line)
        
        -- Skip comments and empty lines
        if line ~= "" and not string.StartWith(line, "#") then
            -- Parse key = value
            local key, value = string.match(line, "^(%S+)%s*=%s*(.+)$")
            if key and value then
                -- Remove any trailing comments
                value = string.match(value, "^([^#]+)") or value
                value = string.Trim(value)
                
                -- Handle RTX config variables
                if string.StartWith(key, "rtx:") then
                    local rtxKey = string.sub(key, 5) -- Remove "rtx:" prefix
                    if RemixConfig and RemixConfig.SetConfigVariable(rtxKey, value) then
                        DebugPrint("Loaded RTX " .. rtxKey .. " = " .. value)
                        loadedCount = loadedCount + 1
                    else
                        DebugPrint("Failed to set RTX " .. rtxKey .. " = " .. value)
                    end
                -- Handle Source engine commands
                elseif string.StartWith(key, "src:") then
                    local cvarName = string.sub(key, 5) -- Remove "src:" prefix
                    RunConsoleCommand(cvarName, value)
                    DebugPrint("Loaded Source " .. cvarName .. " = " .. value)
                    loadedCount = loadedCount + 1
                -- Handle legacy format (backwards compatibility)
                else
                    if RemixConfig and RemixConfig.SetConfigVariable(key, value) then
                        DebugPrint("Loaded (legacy) " .. key .. " = " .. value)
                        loadedCount = loadedCount + 1
                    else
                        DebugPrint("Failed to set (legacy) " .. key .. " = " .. value)
                    end
                end
            end
        end
    end
    
    return true, loadedCount
end

local function LoadMapConfig(mapName)
    local filePath = GetConfigPath(mapName)
    local defaultPath = CONFIG_DIR .. "/default.txt"
    local loadedCount = 0
    local configSource = ""
    
    -- First try to load map-specific config
    if file.Exists(filePath, "DATA") then
        -- Parse the config file to see which variables it contains (for backup)
        local rtxVariables, sourceVariables = ParseConfigFileVariables(mapName)
        
        if #rtxVariables > 0 or #sourceVariables > 0 then
            -- Backup the current values of variables that will be changed
            BackupConfigVariables(rtxVariables, sourceVariables)
            
            local success, count = LoadConfigFromFile(filePath, "map config for " .. mapName)
            if success then
                loadedCount = count
                configSource = "map-specific config"
            end
        else
            DebugPrint("No valid config variables found in map-specific file: " .. filePath)
        end
    end
    
    -- If no map-specific config or it failed, try default.txt
    if loadedCount == 0 then
        DebugPrint("No map-specific config found, trying default.txt")
        
        -- For default config, we need to get the variables it contains for backup
        if file.Exists(defaultPath, "DATA") then
            local defaultConfigText = file.Read(defaultPath, "DATA")
            if defaultConfigText then
                local rtxVariables = {}
                local sourceVariables = {}
                
                for line in string.gmatch(defaultConfigText, "[^\r\n]+") do
                    line = string.Trim(line)
                    if line ~= "" and not string.StartWith(line, "#") then
                        local key = string.match(line, "^(%S+)%s*=")
                        if key then
                            if string.StartWith(key, "rtx:") then
                                table.insert(rtxVariables, string.sub(key, 5)) -- Remove "rtx:" prefix
                            elseif string.StartWith(key, "src:") then
                                table.insert(sourceVariables, string.sub(key, 5)) -- Remove "src:" prefix
                            else
                                -- Legacy format - assume RTX
                                table.insert(rtxVariables, key)
                            end
                        end
                    end
                end
                
                if #rtxVariables > 0 or #sourceVariables > 0 then
                    -- Backup the current values
                    BackupConfigVariables(rtxVariables, sourceVariables)
                    
                    local success, count = LoadConfigFromFile(defaultPath, "default config")
                    if success then
                        loadedCount = count
                        configSource = "default config"
                    end
                end
            end
        end
    end
    
    if loadedCount > 0 then
        print("[RTXF2 - Remix API] Loaded " .. loadedCount .. " RTX and Source settings from " .. configSource .. " for map: " .. mapName)
        if HasBackup() then
            print("[RTXF2 - Remix API] Previous settings backed up and can be restored")
        end
        return true
    else
        DebugPrint("No config file found for map: " .. mapName .. " (tried map-specific and default.txt)")
        return false
    end
end

-- Public API
function RemixMapConfigs.SaveCurrentMapConfig()
    local mapName = GetCurrentMap()
    if mapName == "" then
        print("[RTXF2 - Remix API] Error: No map loaded")
        return false
    end
    
    return SaveMapConfig(mapName)
end

function RemixMapConfigs.LoadCurrentMapConfig()
    local mapName = GetCurrentMap()
    if mapName == "" then
        print("[RTXF2 - Remix API] Error: No map loaded")
        return false
    end
    
    return LoadMapConfig(mapName)
end

function RemixMapConfigs.SaveMapConfig(mapName)
    if not mapName or mapName == "" then
        print("[RTXF2 - Remix API] Error: Invalid map name")
        return false
    end
    
    return SaveMapConfig(mapName)
end

function RemixMapConfigs.LoadMapConfig(mapName)
    if not mapName or mapName == "" then
        print("[RTXF2 - Remix API] Error: Invalid map name")
        return false
    end
    
    return LoadMapConfig(mapName)
end

function RemixMapConfigs.RestoreBackup()
    return RestoreBackupConfig()
end

function RemixMapConfigs.HasBackup()
    return HasBackup()
end

function RemixMapConfigs.ClearBackup()
    return ClearBackup()
end

function RemixMapConfigs.ListConfigs()
    local files, _ = file.Find(CONFIG_DIR .. "/*.txt", "DATA")
    
    if not files or #files == 0 then
        print("[RTXF2 - Remix API] No saved map configs found")
        return {}
    end
    
    print("[RTXF2 - Remix API] Saved map configs:")
    local mapNames = {}
    local hasDefault = false
    
    for _, fileName in ipairs(files) do
        local mapName = string.StripExtension(fileName)
        table.insert(mapNames, mapName)
        
        if mapName == "default" then
            hasDefault = true
            print("  - " .. mapName .. " (fallback config for maps without specific configs)")
        else
            print("  - " .. mapName)
        end
    end
    
    if not hasDefault then
        print("")
        print("  No default.txt found. Use 'rtx_conf_default_save' to create fallback settings.")
    end
    
    return mapNames
end

function RemixMapConfigs.DeleteMapConfig(mapName)
    if not mapName or mapName == "" then
        print("[RTXF2 - Remix API] Error: Invalid map name")
        return false
    end
    
    local filePath = GetConfigPath(mapName)
    
    if not file.Exists(filePath, "DATA") then
        print("[RTXF2 - Remix API] No config found for map: " .. mapName)
        return false
    end
    
    file.Delete(filePath)
    print("[RTXF2 - Remix API] Deleted config for map: " .. mapName)
    return true
end

-- Event handlers
local function OnMapStart()
    timer.Simple(1, function() -- Wait a moment for everything to load
        local newMap = GetCurrentMap()
        DebugPrint("Map started: " .. newMap)
        
        local hasBackupFile = HasBackup()
        local hasMapConfig = file.Exists(GetConfigPath(newMap), "DATA")
        
        currentMap = newMap
        
        if hasMapConfig then
            -- Map has config file
            DebugPrint("Map has config file: " .. currentMap)
            
            -- First, restore backup to get back to original settings (if we have one)
            if hasBackupFile then
                DebugPrint("Restoring original settings before applying map config")
                RestoreBackupConfig()
            end
            
            -- Then load the map config (this will backup the variables it's about to change)
            DebugPrint("Loading config for map: " .. currentMap)
            LoadMapConfig(currentMap)
        else
            -- Map has no config - just restore backup if we have one
            if hasBackupFile then
                DebugPrint("No config for map: " .. currentMap .. " - restoring backup settings")
                RestoreBackupConfig()
            else
                DebugPrint("No config file and no backup for map: " .. currentMap .. " - using current RTX settings")
            end
        end
    end)
end

local function OnDisconnect()
    DebugPrint("Disconnecting from server")
    -- Restore backup when disconnecting (backup will be automatically cleared)
    if HasBackup() then
        DebugPrint("Restoring original settings on disconnect")
        RestoreBackupConfig()
    end
end

-- Auto-loading functions
local function OnMapStart()
    -- Check if auto-loading is enabled
    if not AUTO_LOAD:GetBool() then
        DebugPrint("Auto-loading disabled, skipping config load")
        return
    end
    
    -- Small delay to ensure everything is loaded
    timer.Simple(1, function()
        local mapName = GetCurrentMap()
        if mapName and mapName ~= "" then
            DebugPrint("Auto-loading config for map: " .. mapName)
            RemixMapConfigs.LoadCurrentMapConfig()
        end
    end)
end

local function OnDisconnect()
    -- Restore backup when disconnecting/changing maps
    if HasBackup() then
        DebugPrint("Restoring backup config on disconnect")
        RestoreBackupConfig()
    end
end

-- Hook into map events
hook.Add("InitPostEntity", "RemixMapConfigs_MapStart", OnMapStart)
hook.Add("Disconnected", "RemixMapConfigs_Disconnect", OnDisconnect)

-- Console commands
concommand.Add("rtx_conf_save_map_config", function()
    RemixMapConfigs.SaveCurrentMapConfig()
end, nil, "Save current RTX and Source engine settings for this map")

concommand.Add("rtx_conf_load_map_config", function()
    RemixMapConfigs.LoadCurrentMapConfig()
end, nil, "Load RTX and Source engine settings for this map")

concommand.Add("rtx_conf_list_map_configs", function()
    RemixMapConfigs.ListConfigs()
end, nil, "List all saved map configs")

concommand.Add("rtx_conf_delete_map_config", function(ply, cmd, args)
    if #args < 1 then
        print("Usage: remix_delete_map_config <mapname>")
        return
    end
    
    RemixMapConfigs.DeleteMapConfig(args[1])
end, nil, "Delete config for specified map")

concommand.Add("rtx_conf_restore_backup", function()
    if RemixMapConfigs.HasBackup() then
        RemixMapConfigs.RestoreBackup()
    else
        print("[RTXF2 - Remix API] No backup available to restore")
    end
end, nil, "Restore RTX and Source engine settings from backup")

concommand.Add("rtx_conf_backup_status", function()
    if RemixMapConfigs.HasBackup() then
        local backupText = file.Read(BACKUP_FILE, "DATA")
        if backupText then
            print("[RTXF2 - Remix API] Backup file contents:")
            print("----------------------------------------")
            print(backupText)
            print("----------------------------------------")
        else
            print("[RTXF2 - Remix API] Backup file exists but couldn't be read")
        end
    else
        print("[RTXF2 - Remix API] No backup currently available")
    end
end, nil, "Show current backup status and contents")

concommand.Add("rtx_conf_clear_backup", function()
    if RemixMapConfigs.ClearBackup() then
        print("[RTXF2 - Remix API] Backup cleared")
    else
        print("[RTXF2 - Remix API] No backup to clear")
    end
end, nil, "Clear the current backup without restoring it")

concommand.Add("rtx_conf_default_save", function()
    EnsureConfigDir()
    
    local defaultPath = CONFIG_DIR .. "/default.txt"
    local configLines = {}
    
    -- Add header
    table.insert(configLines, "# RTX Remix and Source Engine default configuration")
    table.insert(configLines, "# " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(configLines, "")
    table.insert(configLines, "# This file will be loaded for any map that doesn't have its own config.")
    table.insert(configLines, "# Adjust RTX settings in-game and Source cvars, then run this command to save as defaults.")
    table.insert(configLines, "")
    
    local savedCount = 0
    
    -- Save RTX tracked config variables
    if RemixConfig and #TRACKED_CONFIGS > 0 then
        table.insert(configLines, "# RTX Remix Settings")
        for _, configKey in ipairs(TRACKED_CONFIGS) do
            local value = RemixConfig.GetConfigVariable(configKey)
            if value and value ~= "" then
                table.insert(configLines, "rtx:" .. configKey .. " = " .. value)
                savedCount = savedCount + 1
            end
        end
        table.insert(configLines, "")
    end
    
    -- Save Source engine tracked commands
    if #TRACKED_SOURCE_COMMANDS > 0 then
        table.insert(configLines, "# Source Engine Settings")
        for _, cvarName in ipairs(TRACKED_SOURCE_COMMANDS) do
            local cvar = GetConVar(cvarName)
            if cvar then
                local value = cvar:GetString()
                if value and value ~= "" then
                    table.insert(configLines, "src:" .. cvarName .. " = " .. value)
                    savedCount = savedCount + 1
                end
            end
        end
        table.insert(configLines, "")
    end
    
    -- Write to file
    local configText = table.concat(configLines, "\n")
    file.Write(defaultPath, configText)
    
    print("[RTXF2 - Remix API] Saved " .. savedCount .. " RTX and Source settings as default config")
    print("[RTXF2 - Remix API] Default config saved to: " .. defaultPath)
end, nil, "Save current RTX and Source engine settings as default config for all maps")

concommand.Add("rtx_conf_load_default", function()
    local defaultPath = CONFIG_DIR .. "/default.txt"
    
    if not file.Exists(defaultPath, "DATA") then
        print("[RTXF2 - Remix API] No default config file found. Use rtx_conf_default_save to create one.")
        return
    end
    
    local success, count = LoadConfigFromFile(defaultPath, "default config")
    if success then
        print("[RTXF2 - Remix API] Loaded " .. count .. " RTX and Source settings from default config")
    else
        print("[RTXF2 - Remix API] Failed to load default config")
    end
end, nil, "Load the default RTX and Source engine config immediately")

concommand.Add("rtx_conf_toggle_autoload", function()
    local currentValue = AUTO_LOAD:GetBool()
    AUTO_LOAD:SetBool(not currentValue)
    
    if AUTO_LOAD:GetBool() then
        print("[RTXF2 - Remix API] Auto-loading enabled - configs will load automatically on map start")
    else
        print("[RTXF2 - Remix API] Auto-loading disabled - use rtx_conf_load_map_config to load manually")
    end
end, nil, "Toggle automatic loading of map configs on map start")

-- Make API globally available
_G.RemixMapConfigs = RemixMapConfigs