if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if SERVER then return end

-- Lightweight queuing/throttling layer for RemixLight operations to avoid
-- hitting native race conditions when too many ops happen in a single frame.

local CV_ENABLED = CreateClientConVar("rtx_light_queue_enabled", "1", true, false, "Enable RemixLight operation queuing")
local CV_OPS_PER_TICK = CreateClientConVar("rtx_light_ops_per_tick", "32", true, false, "Max RemixLight ops processed per tick")
local CV_COALESCE_UPDATES = CreateClientConVar("rtx_light_coalesce_updates", "1", true, false, "Coalesce multiple updates to same light in queue")

local queue = {}
local coalesceIndex = {
    sphere = {},
    rect = {},
    disk = {},
    distant = {},
    cylinder = {},
    dome = {},
}

local function canProcess()
    return CV_ENABLED:GetBool() and istable(RemixLight)
end

local function pushOp(op)
    -- Coalesce updates by lightId and type to keep only the most recent
    if CV_COALESCE_UPDATES:GetBool() and op.op == "update" and op.lightId then
        local typeMap = coalesceIndex[op.type]
        if typeMap then
            local idx = typeMap[op.lightId]
            if idx and queue[idx] and queue[idx].op == "update" then
                queue[idx] = op
                return
            end
        end
    end
    table.insert(queue, op)
    if op.op == "update" and op.lightId and coalesceIndex[op.type] then
        coalesceIndex[op.type][op.lightId] = #queue
    end
end

local function clearCoalesce(op)
    if op and op.op == "update" and op.lightId and coalesceIndex[op.type] then
        coalesceIndex[op.type][op.lightId] = nil
    end
end

local function processOne(op)
    if not istable(RemixLight) then return end
    if op.op == "create" then
        local id = nil
        if op.type == "sphere" and RemixLight.CreateSphere then
            id = RemixLight.CreateSphere(op.base, op.info, op.entityId or 0)
        elseif op.type == "rect" and RemixLight.CreateRect then
            id = RemixLight.CreateRect(op.base, op.info, op.entityId or 0)
        elseif op.type == "disk" and RemixLight.CreateDisk then
            id = RemixLight.CreateDisk(op.base, op.info, op.entityId or 0)
        elseif op.type == "distant" and RemixLight.CreateDistant then
            id = RemixLight.CreateDistant(op.base, op.info, op.entityId or 0)
        elseif op.type == "cylinder" and RemixLight.CreateCylinder then
            id = RemixLight.CreateCylinder(op.base, op.info, op.entityId or 0)
        elseif op.type == "dome" and RemixLight.CreateDome then
            id = RemixLight.CreateDome(op.base, op.info, op.entityId or 0)
        end
        if op.cb then
            pcall(op.cb, id)
        end
        return true
    elseif op.op == "update" then
        if op.type == "sphere" and RemixLight.UpdateSphere then
            RemixLight.UpdateSphere(op.base, op.info, op.lightId)
        elseif op.type == "rect" and RemixLight.UpdateRect then
            RemixLight.UpdateRect(op.base, op.info, op.lightId)
        elseif op.type == "disk" and RemixLight.UpdateDisk then
            RemixLight.UpdateDisk(op.base, op.info, op.lightId)
        elseif op.type == "distant" and RemixLight.UpdateDistant then
            RemixLight.UpdateDistant(op.base, op.info, op.lightId)
        elseif op.type == "cylinder" and RemixLight.UpdateCylinder then
            RemixLight.UpdateCylinder(op.base, op.info, op.lightId)
        elseif op.type == "dome" and RemixLight.UpdateDome then
            RemixLight.UpdateDome(op.base, op.info, op.lightId)
        end
        return true
    elseif op.op == "destroy" then
        if RemixLight.DestroyLight then
            RemixLight.DestroyLight(op.lightId)
        end
        return true
    end
end

hook.Add("Think", "RemixLightQueue_Process", function()
    if not canProcess() then return end
    local maxOps = math.max(0, math.floor(CV_OPS_PER_TICK:GetInt()))
    if maxOps <= 0 then return end
    local processed = 0
    local i = 1
    while processed < maxOps and i <= #queue do
        local op = table.remove(queue, 1)
        clearCoalesce(op)
        local ok = processOne(op)
        processed = processed + 1
        -- continue; i remains 1 since we remove from head
    end
end)

-- Public API
local RemixLightQueue = {}

function RemixLightQueue.CreateSphere(base, sphereInfo, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    -- This prevents race conditions with entity lifecycle
    if not istable(RemixLight) or not RemixLight.CreateSphere then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateSphere(base, sphereInfo, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.CreateRect(base, info, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    if not istable(RemixLight) or not RemixLight.CreateRect then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateRect(base, info, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.CreateDisk(base, info, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    if not istable(RemixLight) or not RemixLight.CreateDisk then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateDisk(base, info, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.CreateDistant(base, info, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    if not istable(RemixLight) or not RemixLight.CreateDistant then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateDistant(base, info, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.CreateCylinder(base, info, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    if not istable(RemixLight) or not RemixLight.CreateCylinder then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateCylinder(base, info, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.CreateDome(base, info, entityId, onCreated)
    -- Always create synchronously to ensure we get the light ID immediately
    if not istable(RemixLight) or not RemixLight.CreateDome then
        if onCreated then pcall(onCreated, nil) end
        return nil
    end
    
    local id = RemixLight.CreateDome(base, info, entityId or 0)
    if onCreated then pcall(onCreated, id) end
    return id
end

function RemixLightQueue.UpdateSphere(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateSphere then RemixLight.UpdateSphere(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "sphere", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.UpdateRect(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateRect then RemixLight.UpdateRect(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "rect", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.UpdateDisk(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateDisk then RemixLight.UpdateDisk(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "disk", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.UpdateDistant(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateDistant then RemixLight.UpdateDistant(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "distant", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.UpdateCylinder(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateCylinder then RemixLight.UpdateCylinder(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "cylinder", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.UpdateDome(base, info, lightId)
    if not CV_ENABLED:GetBool() or not istable(RemixLight) then
        if istable(RemixLight) and RemixLight.UpdateDome then RemixLight.UpdateDome(base, info, lightId) end
        return true
    end
    pushOp({ op = "update", type = "dome", base = base, info = info, lightId = lightId })
    return true
end

function RemixLightQueue.DestroyLight(lightId)
    -- Always destroy synchronously to ensure immediate cleanup
    if not istable(RemixLight) or not RemixLight.DestroyLight then
        return false
    end
    
    RemixLight.DestroyLight(lightId)
    return true
end

-- expose
_G.RemixLightQueue = RemixLightQueue


