if not CLIENT then return end

-- Material Merger - Reduces draw calls by merging similar materials
-- This reduces unique material switches which cause draw call overhead
-- Author: CR

local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

local convar_Enable = CreateClientConVar("rtx_merge_materials", "1", true, false, "Enable material merging to reduce draw calls")
local convar_Debug = CreateClientConVar("rtx_merge_materials_debug", "0", true, false, "Debug material merging")

-- Material equivalence groups - materials that can use the same visual
local materialGroups = {}
local groupLeaders = {} -- One canonical material per group

-- Hash materials by their visual properties
local function GetMaterialHash(mat)
    if not mat or not mat.GetName then return nil end
    
    local name = mat:GetName()
    -- Group by base texture if available
    local baseTex = mat.GetTexture and mat:GetTexture("$basetexture")
    local baseTexName = baseTex and baseTex.GetName and baseTex:GetName() or name
    
    -- Check shader
    local shader = mat.GetShader and mat:GetShader() or "unknown"
    
    -- Check key properties
    local translucent = mat.GetInt and mat:GetInt("$translucent") or 0
    local alpha = mat.GetInt and mat:GetInt("$alpha") or 0
    
    -- Create hash
    return string.format("%s|%s|%d|%d", shader, baseTexName, translucent, alpha)
end

-- Get or create material group leader
function GetMaterialGroupLeader(mat)
    if not convar_Enable:GetBool() then return mat end
    if not mat then return nil end
    
    local hash = GetMaterialHash(mat)
    if not hash then return mat end
    
    -- Check if we already have a leader for this group
    if groupLeaders[hash] then
        if convar_Debug:GetBool() then
            local originalName = mat:GetName()
            local leaderName = groupLeaders[hash]:GetName()
            if originalName ~= leaderName then
                print(string.format("[MaterialMerger] Redirecting '%s' -> '%s'", originalName, leaderName))
            end
        end
        return groupLeaders[hash]
    end
    
    -- This is the first material in this group, make it the leader
    groupLeaders[hash] = mat
    materialGroups[hash] = materialGroups[hash] or {}
    table.insert(materialGroups[hash], mat:GetName())
    
    if convar_Debug:GetBool() then
        print(string.format("[MaterialMerger] New group leader: '%s' (hash: %s)", mat:GetName(), hash))
    end
    
    return mat
end

-- Stats
hook.Add("Think", "MaterialMergerStats", function()
    if not convar_Debug:GetBool() then return end
    
    -- Print stats every 5 seconds
    local time = CurTime()
    if not MaterialMergerLastPrint or time - MaterialMergerLastPrint > 5 then
        MaterialMergerLastPrint = time
        
        local totalMaterials = 0
        local totalGroups = table.Count(materialGroups)
        for hash, group in pairs(materialGroups) do
            totalMaterials = totalMaterials + #group
        end
        
        if totalMaterials > 0 then
            local reduction = (1 - (totalGroups / totalMaterials)) * 100
            print(string.format("[MaterialMerger] %d materials -> %d groups (%.1f%% reduction)", 
                totalMaterials, totalGroups, reduction))
        end
    end
end)

-- Reset on map change
hook.Add("ShutDown", "MaterialMergerCleanup", function()
    table.Empty(materialGroups)
    table.Empty(groupLeaders)
end)

print("[Material Merger] Loaded - reduces draw calls by merging similar materials")

return {
    GetMaterialGroupLeader = GetMaterialGroupLeader,
    GetMaterialHash = GetMaterialHash
}
