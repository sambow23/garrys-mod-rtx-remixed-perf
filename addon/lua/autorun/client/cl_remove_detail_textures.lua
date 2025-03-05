-- Detail Texture Remover using NikNaks
-- This addon replaces detail textures with dev textures after map load

-- Wait for NikNaks to load if it hasn't already
if not NikNaks then 
    require("niknaks") 
end

local enable_addon = CreateConVar("dtexture_remover_enabled", "1", FCVAR_ARCHIVE, "Enable/disable the Detail Texture Remover addon")
local apply_delay = CreateConVar("dtexture_remover_delay", "0", FCVAR_ARCHIVE, "Delay before initial removal (seconds)")
local debug_mode = CreateConVar("dtexture_remover_debug", "0", FCVAR_ARCHIVE, "Enable debugging output")

-- The replacement texture - using the error texture
local replacementTexture = "dev/dev_exclude_error"

-- Keep track of modified materials to avoid reprocessing
local modifiedMaterials = {}
local materialsProcessed = 0
local detailTexturesRemoved = 0

-- Timer identifier for continuous checking
local TIMER_NAME = "DetailTextureRemoverContinuous"

-- Debug print function
local function DebugPrint(...)
    if debug_mode:GetBool() then
        print("[Detail Texture Remover]", ...)
    end
end

-- Flag to track whether we're running via command (show all output) or automatically (silent)
local runningFromCommand = false

-- Function to process a single material
local function ProcessMaterial(matName)
    if not matName or matName == "" then 
        return false 
    end
    
    -- Skip already processed materials
    if modifiedMaterials[matName] ~= nil then
        return modifiedMaterials[matName] -- Return true if this had a detail texture, false otherwise
    end
    
    local mat = Material(matName)
    if not mat or mat:IsError() then 
        modifiedMaterials[matName] = false
        return false 
    end
    
    -- Check if this material has detail textures
    local detailTexture = mat:GetString("$detail")
    if detailTexture and detailTexture ~= "" then
        if runningFromCommand or debug_mode:GetBool() then
            DebugPrint("Found material with detail texture:", matName, "Detail:", detailTexture)
        end
        
        -- Replace the detail texture with our error texture
        mat:SetTexture("$detail", replacementTexture)
        
        detailTexturesRemoved = detailTexturesRemoved + 1
        materialsProcessed = materialsProcessed + 1
        modifiedMaterials[matName] = true
        return true
    else
        -- Mark as processed even if it doesn't have a detail texture
        materialsProcessed = materialsProcessed + 1
        modifiedMaterials[matName] = false
    end
    
    return false
end

-- Function to process materials from BSP faces
local function ProcessBSPMaterials()
    -- Skip if NikNaks is not available or current map isn't loaded
    if not NikNaks or not NikNaks.CurrentMap then
        if runningFromCommand then
            error("NikNaks or CurrentMap not available - cannot process BSP materials")
        end
        return
    end
    
    -- Get the current map
    local bsp = NikNaks.CurrentMap
    
    -- Process textures from map
    for _, texture in ipairs(bsp:GetTextures()) do
        if texture then
            ProcessMaterial(texture)
        end
    end
    
    -- Process faces to get additional materials
    for _, face in pairs(bsp:GetFaces()) do
        local texture = face:GetTexture()
        if texture then
            ProcessMaterial(texture)
        end
    end
    
    -- Process static props for more materials
    for _, prop in pairs(bsp:GetStaticProps()) do
        local modelPath = prop:GetModel()
        if modelPath then
            -- Use NikNaks model processing functions
            ProcessMaterial(modelPath)
        end
    end
end

-- Function to process all currently loaded entities
local function ProcessLoadedEntities()
    -- Process entities in the world
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end
        
        -- Process entity's materials
        if ent:GetMaterials() then
            for _, matName in ipairs(ent:GetMaterials()) do
                ProcessMaterial(matName)
            end
        end
        
        -- Process model
        local modelName = ent:GetModel()
        if modelName then
            ProcessMaterial(modelName)
        end
    end
end

-- Main function to remove detail textures - can be called repeatedly
local function RemoveDetailTextures(showOutput)
    if not enable_addon:GetBool() then return 0 end
    
    -- Save previous counts to calculate new replacements
    local previousProcessed = materialsProcessed
    local previousRemoved = detailTexturesRemoved
    
    -- Set flag for debug messages
    runningFromCommand = showOutput or false
    
    local startTime = SysTime()
    if runningFromCommand or debug_mode:GetBool() then
    end
    
    -- Process BSP materials
    if NikNaks and NikNaks.CurrentMap then
        ProcessBSPMaterials()
    else
        if runningFromCommand then
            error("NikNaks or CurrentMap not available - cannot process detail textures")
        end
        return 0
    end
    
    -- Process all loaded entities
    ProcessLoadedEntities()
    
    -- Reset flag
    runningFromCommand = false
    
    local endTime = SysTime()
    local processingTime = math.Round((endTime - startTime) * 1000)
    
    -- Calculate new textures found
    local newProcessed = materialsProcessed - previousProcessed
    local newRemoved = detailTexturesRemoved - previousRemoved
    
    -- Only report when new textures are found or when explicitly requested
    if newRemoved > 0 then
        if showOutput or debug_mode:GetBool() then
            print("[Detail Texture Remover] Found and replaced " .. newRemoved .. " new detail textures (took " .. processingTime .. "ms)")
        end
    elseif showOutput then
        print("[Detail Texture Remover] No new detail textures found (processed " .. newProcessed .. " new materials)")
    end
    
    return newRemoved
end

-- Start the continuous checking timer
local function StartContinuousChecking()
    if timer.Exists(TIMER_NAME) then 
        timer.Remove(TIMER_NAME)
    end
    
    -- Create a timer that runs every 2 seconds
    timer.Create(TIMER_NAME, 2, 0, function() RemoveDetailTextures(false) end)
    DebugPrint("Continuous detail texture checking enabled (every 2 seconds)")
end

-- Stop the continuous checking
local function StopContinuousChecking()
    if timer.Exists(TIMER_NAME) then
        timer.Remove(TIMER_NAME)
        DebugPrint("Continuous detail texture checking disabled")
    end
end

-- Function to handle when the enable cvar changes
cvars.AddChangeCallback("dtexture_remover_enabled", function(_, _, new)
    if new == "1" then
        StartContinuousChecking()
    else
        StopContinuousChecking()
    end
end)

-- Initial run with delay after NikNaks is fully loaded
hook.Add("InitPostEntity", "RemoveDetailTexturesOnMapLoad", function()
    if enable_addon:GetBool() then
        -- First run after map loads
        timer.Simple(apply_delay:GetFloat(), function()
            -- Ensure NikNaks and Map are ready
            if not NikNaks or not NikNaks.CurrentMap then
                print("[Detail Texture Remover] Waiting for NikNaks to fully load...")
                timer.Simple(2, function()
                    if not NikNaks or not NikNaks.CurrentMap then
                        error("[Detail Texture Remover] NikNaks or CurrentMap not available after waiting")
                        return
                    end
                    local found = RemoveDetailTextures(true)
                    StartContinuousChecking()
                end)
                return
            end
            
            local found = RemoveDetailTextures(true)
            
            -- Start continuous checking after initial scan
            StartContinuousChecking()
            
            -- Notification
            notification.AddLegacy("Replaced " .. detailTexturesRemoved .. " detail textures", NOTIFY_GENERIC, 5)
            surface.PlaySound("buttons/button14.wav")
        end)
    end
end)

-- Reset variables on map change
hook.Add("ShutDown", "CleanupDetailTextureRemover", function()
    StopContinuousChecking()
    modifiedMaterials = {}
    materialsProcessed = 0
    detailTexturesRemoved = 0
end)

-- Add command to manually trigger detail texture removal
concommand.Add("remove_detail_textures", function()
    local oldCount = detailTexturesRemoved
    RemoveDetailTextures(true) -- Force showing output when using command
    local newCount = detailTexturesRemoved - oldCount
    
    -- Don't need to duplicate the console output here since RemoveDetailTextures() will already output with showOutput=true
    notification.AddLegacy("Replaced " .. newCount .. " new detail textures", NOTIFY_GENERIC, 3)
end)

-- Add a simple menu option
hook.Add("PopulateToolMenu", "DetailTextureRemoverMenu", function()
    spawnmenu.AddToolMenuOption("Options", "Graphics", "DetailTextureRemover", "Detail Texture Remover", "", "", function(panel)
        panel:AddControl("Header", {Description = "Detail Texture Remover"})
        panel:AddControl("CheckBox", {Label = "Enable addon", Command = "dtexture_remover_enabled"})
        panel:AddControl("Slider", {Label = "Initial delay (seconds)", Command = "dtexture_remover_delay", Min = 0, Max = 10, Type = "Float"})
        panel:AddControl("CheckBox", {Label = "Debug mode", Command = "dtexture_remover_debug"})
        panel:AddControl("Button", {Label = "Scan for detail textures now", Command = "remove_detail_textures"})
        
        -- Add a description
        panel:Help("This addon replaces detail textures with " .. replacementTexture)
        panel:Help("Materials processed: " .. materialsProcessed)
        panel:Help("Detail textures replaced: " .. detailTexturesRemoved)
        panel:Help("Continuously scans every 2 seconds for new materials")
    end)
end)

print("[Detail Texture Remover] Addon loaded. Will replace detail textures with " .. replacementTexture)