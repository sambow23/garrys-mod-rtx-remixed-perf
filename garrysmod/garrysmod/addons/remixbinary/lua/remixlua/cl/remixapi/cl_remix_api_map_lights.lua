local brightness_multiplier = CreateClientConVar("rtx_api_map_lights_brightness", "5.0", true, false, "Brightness multiplier for converted lights")
local size_multiplier = CreateClientConVar("rtx_api_map_lights_size", "5.0", true, false, "Size multiplier for converted lights")
local min_size = CreateClientConVar("rtx_api_map_lights_min_size", "100", true, false, "Minimum size for RTX lights")
local max_size = CreateClientConVar("rtx_api_map_lights_max_size", "1000", true, false, "Maximum size for RTX lights")
local visual_mode = CreateClientConVar("rtx_api_map_lights_visual", "0", true, false, "Show visible models for lights")
local debug_mode = CreateClientConVar("rtx_api_map_lights_debug", "0", true, false, "Enable debug messages")
local env_max_brightness = CreateClientConVar("rtx_api_map_lights_env_max_brightness", "0", true, false, "Max brightness (0-100 scale) for directional lights; 0 disables clamping")
local env_dir_flip = CreateClientConVar("rtx_api_map_lights_env_dir_flip", "0", true, false, "Flip directional vector for light_environment if needed")
local creation_delay = CreateClientConVar("rtx_api_map_lights_creation_delay", "0.0", true, false, "Delay between light creation in seconds")
local creation_batch_size = CreateClientConVar("rtx_api_map_lights_batch_size", "1", true, false, "Number of lights to create in each batch")
local creation_batch_delay = CreateClientConVar("rtx_api_map_lights_batch_delay", "0.0", true, false, "Delay between batches in seconds")
local pos_jitter = CreateClientConVar("rtx_api_map_lights_position_jitter", "1", true, false, "Add a small random offset to light positions to prevent conflicts")
local pos_jitter_amount = CreateClientConVar("rtx_api_map_lights_position_jitter_amount", "0.1", true, false, "Amount of random position offset")
local rect_rotation_x = CreateClientConVar("rtx_api_map_lights_rect_rotation_x", "0", true, false, "X rotation offset for rectangle and disk lights")
local rect_rotation_y = CreateClientConVar("rtx_api_map_lights_rect_rotation_y", "0", true, false, "Y rotation offset for rectangle and disk lights")
local rect_rotation_z = CreateClientConVar("rtx_api_map_lights_rect_rotation_z", "0", true, false, "Z rotation offset for rectangle and disk lights")

-- Auto-spawn controls
local autospawn = CreateClientConVar("rtx_api_map_lights_autospawn", "1", true, false, "Automatically convert map lights on map start")
local autospawn_delay = CreateClientConVar("rtx_api_map_lights_autospawn_delay", "1.5", true, false, "Delay (seconds) before auto-processing after map start")

-- Debug helpers
local debug_vis = CreateClientConVar("rtx_api_map_lights_debug_vis", "0", true, false, "Draw debug direction for spotlights")
local spot_dir_basis = CreateClientConVar("rtx_api_map_lights_dir_basis", "0", true, false, "Angles basis if no target: 0=F,1=-F,2=U,3=-U,4=R,5=-R")
local debug_beam_mat = Material("cable/physbeam")

-- Optional queue include to throttle RemixLight operations
if file.Exists("remixlua/cl/remixapi/cl_remix_light_queue.lua", "LUA") then
    include("remixlua/cl/remixapi/cl_remix_light_queue.lua")
end

-- Track created entities so we can clean them up
local createdLights = {}
local last_entity_id = 0
local createdLightPositions = {}
local lastSpawnedMap = ""

-- Light entity classes we want to detect
local lightClasses = {
    ["light"] = true,
    ["light_spot"] = true,
    ["light_dynamic"] = true,
    ["light_environment"] = true,
}

-- Mapping from Source light types to RTX light types
local rtxLightTypes = {
    ["light"] = 0, -- Sphere light
    ["light_dynamic"] = 0, -- Sphere light
    ["light_spot"] = 0, -- Disk light
    ["light_environment"] = 3, -- Distant (directional) light
}

-- Visual models to use for different light types
local lightModels = {
    ["light"] = "models/hunter/misc/sphere025x025.mdl",
    ["light_spot"] = "models/hunter/misc/sphere025x025.mdl",
    ["light_dynamic"] = "models/hunter/misc/sphere025x025.mdl",
    ["light_environment"] = "models/hunter/misc/sphere025x025.mdl",
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

-- Robustly parse Source entity angle fields. Returns Angle or nil, and a debug source tag
local function ParseEntityAngles(ent)
    local function applyEnvPitchOverride(ent, ang, tag)
        if ent and ent.classname == "light_environment" then
            local pOverride = tonumber(ent.pitch or ent._pitch)
            if pOverride then
                ang.p = -(pOverride)
                tag = tostring(tag or "") .. "+envpitch"
            end
        end
        return ang, tag
    end
    local angField = ent.angles or ent._angles
    -- Support string angles: "pitch yaw roll" or just "yaw"
    if type(angField) == "string" then
        local ax, ay, az = string.match(angField, "([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)")
        if ax and ay and az then
            -- Source convention: +pitch looks down -> negate when building Angle
            local a = Angle(-(tonumber(ax) or 0), tonumber(ay) or 0, tonumber(az) or 0)
            return applyEnvPitchOverride(ent, a, "angles_xyz")
        end
        local yawOnly = tonumber(angField)
        if yawOnly then
            local pitch = tonumber(ent.pitch or ent._pitch or 0)
            return Angle(-pitch, yawOnly, 0), "angles_yaw"
        end
    elseif type(angField) == "number" then
        -- Some entities may store yaw-only in 'angles' as a number
        local pitch = tonumber(ent.pitch or ent._pitch or 0)
        return Angle(-pitch, angField, 0), "angles_yaw_num"
    elseif (isvector and isvector(angField)) or type(angField) == "Vector" then
        -- Some BSP libs may expose angles as a Vector
        local a = Angle(-(angField.x or 0), angField.y or 0, angField.z or 0)
        return applyEnvPitchOverride(ent, a, "angles_vec")
    elseif istable(angField) and angField.x and angField.y and angField.z then
        local a = Angle(-(angField.x or 0), angField.y or 0, angField.z or 0)
        return applyEnvPitchOverride(ent, a, "angles_tbl")
    elseif istable(angField) then
        -- Support array-like tables: {pitch, yaw, roll}
        local ax, ay, az = tonumber(angField[1] or 0), tonumber(angField[2] or 0), tonumber(angField[3] or 0)
        if ax ~= 0 or ay ~= 0 or az ~= 0 then
            local a = Angle(-ax, ay, az)
            return applyEnvPitchOverride(ent, a, "angles_tbl_idx")
        end
    elseif (isangle and isangle(angField)) then
        -- GLua Angle userdata
        local a = Angle(-(angField.p or 0), angField.y or 0, angField.r or 0)
        return applyEnvPitchOverride(ent, a, "angles_glua")
    elseif type(angField) == "Angle" then
        -- Angle type without isangle available
        local a = Angle(-(angField.p or 0), angField.y or 0, angField.r or 0)
        return applyEnvPitchOverride(ent, a, "angles_type_Angle")
    elseif type(angField) == "userdata" then
        -- Generic userdata exposing p/y/r or pitch/yaw/roll
        local p = angField.p or angField.pitch
        local y = angField.y or angField.yaw
        local r = angField.r or angField.roll
        if p ~= nil or y ~= nil or r ~= nil then
            local a = Angle(-(tonumber(p) or 0), tonumber(y) or 0, tonumber(r) or 0)
            return applyEnvPitchOverride(ent, a, "angles_userdata")
        end
        -- Try parsing its string representation (e.g., "-16.000 45.000 0.000")
        local s = tostring(angField)
        if type(s) == "string" then
            local ax, ay, az = string.match(s, "([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)")
            if ax and ay and az then
                local a = Angle(-(tonumber(ax) or 0), tonumber(ay) or 0, tonumber(az) or 0)
                return applyEnvPitchOverride(ent, a, "angles_userdata_str")
            end
        end
    end
    -- Generic fallback: if we have any angles field at all, try parsing its string form
    if angField ~= nil then
        local s = tostring(angField)
        if type(s) == "string" then
            local ax, ay, az = string.match(s, "([%-%.%d]+)%s+([%-%.%d]+)%s+([%-%.%d]+)")
            if ax and ay and az then
                local a = Angle(-(tonumber(ax) or 0), tonumber(ay) or 0, tonumber(az) or 0)
                return applyEnvPitchOverride(ent, a, "angles_any_str")
            end
        end
    end
    -- Fallback to separate fields
    local hasPitch = ent.pitch or ent._pitch
    local yawRaw = ent.angle or ent._angle or ent.yaw or ent._yaw
    local hasYaw = yawRaw ~= nil
    if hasPitch or hasYaw then
        local pitch = tonumber(ent.pitch or ent._pitch or 0)
        local yaw = tonumber(yawRaw or 0)
        local tag = (yawRaw ~= nil and "pitch_yaw") or "pitch_only"
        return Angle(-pitch, yaw, 0), tag
    end
    return nil, "none"
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
        -- Read sun spread/diameter if available, else default to ~solar disc size
        local spread = tonumber(entity.sunspreadangle or entity._sunspreadangle or 0.53)
        lightProps.angularDiameter = spread or 0.53
        -- Derive directional angles (reuse robust parser)
        local a, src = ParseEntityAngles(entity)
        if debug_mode:GetBool() then
            local function tv(v)
                local t = type(v)
                if t == "table" then return "table" end
                if t == "Vector" or (isvector and isvector(v)) then
                    return string.format("Vector(%.2f,%.2f,%.2f)", v.x or 0, v.y or 0, v.z or 0)
                end
                return tostring(v)
            end
            print("[Light2RTX Debug] env raw angle fields:",
                "angles=", tv(entity.angles),
                "_angles=", tv(entity._angles),
                "angle=", tv(entity.angle),
                "_angle=", tv(entity._angle),
                "yaw=", tv(entity.yaw),
                "_yaw=", tv(entity._yaw),
                "pitch=", tv(entity.pitch),
                "_pitch=", tv(entity._pitch))
        end
        if a then
            lightProps.angles = a
            local dir = a:Forward()
            if env_dir_flip:GetBool() then dir = -dir end
            lightProps.direction = dir
            lightProps.debugSource = (src or "?") .. "+light_environment"
        end
    elseif entity.classname == "light_spot" then
        if debug_mode:GetBool() then
            -- Dump raw fields to diagnose yaw sourcing
            local function tv(v)
                local t = type(v)
                if t == "table" then return "table" end
                if t == "Vector" or (isvector and isvector(v)) then
                    return string.format("Vector(%.2f,%.2f,%.2f)", v.x or 0, v.y or 0, v.z or 0)
                end
                return tostring(v)
            end
            print("[Light2RTX Debug] spot raw angle fields:",
                "angles=", tv(entity.angles),
                "_angles=", tv(entity._angles),
                "angle=", tv(entity.angle),
                "_angle=", tv(entity._angle),
                "yaw=", tv(entity.yaw),
                "_yaw=", tv(entity._yaw),
                "pitch=", tv(entity.pitch),
                "_pitch=", tv(entity._pitch))
        end
        -- For spotlights, extract cone parameters
        local coneAngle = tonumber(entity.cone or entity._cone or 45)
        lightProps.coneAngle = coneAngle
        lightProps.coneSoftness = 0.2 -- Default softness
        
        -- Adjust rect dimensions based on cone angle
        -- Wider cone = wider rectangle
        local aspectRatio = 1.0 -- Default aspect ratio for the rectangle
        lightProps.rectWidth = size * aspectRatio
        lightProps.rectHeight = size
        
        -- Derive spotlight angles and direction consistently (Source: +pitch looks down)
        local a, src = ParseEntityAngles(entity)
        if a then
            lightProps.angles = a
            -- Provide a direction immediately; later logic will respect this if no target exists
            lightProps.direction = a:Forward()
            lightProps.shapingEnabled = true
            lightProps.debugSource = src .. "+getLightProperties"
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
    
    -- Build a map of targetname -> position for aiming spotlights at targets
    local nameToPos = {}
    for _, e in pairs(bsp:GetEntities()) do
        local tn = e.targetname or e._targetname
        if tn then
            local p = StringToVector(e.origin)
            nameToPos[tn] = p
        end
    end
    
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
            
            -- Derive direction for spotlights from target or angles when available
            if ent.classname == "light_spot" then
                local tgt = ent.target or ent._target
                if tgt and nameToPos[tgt] then
                    local dirVec = (nameToPos[tgt] - pos):GetNormalized()
                    lightProps.direction = dirVec
                    lightProps.shapingEnabled = true
                    lightProps.debugSource = "target"
                elseif not lightProps.direction then
                    -- Fallback: parse angles only if not already set by getLightProperties
                    local a, src = ParseEntityAngles(ent)
                    if a then
                        local f = a:Forward()
                        lightProps.direction = f
                        lightProps.shapingEnabled = true
                        lightProps.angles = a
                        lightProps.debugSource = src
                    end
                end
            end
            
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

-- Create a Remix light using the newer RemixLight Lua API (sphere for now)
local function createRemixLight(pos, color, brightness, size, lightType, lightProps, angles, visualProp, classname)
    -- Generate a unique position key with some tolerance (0.1 units)
    local posKey = string.format("%.1f_%.1f_%.1f", pos.x, pos.y, pos.z)
    if createdLightPositions[posKey] then
        print("[Light2RTX] Skipping duplicate light at " .. posKey)
        return nil
    end
    createdLightPositions[posKey] = true

    if not istable(RemixLight) then
        print("[Light2RTX] RemixLight API not available")
        createdLightPositions[posKey] = nil
        return nil
    end

    local entityId = getUniqueEntityID()

    -- Base light definition: compute radiance from color and brightness (0-100)
    local appliedBrightness = tonumber(brightness) or 100
    if classname == "light_environment" then
        local maxEnv = tonumber(env_max_brightness:GetFloat()) or 0
        if maxEnv > 0 then
            appliedBrightness = math.min(appliedBrightness, maxEnv)
        end
    end
    local scale = appliedBrightness / 100.0
    local base = {
        hash = tonumber(util.CRC(string.format("maplight_%s", posKey))) or entityId,
        radiance = { x = color.r * scale, y = color.g * scale, z = color.b * scale },
    }

    -- Direction from angles if present
    -- Default to pointing down; override with explicit direction when known
    local dir = Vector(0, 0, -1)
    -- If a spotlight direction was derived, prefer it
    if lightProps and lightProps.direction then
        local d = lightProps.direction
        dir = Vector(d.x, d.y, d.z)
    elseif angles then
        local baseAngles = angles
        baseAngles.x = baseAngles.x + rect_rotation_x:GetFloat()
        baseAngles.y = baseAngles.y + rect_rotation_y:GetFloat()
        baseAngles.z = baseAngles.z + rect_rotation_z:GetFloat()
        local basis = spot_dir_basis:GetInt()
        if basis == 0 then dir = baseAngles:Forward()
        elseif basis == 1 then dir = -baseAngles:Forward()
        elseif basis == 2 then dir = baseAngles:Up()
        elseif basis == 3 then dir = -baseAngles:Up()
        elseif basis == 4 then dir = baseAngles:Right()
        elseif basis == 5 then dir = -baseAngles:Right()
        else dir = baseAngles:Forward() end
    end

    -- Special-case directional: use Distant lights
    local lightId = nil
    if classname == "light_environment" then
        local distant = {
            direction = { x = dir.x, y = dir.y, z = dir.z },
            angularDiameterDegrees = (lightProps and tonumber(lightProps.angularDiameter)) or 0.53,
            volumetricRadianceScale = 1.0,
        }
        if istable(RemixLightQueue) and RemixLightQueue.CreateDistant then
            lightId = RemixLightQueue.CreateDistant(base, distant, entityId)
        elseif RemixLight.CreateDistant then
            lightId = RemixLight.CreateDistant(base, distant, entityId)
        end
    else
        -- Sphere info as a reasonable default representation
        local sphere = {
            position = { x = pos.x, y = pos.y, z = pos.z },
            radius = tonumber(size) or 200,
            volumetricRadianceScale = 1.0,
        }
        if lightProps and lightProps.shapingEnabled then
            sphere.shaping = {
                direction = { x = dir.x, y = dir.y, z = dir.z },
                coneAngleDegrees = tonumber(lightProps.coneAngle) or 45.0,
                coneSoftness = tonumber(lightProps.coneSoftness) or 0.2,
                focusExponent = 1.0,
            }
            DebugPrint(string.format("Create spot dir=(%.2f, %.2f, %.2f) src=%s", dir.x, dir.y, dir.z, tostring(lightProps.debugSource)))
        end

        -- Create the light (synchronous) and get its id
        if istable(RemixLightQueue) and RemixLightQueue.CreateSphere then
            lightId = RemixLightQueue.CreateSphere(base, sphere, entityId)
        elseif RemixLight.CreateSphere then
            lightId = RemixLight.CreateSphere(base, sphere, entityId)
        end
    end

    if not lightId or lightId == 0 then
        print("[Light2RTX] Failed to create Remix light")
        createdLightPositions[posKey] = nil
        return nil
    end

    -- Link optional visual prop
    if IsValid(visualProp) then
        visualProp.RTXLight = true
    end

    local entry = {
        id = lightId,
        entityId = entityId,
        type = (classname == "light_environment") and "distant" or "sphere",
        pos = pos,
        color = color,
        size = size,
        shapingEnabled = lightProps and lightProps.shapingEnabled or false,
        classname = classname,
        visualProp = visualProp,
        -- Debug/inspection fields
        angles = angles,
        direction = dir,
    }
    return entry
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
                
                -- Create the Remix light using new API
                local entry = createRemixLight(
                    light.pos,
                    light.color,
                    light.brightness,
                    light.size,
                    light.lightType or 0,
                    light.lightProps,
                    light.angles,
                    visualProp,
                    light.classname
                )
                
                if entry and entry.id then
                    table.insert(createdLights, entry)
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
    for _, entry in ipairs(createdLights) do
        if entry.visualProp and IsValid(entry.visualProp) then
            entry.visualProp:Remove()
        end
        if istable(RemixLight) and RemixLight.DestroyLight and entry.id then
            RemixLight.DestroyLight(entry.id)
        end
    end
    createdLights = {}
    print("[Light2RTX] Cleared all RTX lights")
end

-- Toggle light visibility
local function toggleVisualMode()
    local newValue = not visual_mode:GetBool()
    RunConsoleCommand("rtx_api_map_lights_visual", newValue and "1" or "0")
    
    -- If turning off, remove all visual props
    if not newValue then
        for _, entry in ipairs(createdLights) do
            if entry.visualProp and IsValid(entry.visualProp) then
                entry.visualProp:Remove()
                entry.visualProp = nil
            end
        end
    else
        -- If turning on, create visual props for existing lights
        for _, entry in ipairs(createdLights) do
            if (not entry.visualProp) or (entry.visualProp and not IsValid(entry.visualProp)) then
                local visualProp = createVisualProp(entry.pos, entry.color, "default")
                if IsValid(visualProp) then
                    entry.visualProp = visualProp
                end
            end
        end
    end
    
    print("[Light2RTX] Visual mode " .. (newValue and "enabled" or "disabled"))
end

-- PhysGun functionality
local heldProps = {}

-- Enable drawing of beams
hook.Add("PostDrawOpaqueRenderables", "rtx_api_map_lights_DrawPhysBeams", function()
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
hook.Add("PhysgunPickup", "rtx_api_map_lights_PhysgunPickup", function(ply, ent)
    if ent.RTXLight then
        heldProps[ent] = true
        DebugPrint("Light prop picked up with physgun")
        return true
    end
end)

-- Hook for dropping clientside props with the physgun
hook.Add("PhysgunDrop", "rtx_api_map_lights_PhysgunDrop", function(ply, ent)
    if ent.RTXLight then
        heldProps[ent] = nil
        DebugPrint("Light prop dropped with physgun")
        return true
    end
end)

-- Handle moving the held props with the physgun
hook.Add("Think", "rtx_api_map_lights_PhysgunThink", function()
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
            
            -- Update the connected Remix light
            if prop.RTXLight then
                -- Find the entry that owns this prop
                for _, entry in ipairs(createdLights) do
                    if entry.visualProp == prop and entry.type == "sphere" and entry.id then
                        entry.pos = newPos
                        if istable(RemixLight) and RemixLight.UpdateSphereFields then
                            RemixLight.UpdateSphereFields(entry.id, { position = { x = newPos.x, y = newPos.y, z = newPos.z } })
                        elseif istable(RemixLightQueue) and RemixLightQueue.UpdateSphere then
                            -- Fallback: build minimal base+info from cached entry, only include shaping if enabled
                            local base = { hash = tonumber(util.CRC("upd_" .. tostring(entry.id))) or entry.entityId, radiance = { x = entry.color.r, y = entry.color.g, z = entry.color.b } }
                            local info = { position = { x = newPos.x, y = newPos.y, z = newPos.z }, radius = entry.size or 200, volumetricRadianceScale = 1.0 }
                            if entry.shapingEnabled then
                                info.shaping = { direction = { x = 0, y = 0, z = -1 }, coneAngleDegrees = 45.0, coneSoftness = 0.2, focusExponent = 1.0 }
                            end
                            RemixLightQueue.UpdateSphere(base, info, entry.id)
                        end
                        break
                    end
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
concommand.Add("rtx_api_map_lights_process", function()
    batchCreateRTXLights()
end)

concommand.Add("rtx_api_map_lights_clear", function()
    clearRTXLights()
end)

concommand.Add("rtx_api_map_lights_toggle_visual", function()
    toggleVisualMode()
end)

concommand.Add("rtx_api_map_lights_reset", function()
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
hook.Add("PreDrawHalos", "rtx_api_map_lights_Highlight", function()
    if not visual_mode:GetBool() then return end
    
    local ply = LocalPlayer()
    local wep = ply:GetActiveWeapon()
    
    if IsValid(wep) and wep:GetClass() == "weapon_physgun" then
        -- Find all RTX light props
        local lightProps = {}
        for _, entry in ipairs(createdLights) do
            if entry.visualProp and IsValid(entry.visualProp) then
                table.insert(lightProps, entry.visualProp)
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

-- Optional debug direction lines for spotlights and directional lights
hook.Add("PostDrawTranslucentRenderables", "rtx_api_map_lights_DebugDir", function(depth, sky)
    if not debug_vis:GetBool() then return end
    -- Use a textured beam material (fixed-function safe)
    render.SetMaterial(debug_beam_mat)
    for _, entry in ipairs(createdLights) do
        if entry.pos then
            local isSpot = entry.classname == "light_spot" and entry.shapingEnabled
            local isDistant = entry.type == "distant" or entry.classname == "light_environment"
            if isSpot or isDistant then
                local startPos = entry.pos
                local dir = Vector(0, 0, -1)
                -- Prefer stored direction when present
                if entry.direction and isvector(entry.direction) then
                    dir = entry.direction
                elseif entry.angles then
                    dir = entry.angles:Forward()
                end
                local length = isDistant and 1024 or 128
                local endPos = startPos + dir * length
                local col = isDistant and Color(0, 200, 255, 220) or Color(255, 0, 0, 220)
                local beamWidth = 1
                if isDistant then beamWidth = 2 end
                render.DrawBeam(startPos, endPos, beamWidth, 0, 1, col)
            end
        end
    end
end)

hook.Add("Initialize", "rtx_api_map_lights_Reset", function()
    resetLightTracking()
end)

hook.Add("InitPostEntity", "rtx_api_map_lights_Reset", function()
    resetLightTracking()
end)

-- Auto process once per map after a short delay (to ensure player/entities are ready)
hook.Add("InitPostEntity", "rtx_api_map_lights_AutoProcess", function()
    if not autospawn:GetBool() then return end
    local map = game.GetMap() or ""
    if map == "" or map == lastSpawnedMap then return end
    local delay = math.max(0, autospawn_delay:GetFloat())
    timer.Simple(delay, function()
        if not autospawn:GetBool() then return end
        local lp = LocalPlayer and LocalPlayer() or nil
        if not IsValid(lp) then return end
        lastSpawnedMap = map
        batchCreateRTXLights()
    end)
end)

-- Make functions accessible to other scripts
Light2RTX = {
    Process = batchCreateRTXLights,
    Clear = clearRTXLights,
    ToggleVisual = toggleVisualMode
}

print("[Light2RTX] Loaded! Use 'rtx_api_map_lights_process' to convert map lights to RTX lights")
print("[Light2RTX] Use 'rtx_api_map_lights_clear' to remove all created lights")
print("[Light2RTX] Use 'rtx_api_map_lights_toggle_visual' to toggle visual mode for moving lights with physgun")