local brightness_multiplier = CreateClientConVar("light2rtx_brightness", "5.0", true, false, "Brightness multiplier for converted lights")
local size_multiplier = CreateClientConVar("light2rtx_size", "5.0", true, false, "Size multiplier for converted lights")
local min_size = CreateClientConVar("light2rtx_min_size", "100", true, false, "Minimum size for RTX lights")
local max_size = CreateClientConVar("light2rtx_max_size", "1000", true, false, "Maximum size for RTX lights")
local visual_mode = CreateClientConVar("light2rtx_visual", "0", true, false, "Show visible models for lights")
local debug_mode = CreateClientConVar("light2rtx_debug", "0", true, false, "Enable debug messages")
local creation_delay = CreateClientConVar("light2rtx_creation_delay", "0.0", true, false, "Delay between light creation in seconds")
local creation_batch_size = CreateClientConVar("light2rtx_batch_size", "1", true, false, "Number of lights to create in each batch")
local creation_batch_delay = CreateClientConVar("light2rtx_batch_delay", "0.0", true, false, "Delay between batches in seconds")
local pos_jitter = CreateClientConVar("light2rtx_position_jitter", "1", true, false, "Add a small random offset to light positions to prevent conflicts")
local pos_jitter_amount = CreateClientConVar("light2rtx_position_jitter_amount", "0.1", true, false, "Amount of random position offset")
local rect_rotation_x = CreateClientConVar("light2rtx_rect_rotation_x", "0", true, false, "X rotation offset for rectangle and disk lights")
local rect_rotation_y = CreateClientConVar("light2rtx_rect_rotation_y", "0", true, false, "Y rotation offset for rectangle and disk lights")
local rect_rotation_z = CreateClientConVar("light2rtx_rect_rotation_z", "0", true, false, "Z rotation offset for rectangle and disk lights")

-- Track created entities so we can clean them up
local createdLights = {}
local last_entity_id = 0
local createdLightPositions = {}

-- Light entity classes we want to detect
local lightClasses = {
    ["light"] = true,
    ["light_spot"] = true,
    ["light_dynamic"] = true,
}

-- Mapping from Source light types to RTX light types
local rtxLightTypes = {
    ["light"] = 0, -- Sphere light
    ["light_dynamic"] = 0, -- Sphere light
    ["light_spot"] = 0, -- Disk light
}

-- Visual models to use for different light types
local lightModels = {
    ["light"] = "models/hunter/misc/sphere025x025.mdl",
    ["light_spot"] = "models/hunter/misc/sphere025x025.mdl",
    ["light_dynamic"] = "models/hunter/misc/sphere025x025.mdl",
}

-- Print debug messages if debug mode is enabled
local function DebugPrint(...)
    if debug_mode:GetBool() then
        print("[Light2RTX Debug]", ...)
    end
end

-- Convert a string "x y z" to a Vector
local function StringToVector(str)
    if type(str) == "Vector" then 
        return str -- Already a Vector
    elseif type(str) == "string" then
        local x, y, z = string.match(str, "([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)")
        if x and y and z then
            return Vector(tonumber(x), tonumber(y), tonumber(z))
        end
    end
    return Vector(0, 0, 0)
end

-- Helper function to estimate appropriate light size based on brightness
local function estimateLightSize(brightness, entitySize)
    -- Base size on brightness - brighter lights should be larger
    local baseSize = entitySize or 200
    
    -- Scale it by brightness
    baseSize = baseSize * (1 + brightness / 200)
    
    -- Apply size multiplier
    baseSize = baseSize * size_multiplier:GetFloat()
    
    -- Enforce minimum and maximum size
    return math.Clamp(baseSize, min_size:GetFloat(), max_size:GetFloat())
end

-- Helper function to estimate light brightness and color from BSP entity data
local function getLightProperties(entity)
    local color = Color(255, 255, 255)
    local brightness = 100
    local entitySize = nil
    local lightType = rtxLightTypes[entity.classname] or rtxLightTypes["default"]
    
    -- Special properties for each light type
    local lightProps = {
        rectWidth = 100,
        rectHeight = 100,
        angularDiameter = 0.5,
        coneAngle = 120,
        coneSoftness = 0.2,
        shapingEnabled = false
    }
    
    -- Extract color information from the _light property if available
    if entity._light then
        local r, g, b, i = string.match(entity._light or "", "(%d+)%s+(%d+)%s+(%d+)%s+(%d+)")
        if r and g and b and i then
            r, g, b, i = tonumber(r), tonumber(g), tonumber(b), tonumber(i)
            color = Color(r, g, b)
            
            -- Normalize brightness based on color intensity
            local colorIntensity = (r + g + b) / (3 * 255)
            brightness = i * colorIntensity / 2.55  -- Convert 0-255 to 0-100
        end
    end
    
    -- Get size from entity properties
    if entity.distance or entity._distance then
        entitySize = tonumber(entity.distance or entity._distance or nil)
    end
    
    -- Apply brightness multiplier
    brightness = brightness * brightness_multiplier:GetFloat()
    
    -- Estimate appropriate size
    local size = estimateLightSize(brightness, entitySize)
    
    -- Special handling for certain light types
    if entity.classname == "light_environment" then
        -- Environment lights are usually brighter and larger
        brightness = brightness * 1.5
        size = size * 1.5
        lightProps.angularDiameter = 0.5 -- Small angular diameter for sun-like light
    elseif entity.classname == "light_spot" then
        -- For spotlights, extract cone parameters
        local coneAngle = tonumber(entity.cone or entity._cone or 45)
        lightProps.coneAngle = coneAngle
        lightProps.coneSoftness = 0.2 -- Default softness
        
        -- Adjust rect dimensions based on cone angle
        -- Wider cone = wider rectangle
        local aspectRatio = 1.0 -- Default aspect ratio for the rectangle
        lightProps.rectWidth = size * aspectRatio
        lightProps.rectHeight = size
        
        -- Extract spotlight direction if available
        if entity.angles or entity._angles then
            local angles = StringToVector(entity.angles or entity._angles)
            lightProps.angles = Angle(angles.x, angles.y, angles.z)
        elseif entity.pitch or entity._pitch then
            local pitch = tonumber(entity.pitch or entity._pitch or 0)
            local yaw = tonumber(entity.angle or entity._angle or 0)
            lightProps.angles = Angle(pitch, yaw, 0)
        end
    end
    
    return color, brightness, size, lightType, lightProps
end

-- Find lights in the BSP data
local function findLightsInBSP()
    if not NikNaks or not NikNaks.CurrentMap then 
        print("[Light2RTX] NikNaks or current map data not available!")
        return {} 
    end
    
    local lights = {}
    local bsp = NikNaks.CurrentMap
    
    -- Check entities in the BSP
    for _, ent in pairs(bsp:GetEntities()) do
        if ent.classname and lightClasses[ent.classname] then
            -- Get position - convert to Vector if it's a string
            local pos = StringToVector(ent.origin)
            
            -- Skip if no valid position
            if pos == Vector(0, 0, 0) and ent.origin then
                DebugPrint("Could not parse position from:", ent.origin)
                continue
            end
            
            local color, brightness, size, lightType, lightProps = getLightProperties(ent)
            
            table.insert(lights, {
                pos = pos,
                color = color,
                brightness = brightness,
                size = size,
                classname = ent.classname,
                lightType = lightType,
                lightProps = lightProps,
                angles = lightProps.angles -- Store angles if available
            })
            
            DebugPrint(string.format("Found light: %s (RTX Type: %d) at %.2f,%.2f,%.2f - Color: %d,%d,%d - Brightness: %.1f - Size: %.1f", 
                ent.classname, lightType, pos.x, pos.y, pos.z, color.r, color.g, color.b, brightness, size))
        end
    end
    
    return lights
end

-- Create a unique entity ID for each light
local function getUniqueEntityID()
    last_entity_id = last_entity_id + 1
    -- Combine time-based component with counter and a random element
    local timeComponent = math.floor(CurTime() * 100) * 100000
    local randomComponent = math.random(1000, 9999)
    -- Ensure unique ID across client sessions
    return last_entity_id + timeComponent + randomComponent
end

-- Get the appropriate model for a light type
local function getLightModel(classname)
    return lightModels[classname] or lightModels["default"]
end

-- Create visual prop for a light
local function createVisualProp(pos, color, classname)
    local prop = ents.CreateClientProp(getLightModel(classname))
    if not IsValid(prop) then return nil end
    
    prop:SetPos(pos)
    prop:SetAngles(Angle(0, 0, 0))
    prop:SetColor(color)
    prop:SetRenderMode(RENDERMODE_TRANSALPHA)
    prop:SetModelScale(0.5, 0)
    
    -- Make it slightly transparent
    local c = prop:GetColor()
    prop:SetColor(Color(c.r, c.g, c.b, 200))
    
    -- Mark as a light prop for selection
    prop.RTXLight = true
    
    -- Make the prop pickupable with physgun
    -- Clientside entities aren't normally affected by the physics gun, but we'll
    -- track this flag and handle it ourselves
    prop:SetMoveType(MOVETYPE_VPHYSICS)
    prop:PhysicsInit(SOLID_VPHYSICS)
    
    return prop
end

-- Create RTX light entity
local function createRTXLightEntity(pos, color, brightness, size, lightType, lightProps, angles, visualProp)
    -- Generate a unique position key with some tolerance (0.1 units)
    local posKey = string.format("%.1f_%.1f_%.1f", pos.x, pos.y, pos.z)
    
    -- Check if we've already created a light at this position
    if createdLightPositions[posKey] then
        print("[Light2RTX] Skipping duplicate light at " .. posKey)
        return nil
    end
    
    -- Mark this position as being processed
    createdLightPositions[posKey] = true
    
    -- Rest of the function as before
    local ent = ents.CreateClientside("base_rtx_light")
    if not IsValid(ent) then
        print("[Light2RTX] Failed to create base_rtx_light entity")
        createdLightPositions[posKey] = nil  -- Clear the mark if failed
        return nil
    end
    
    -- Generate a truly unique ID for this entity
    -- Use the CRC of the position string to ensure uniqueness across map sessions
    local uniqueID = getUniqueEntityID() 
    ent.rtxEntityID = uniqueID
    DebugPrint("Creating entity with ID:", ent.rtxEntityID)
    
    -- Set position and properties
    ent:SetPos(pos)
    if angles then
        ent:SetAngles(angles)
    end
    
    -- Set common properties
    ent:SetLightType(lightType or 0)
    ent:SetLightBrightness(brightness)
    ent:SetLightSize(size)
    ent:SetLightR(color.r)
    ent:SetLightG(color.g)
    ent:SetLightB(color.b)
    ent:SetPos(pos)
    
    -- Set light-type specific properties
    if lightProps then
        -- Rectangle light properties
        if lightType == 1 then
            ent:SetRectWidth(lightProps.rectWidth)
            ent:SetRectHeight(lightProps.rectHeight)
        end
        
        -- Distant light properties
        if lightType == 3 then
            ent:SetAngularDiameter(lightProps.angularDiameter)
        end
        
        -- Light shaping properties (applies to most types)
        ent:SetShapingEnabled(lightProps.shapingEnabled)
        ent:SetConeAngle(lightProps.coneAngle)
        ent:SetConeSoftness(lightProps.coneSoftness)
    end

    if lightType == 1 or lightType == 2 then -- Rectangle (1) or Disk (2) lights
        local baseAngles = angles or Angle(0, 0, 0)
        
        -- Apply additional rotation from CVars
        baseAngles.x = baseAngles.x + rect_rotation_x:GetFloat()
        baseAngles.y = baseAngles.y + rect_rotation_y:GetFloat()
        baseAngles.z = baseAngles.z + rect_rotation_z:GetFloat()
        
        ent:SetAngles(baseAngles)
        
        DebugPrint(string.format("Applied rotation to light: %d,%d,%d", 
            baseAngles.x, baseAngles.y, baseAngles.z))
    elseif angles then
        ent:SetAngles(angles)
    end
    
    -- Link to visual prop if one exists
    if IsValid(visualProp) then
        ent.visualProp = visualProp
        visualProp.lightEntity = ent
    end
    
    -- Spawn the entity
    ent:Spawn()
    
    -- Create the RTX light with a retry mechanism
    local function attemptRTXLightCreation()
        if not IsValid(ent) then return end
        
        if ent.CreateRTXLight then
            ent:CreateRTXLight()
        end
    end
    
    -- Start the creation process after a small delay
    timer.Simple(0.1, attemptRTXLightCreation)
    
    return ent
end

local function addPositionOffset(pos)
    if not pos_jitter:GetBool() then return pos end
    
    local jitterAmount = pos_jitter_amount:GetFloat() or 0.1
    local offset = Vector(
        math.Rand(-jitterAmount, jitterAmount),
        math.Rand(-jitterAmount, jitterAmount),
        math.Rand(-jitterAmount, jitterAmount)
    )
    return pos + offset
end

-- Create RTX lights for all the lights we found
local function batchCreateRTXLights()
    -- Reset entity ID counter and position tracking
    last_entity_id = 0
    table.Empty(createdLightPositions)
    
    -- Get lights from BSP
    local bspLights = findLightsInBSP()
    print("[Light2RTX] Found " .. #bspLights .. " lights in BSP data")
    
    -- Skip duplicate positions in advance by using a position map
    local uniqueLightsByPosition = {}
    for _, light in ipairs(bspLights) do
        -- Add small jitter to prevent exact overlaps
        light.pos = addPositionOffset(light.pos)
        
        -- Create a unique position key
        local posKey = string.format("%.1f_%.1f_%.1f", light.pos.x, light.pos.y, light.pos.z)
        
        -- Only keep one light per position
        uniqueLightsByPosition[posKey] = light
    end
    
    -- Convert back to an array
    local uniqueLights = {}
    for _, light in pairs(uniqueLightsByPosition) do
        table.insert(uniqueLights, light)
    end
    
    print("[Light2RTX] After deduplication: " .. #uniqueLights .. " unique light positions")
    
    -- Batch processing variables
    local BATCH_SIZE = creation_batch_size:GetInt()
    local BATCH_DELAY = creation_batch_delay:GetFloat()
    local CREATION_INTERVAL = creation_delay:GetFloat()
    
    -- Split into batches
    local batches = {}
    for i = 1, #uniqueLights, BATCH_SIZE do
        local endIndex = math.min(i + BATCH_SIZE - 1, #uniqueLights)
        local batch = {}
        for j = i, endIndex do
            table.insert(batch, uniqueLights[j])
        end
        table.insert(batches, batch)
    end
    
    print("[Light2RTX] Split into " .. #batches .. " batches of up to " .. BATCH_SIZE .. " lights each")
    
    -- Process batches one at a time
    local function processBatch(batchIndex)
        if batchIndex > #batches then
            print("[Light2RTX] All batches complete. " .. #createdLights .. " lights created.")
            return
        end
        
        print("[Light2RTX] Processing batch " .. batchIndex .. "/" .. #batches)
        
        local batch = batches[batchIndex]
        local lightsCreated = 0
        
        -- Process lights in this batch with intervals
        for i, light in ipairs(batch) do
            timer.Simple((i-1) * CREATION_INTERVAL, function()
                -- Create visual prop if enabled
                local visualProp = nil
                if visual_mode:GetBool() then
                    visualProp = createVisualProp(light.pos, light.color, light.classname)
                    if light.angles and IsValid(visualProp) then
                        visualProp:SetAngles(light.angles)
                    end
                end
                
                -- Create the RTX light entity
                local ent = createRTXLightEntity(
                    light.pos, 
                    light.color, 
                    light.brightness, 
                    light.size,
                    light.lightType or 0,
                    light.lightProps,
                    light.angles,
                    visualProp
                )
                
                if IsValid(ent) then
                    table.insert(createdLights, ent)
                    lightsCreated = lightsCreated + 1
                    
                    -- Last light in batch
                    if i == #batch then
                        print("[Light2RTX] Batch " .. batchIndex .. " complete. Created " .. 
                            lightsCreated .. "/" .. #batch .. " lights.")
                        
                        -- Process next batch after delay
                        timer.Simple(BATCH_DELAY, function()
                            processBatch(batchIndex + 1)
                        end)
                    end
                else
                    -- Last light in batch but creation failed
                    if i == #batch then
                        print("[Light2RTX] Batch " .. batchIndex .. " complete with errors. Created " .. 
                            lightsCreated .. "/" .. #batch .. " lights.")
                        
                        -- Process next batch after delay
                        timer.Simple(BATCH_DELAY, function()
                            processBatch(batchIndex + 1)
                        end)
                    end
                end
            end)
        end
    end
    
    -- Start with the first batch
    processBatch(1)
    
    print("[Light2RTX] Started batch processing for " .. #uniqueLights .. " lights")
end

-- Remove all created lights
local function clearRTXLights()
    for _, ent in ipairs(createdLights) do
        if IsValid(ent) then
            -- Remove visual prop if it exists
            if IsValid(ent.visualProp) then
                ent.visualProp:Remove()
            end
            ent:Remove()
        end
    end
    createdLights = {}
    print("[Light2RTX] Cleared all RTX lights")
end

-- Toggle light visibility
local function toggleVisualMode()
    local newValue = not visual_mode:GetBool()
    RunConsoleCommand("light2rtx_visual", newValue and "1" or "0")
    
    -- If turning off, remove all visual props
    if not newValue then
        for _, ent in ipairs(createdLights) do
            if IsValid(ent) and IsValid(ent.visualProp) then
                ent.visualProp:Remove()
                ent.visualProp = nil
            end
        end
    else
        -- If turning on, create visual props for existing lights
        for _, ent in ipairs(createdLights) do
            if IsValid(ent) and not IsValid(ent.visualProp) then
                local visualProp = createVisualProp(
                    ent:GetPos(), 
                    Color(ent:GetLightR(), ent:GetLightG(), ent:GetLightB()),
                    "default"
                )
                
                if IsValid(visualProp) then
                    ent.visualProp = visualProp
                    visualProp.lightEntity = ent
                end
            end
        end
    end
    
    print("[Light2RTX] Visual mode " .. (newValue and "enabled" or "disabled"))
end

-- PhysGun functionality
local heldProps = {}

-- Enable drawing of beams
hook.Add("PostDrawOpaqueRenderables", "Light2RTX_DrawPhysBeams", function()
    local wep = LocalPlayer():GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "weapon_physgun" then 
        return 
    end
    
    -- Draw beams for all held props
    for prop, _ in pairs(heldProps) do
        if IsValid(prop) then
            local attachment = wep:GetAttachment(1) -- Get the physgun beam attachment
            if attachment then
                -- Draw a beam from the physgun to the held entity
                local startPos = attachment.Pos
                local endPos = prop:GetPos()
                
                render.SetMaterial(Material("cable/physbeam"))
                render.DrawBeam(startPos, endPos, 1, 0, 10, Color(0, 255, 255, 200))
            end
        end
    end
end)

-- Hook for picking up clientside props with the physgun
hook.Add("PhysgunPickup", "Light2RTX_PhysgunPickup", function(ply, ent)
    if ent.RTXLight then
        heldProps[ent] = true
        DebugPrint("Light prop picked up with physgun")
        return true
    end
end)

-- Hook for dropping clientside props with the physgun
hook.Add("PhysgunDrop", "Light2RTX_PhysgunDrop", function(ply, ent)
    if ent.RTXLight then
        heldProps[ent] = nil
        DebugPrint("Light prop dropped with physgun")
        return true
    end
end)

-- Handle moving the held props with the physgun
hook.Add("Think", "Light2RTX_PhysgunThink", function()
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    
    if not IsValid(wep) or wep:GetClass() ~= "weapon_physgun" then
        -- If player isn't holding a physgun, clear held props
        heldProps = {}
        return
    end
    
    if not input.IsMouseDown(MOUSE_LEFT) then
        -- If mouse isn't held down, clear held props
        heldProps = {}
        return
    end
    
    -- Handle moving the held props
    for prop, _ in pairs(heldProps) do
        if IsValid(prop) then
            -- Get aim trace
            local eyeTrace = ply:GetEyeTrace()
            
            -- Get physgun attachment position
            local attachment = wep:GetAttachment(1)
            local startPos = attachment and attachment.Pos or ply:EyePos()
            
            -- Calculate new position
            local newPos = eyeTrace.HitPos
            
            -- Move the prop
            prop:SetPos(newPos)
            
            -- Update the connected light entity
            if IsValid(prop.lightEntity) then
                prop.lightEntity:SetPos(newPos)
                
                -- Force RTX light to update
                if prop.lightEntity.lastUpdatePos then
                    prop.lightEntity.lastUpdatePos = nil
                end
            end
        end
    end
end)

local function resetLightTracking()
    -- Clear all created lights
    clearRTXLights()
    
    -- Reset tracking variables
    table.Empty(createdLightPositions)
    last_entity_id = 0
    
    -- Reset Lua-side entity tracking
    for k in pairs(lightsBeingProcessed or {}) do
        lightsBeingProcessed[k] = nil
    end
    
    print("[Light2RTX] Light tracking data has been reset")
end

-- Add console commands
concommand.Add("light2rtx_process", function()
    batchCreateRTXLights()
end)

concommand.Add("light2rtx_clear", function()
    clearRTXLights()
end)

concommand.Add("light2rtx_toggle_visual", function()
    toggleVisualMode()
end)

concommand.Add("light2rtx_reset", function()
    resetLightTracking()
end)

-- Add context menu for lights
properties.Add("rtx_light_edit", {
    MenuLabel = "Edit RTX Light",
    Order = 500,
    MenuIcon = "icon16/lightbulb.png",
    
    Filter = function(self, ent, ply)
        if not IsValid(ent) then return false end
        return ent.RTXLight and IsValid(ent.lightEntity)
    end,
    
    Action = function(self, ent)
        if IsValid(ent.lightEntity) then
            ent.lightEntity:OpenPropertyMenu()
        end
    end
})

-- Add highlight for light entities when using physgun
hook.Add("PreDrawHalos", "Light2RTX_Highlight", function()
    if not visual_mode:GetBool() then return end
    
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    
    if IsValid(wep) and wep:GetClass() == "weapon_physgun" then
        -- Find all RTX light props
        local lightProps = {}
        for _, ent in ipairs(createdLights) do
            if IsValid(ent) and IsValid(ent.visualProp) then
                table.insert(lightProps, ent.visualProp)
            end
        end
        
        -- Add a halo around light props
        halo.Add(lightProps, Color(0, 255, 255), 2, 2, 1, true, true)
        
        -- Add a more prominent halo around held props
        local heldLightProps = {}
        for prop, _ in pairs(heldProps) do
            if IsValid(prop) then
                table.insert(heldLightProps, prop)
            end
        end
        
        if #heldLightProps > 0 then
            halo.Add(heldLightProps, Color(255, 255, 0), 4, 4, 2, true, true)
        end
    end
end)

hook.Add("Initialize", "Light2RTX_Reset", function()
    resetLightTracking()
end)

hook.Add("InitPostEntity", "Light2RTX_Reset", function()
    resetLightTracking()
end)

-- Make functions accessible to other scripts
Light2RTX = {
    Process = createRTXLights,
    Clear = clearRTXLights,
    ToggleVisual = toggleVisualMode
}

print("[Light2RTX] Loaded! Type 'light2rtx_process' in console to convert map lights to RTX lights")
print("[Light2RTX] Use 'light2rtx_clear' to remove all created lights")
print("[Light2RTX] Use 'light2rtx_toggle_visual' to toggle visual mode for moving lights with physgun")