if not CLIENT then return end

-- Static Prop Instancing - Drastically reduces draw calls for repeated props
-- Batches multiple instances of the same model into single draw calls
-- Author: CR

local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

local convar_Enable = CreateClientConVar("rtx_prop_instancing", "1", true, false, "Enable static prop instancing")
local convar_MaxInstances = CreateClientConVar("rtx_prop_instancing_max", "100", true, false, "Max instances per batch")
local convar_Debug = CreateClientConVar("rtx_prop_instancing_debug", "0", true, false, "Debug instancing")

-- Instance batches: [modelPath][materialName] = { matrices = {...}, colors = {...} }
local instanceBatches = {}
local batchStats = { models = 0, instances = 0, batches = 0 }
local lastFrameStats = { models = 0, instances = 0, batches = 0 } -- Preserved for HUD display

-- Clear batches each frame
local function ClearBatches()
    table.Empty(instanceBatches)
    batchStats = { models = 0, instances = 0, batches = 0 }
end

-- Add a prop instance to the batch
function AddPropInstance(modelPath, matrix, meshData, color)
    if not convar_Enable:GetBool() then return false end
    if not modelPath or not matrix or not meshData then return false end
    
    -- Initialize model batch
    instanceBatches[modelPath] = instanceBatches[modelPath] or {}
    local modelBatch = instanceBatches[modelPath]
    
    -- Group by material for efficient batching
    for _, meshInfo in ipairs(meshData.meshes) do
        local matName = meshInfo.material and meshInfo.material:GetName() or "unknown"
        
        modelBatch[matName] = modelBatch[matName] or {
            material = meshInfo.material,
            mesh = meshInfo.mesh,
            matrices = {},
            colors = {}
        }
        
        local batch = modelBatch[matName]
        
        -- Check if batch is full
        local maxInstances = convar_MaxInstances:GetInt()
        if #batch.matrices >= maxInstances then
            return false -- Batch full, caller should render directly
        end
        
        table.insert(batch.matrices, matrix)
        table.insert(batch.colors, color or Color(255, 255, 255))
        
        batchStats.instances = batchStats.instances + 1
    end
    
    return true -- Successfully batched
end

-- Render all batched instances
function RenderInstancedProps()
    if not convar_Enable:GetBool() then return end
    
    local drawCalls = 0
    
    for modelPath, materialBatches in pairs(instanceBatches) do
        batchStats.models = batchStats.models + 1
        
        for matName, batch in pairs(materialBatches) do
            if #batch.matrices > 0 then
                batchStats.batches = batchStats.batches + 1
                
                -- Render all instances in this batch
                render.SetMaterial(batch.material)
                
                for i = 1, #batch.matrices do
                    local mat = batch.matrices[i]
                    local col = batch.colors[i]
                    
                    if col then
                        render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
                    end
                    
                    cam.PushModelMatrix(mat)
                    batch.mesh:Draw()
                    cam.PopModelMatrix()
                    
                    if col then
                        render.SetColorModulation(1, 1, 1)
                    end
                end
                
                drawCalls = drawCalls + 1
            end
        end
    end
    
    if convar_Debug:GetBool() then
        print(string.format("[PropInstancing] %d models, %d instances, %d batches, %d draw calls", 
            batchStats.models, batchStats.instances, batchStats.batches, drawCalls))
    end
    
    -- Preserve stats for HUD display before clearing
    lastFrameStats.models = batchStats.models
    lastFrameStats.instances = batchStats.instances
    lastFrameStats.batches = batchStats.batches
    
    ClearBatches()
end

-- NOTE: Do NOT hook into render core here - the static prop renderer will call
-- ClearBatches() at start and RenderInstancedProps() at end of its own hook

-- Stats display
if RenderCore and RenderCore.RegisterStats then
    RenderCore.RegisterStats("PropInstancing", function()
        if not convar_Enable:GetBool() then return "Instancing: OFF" end
        return string.format("Instancing: %d models, %d instances -> %d batches", 
            lastFrameStats.models, lastFrameStats.instances, lastFrameStats.batches)
    end)
end

print("[Prop Instancing] Loaded - reduces draw calls for repeated props")

return {
    AddPropInstance = AddPropInstance,
    RenderInstancedProps = RenderInstancedProps,
    ClearBatches = ClearBatches
}
