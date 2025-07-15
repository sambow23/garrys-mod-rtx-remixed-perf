if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if SERVER then return end

-- RemixMapConfigs: Automatic per-map RTX configuration system
local RemixMapConfigs = {}

-- Configuration
local CONFIG_DIR = "remix_map_configs"
local BACKUP_FILE = CONFIG_DIR .. "/backup.txt"
local DEBUG_MODE = CreateClientConVar("rtx_conf_map_configs_debug", "0", true, false, "Enable debug output for map configs")

local TRACKED_CONFIGS = {
    ---- Modify this list to add parameters you want to save/load per map.
    
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
    "rtx.autoExposure.enabled",
    "rtx.autoExposure.evMinValue",
    "rtx.autoExposure.evMaxValue",
    "rtx.tonemap.exposureBias",
    "rtx.tonemap.dynamicRange",
    "rtx.tonemappingMode",
    "rtx.bloom.enable",
    "rtx.bloom.burnIntensity",
    "rtx.postfx.enable",
    "rtx.enableFog"
}

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
local function BackupConfigVariables(variablesToBackup)
    if not RemixConfig then
        DebugPrint("RemixConfig API not available for backup")
        return false
    end
    
    EnsureConfigDir()
    
    local backupLines = {}
    local backupCount = 0
    
    -- Add header
    table.insert(backupLines, "# RTX Remix settings backup")
    table.insert(backupLines, "# Created: " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(backupLines, "# Variables backed up before applying map-specific config")
    table.insert(backupLines, "")
    
    -- Backup each variable
    for _, configKey in ipairs(variablesToBackup) do
        local currentValue = RemixConfig.GetConfigVariable(configKey)
        if currentValue and currentValue ~= "" then
            table.insert(backupLines, configKey .. " = " .. currentValue)
            DebugPrint("Backed up " .. configKey .. " = " .. currentValue)
            backupCount = backupCount + 1
        end
    end
    
    if backupCount > 0 then
        local backupText = table.concat(backupLines, "\n")
        file.Write(BACKUP_FILE, backupText)
        DebugPrint("Backed up " .. backupCount .. " config variables to " .. BACKUP_FILE)
        print("[RTXF2 - Remix API] Backed up " .. backupCount .. " RTX settings to backup file")
        return true
    else
        DebugPrint("No variables to backup")
        return false
    end
end

local function RestoreBackupConfig()
    if not RemixConfig then
        DebugPrint("RemixConfig API not available for restore")
        return false
    end
    
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
                
                -- Restore the config variable
                if RemixConfig.SetConfigVariable(key, value) then
                    DebugPrint("Restored " .. key .. " = " .. value)
                    restoredCount = restoredCount + 1
                else
                    DebugPrint("Failed to restore " .. key .. " = " .. value)
                end
            end
        end
    end
    
    print("[RTXF2 - Remix API] Restored " .. restoredCount .. " RTX settings from backup")
    
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
        return {}
    end
    
    local configText = file.Read(filePath, "DATA")
    if not configText then
        return {}
    end
    
    local variables = {}
    for line in string.gmatch(configText, "[^\r\n]+") do
        line = string.Trim(line)
        
        -- Skip comments and empty lines
        if line ~= "" and not string.StartWith(line, "#") then
            -- Parse key = value to get the key
            local key = string.match(line, "^(%S+)%s*=")
            if key then
                table.insert(variables, key)
            end
        end
    end
    
    return variables
end

-- File I/O functions
local function SaveMapConfig(mapName)
    if not RemixConfig then
        DebugPrint("RemixConfig API not available")
        return false
    end
    
    EnsureConfigDir()
    
    -- GetConfigVariable now reads directly from config file and defaults
    DebugPrint("Getting current config values...")
    
    local configData = {}
    local configLines = {}
    
    -- Add header
    table.insert(configLines, "# RTX Remix configuration for map: " .. mapName)
    table.insert(configLines, "# " .. os.date("%Y-%m-%d %H:%M:%S"))
    table.insert(configLines, "")
    table.insert(configLines, "# Note: These are current config values. Adjust RTX settings in-game,")
    table.insert(configLines, "# then save again or modify this file directly.")
    table.insert(configLines, "")
    
    -- Save each tracked config variable
    local savedCount = 0
    for _, configKey in ipairs(TRACKED_CONFIGS) do
        local value = RemixConfig.GetConfigVariable(configKey)
        if value and value ~= "" then
            configData[configKey] = value
            table.insert(configLines, configKey .. " = " .. value)
            DebugPrint("Saved " .. configKey .. " = " .. value)
            savedCount = savedCount + 1
        else
            DebugPrint("Skipped " .. configKey .. " (no value)")
        end
    end
    
    -- Write to file
    local configText = table.concat(configLines, "\n")
    local filePath = GetConfigPath(mapName)
    
    file.Write(filePath, configText)
    
    DebugPrint("Saved config for map '" .. mapName .. "' to " .. filePath)
    print("[RTXF2 - Remix API] Saved " .. savedCount .. " RTX settings for map: " .. mapName)
    
    if savedCount == 0 then
        print("[RTXF2 - Remix API] Warning: No config values were saved. Try adjusting RTX settings first, or check if RemixConfig API is working.")
    end
    
    return savedCount > 0
end

local function LoadMapConfig(mapName)
    if not RemixConfig then
        DebugPrint("RemixConfig API not available")
        return false
    end
    
    local filePath = GetConfigPath(mapName)
    
    if not file.Exists(filePath, "DATA") then
        DebugPrint("No config file found for map: " .. mapName)
        return false
    end
    
    -- First, parse the config file to see which variables it contains
    local variablesToChange = ParseConfigFileVariables(mapName)
    
    if #variablesToChange == 0 then
        DebugPrint("No valid config variables found in file: " .. filePath)
        return false
    end
    
    -- Backup the current values of variables that will be changed
    BackupConfigVariables(variablesToChange)
    
    local configText = file.Read(filePath, "DATA")
    if not configText then
        DebugPrint("Failed to read config file: " .. filePath)
        return false
    end
    
    DebugPrint("Loading config for map: " .. mapName)
    
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
                
                -- Set the config variable
                if RemixConfig.SetConfigVariable(key, value) then
                    DebugPrint("Loaded " .. key .. " = " .. value)
                    loadedCount = loadedCount + 1
                else
                    DebugPrint("Failed to set " .. key .. " = " .. value)
                end
            end
        end
    end
    
    print("[RTXF2 - Remix API] Loaded " .. loadedCount .. " RTX settings for map: " .. mapName)
    if HasBackup() then
        print("[RTXF2 - Remix API] Previous settings backed up and can be restored")
    end
    return loadedCount > 0
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
    
    for _, fileName in ipairs(files) do
        local mapName = string.StripExtension(fileName)
        table.insert(mapNames, mapName)
        print("  - " .. mapName)
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

-- Hook into map events
hook.Add("InitPostEntity", "RemixMapConfigs_MapStart", OnMapStart)
hook.Add("Disconnected", "RemixMapConfigs_Disconnect", OnDisconnect)

-- Console commands
concommand.Add("rtx_conf_save_map_config", function()
    RemixMapConfigs.SaveCurrentMapConfig()
end, nil, "Save current RTX settings for this map")

concommand.Add("rtx_conf_load_map_config", function()
    RemixMapConfigs.LoadCurrentMapConfig()
end, nil, "Load RTX settings for this map")

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

concommand.Add("rtx_conf_capture_values", function()
    if not RemixConfig then
        print("[RTXF2 - Remix API] RemixConfig API not available")
        return
    end
    
    print("[RTXF2 - Remix API] Cache system has been removed. RTX settings are now read directly from config file and defaults.")
    print("You can save current settings with: remix_save_map_config")
end, nil, "Info about RTX settings capture (cache system removed)")

concommand.Add("rtx_conf_set_cached_value", function(ply, cmd, args)
    if not RemixConfig then
        print("[RTXF2 - Remix API] RemixConfig API not available")
        return
    end
    
    print("[RTXF2 - Remix API] Cache system has been removed. Use RemixConfig.SetConfigVariable() instead.")
    
    if #args >= 2 then
        local key = args[1]
        local value = args[2]
        
        if RemixConfig.SetConfigVariable(key, value) then
            print("[RTXF2 - Remix API] Set config variable: " .. key .. " = " .. value)
        else
            print("[RTXF2 - Remix API] Failed to set config variable: " .. key)
        end
    else
        print("Usage: rtx_conf_set_cached_value <key> <value>")
        print("Example: rtx_conf_set_cached_value rtx.pathMaxBounces 6")
    end
end, nil, "Set a config variable directly (cache system removed)")

concommand.Add("rtx_conf_restore_backup", function()
    if RemixMapConfigs.HasBackup() then
        RemixMapConfigs.RestoreBackup()
    else
        print("[RTXF2 - Remix API] No backup available to restore")
    end
end, nil, "Restore RTX settings from backup")

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

-- Make API globally available
_G.RemixMapConfigs = RemixMapConfigs