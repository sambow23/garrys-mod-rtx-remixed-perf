-- Water Texture Replacer
-- This script detects and replaces all water textures with a specified texture

local function FormatMaterialPath(path)
    path = path:gsub("^materials/", "")
    path = path:gsub("%.vmt$", "")
    return path
end

local function IsWaterMaterial(mat)
    if not mat or mat:IsError() then return false end

    local matName = mat:GetName():lower()
    
    -- Early exit for common non-water materials
    if matName:find("glass") or 
       matName:find("window") or 
       matName:find("mirror") or
       matName:find("tree") or
       matName:find("foliage") or
       matName:find("leaf") or
       matName:find("branch") or
       matName:find("forest") or
       matName:find("tools/toolsnodraw") or
       matName:find("cliff") then
        return false
    end

    if matName:match("^tools/") then
        return false
    end

    -- Only allow materials that explicitly have "water" in their name
    if not (matName:match("[^a-z]water[^a-z]") or matName:match("^water") or matName:match("water$")) then
        return false
    end

    local shader = mat:GetShader()
    if shader then
        shader = shader:lower()
        -- Early exit for sprite materials
        if shader:find("sprite") or shader:find("vertexlitgeneric") then
            return false
        end
    end

    -- Additional verification: must have either water surface property or water flag
    local isWater = false
    
    -- Check surface property
    local surfaceProp = mat:GetString("$surfaceprop")
    if surfaceProp and surfaceProp:lower() == "water" then
        isWater = true
    end

    -- Check water flag
    local flags = mat:GetInt("$flags")
    if flags and bit.band(flags, 0x2000) ~= 0 then
        isWater = true
    end

    return isWater
end

local function ValidateTexture(texturePath)
    texturePath = FormatMaterialPath(texturePath)
    local mat = Material(texturePath)
    
    if mat:IsError() then
        return false
    end
    
    local baseTexture = mat:GetTexture("$basetexture")
    if not baseTexture then
        return false
    end
    
    return true
end

-- Table to store water entities for continuous monitoring
local waterEntities = {}

local function ProcessWaterEntity(ent)
    if not IsValid(ent) then return end
    
    -- Force visibility
    ent:SetNoDraw(false)
    
    -- Remove any render flags that might hide the entity
    local oldRenderMode = ent:GetRenderMode()
    ent:SetRenderMode(RENDERMODE_NORMAL)
    
    -- Only set render bounds if the entity has a valid model
    if ent:GetModel() then
        local mins, maxs = ent:GetModelBounds()
        if mins and maxs and ent.SetRenderBounds then
            ent:SetRenderBounds(mins, maxs)
        end
    end
    
    -- Store the entity for continuous monitoring
    waterEntities[ent:EntIndex()] = ent
end

local function FixWaterNodraws()
    -- Clear old references
    table.Empty(waterEntities)
    
    -- Process all water-related entities
    local waterClasses = {
        "func_water_analog",
        "func_water",
        "water_lod_control",
        "func_water_detail",
        "water"
    }
    
    for _, class in ipairs(waterClasses) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            ProcessWaterEntity(ent)
        end
    end
    
    -- Find any entities with water materials
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            local model = ent:GetModel()
            if model and (model:lower():find("water") or model:lower():find("liquid")) then
                ProcessWaterEntity(ent)
            end
        end
    end
end

local function ReplaceWaterTextures(newTexturePath)
    local materials = game.GetWorld():GetMaterials()
    local replacedCount = 0
    
    newTexturePath = FormatMaterialPath(newTexturePath)
    
    if not ValidateTexture(newTexturePath) then
        return
    end
    
    local replacementMat = Material(newTexturePath)
    local replacementBaseTexture = replacementMat:GetTexture("$basetexture")
    
    if not replacementBaseTexture then
        return
    end

    for _, matPath in ipairs(materials) do
        if not matPath or matPath == "" then continue end
        
        local success, result = pcall(function()
            local mat = Material(matPath)
            if IsWaterMaterial(mat) then
                -- Create a new material with LightmappedGeneric shader
                local newMatName = "water_replace_" .. os.time() .. "_" .. math.random(1000, 9999)
                local newMat = Material(newMatName, "LightmappedGeneric", {
                    ["$basetexture"] = replacementBaseTexture:GetName()
                })
                
                -- Override the original material
                mat:SetTexture("$basetexture", replacementBaseTexture)
                mat:SetShader("LightmappedGeneric")
                
                -- Remove all other parameters
                local paramsToRemove = {
                    "$bumpmap", "$normalmap", "$envmap", "$reflectivity",
                    "$refracttexture", "$refracttint", "$refractamount",
                    "$fresnelreflection", "$bottommaterial", "$underwateroverlay",
                    "$dudvmap", "$fogcolor", "$fogstart", "$fogend"
                }
                
                for _, param in ipairs(paramsToRemove) do
                    mat:SetUndefined(param)
                end
                
                -- Set basic parameters
                mat:SetFloat("$alpha", 1)
                mat:SetInt("$translucent", 0)
                mat:SetInt("$nodraw", 0)
                mat:SetInt("$nofog", 0)
                
                replacedCount = replacedCount + 1
            end
        end)
    end
    
    -- Fix water nodraws
    FixWaterNodraws()
end

-- Configuration
local config = {
    replacementTexture = "dev/dev_monitor",
    initDelay = 1.0
}

-- Continuous monitoring of water entities
hook.Add("Think", "WaterTextureReplacer_Monitor", function()
    for entIdx, ent in pairs(waterEntities) do
        if IsValid(ent) and ent:GetNoDraw() then
            ent:SetNoDraw(false)
        end
    end
end)

-- Hook into map load to replace textures
hook.Add("InitPostEntity", "WaterTextureReplacer", function()
    timer.Simple(config.initDelay, function()
        ReplaceWaterTextures(config.replacementTexture)
    end)
end)

-- Hook into entity creation to catch any dynamically spawned water entities
hook.Add("OnEntityCreated", "WaterTextureReplacer_EntCreated", function(ent)
    if not IsValid(ent) then return end
    
    local class = ent:GetClass()
    if class:match("^func_water") or class == "water_lod_control" or 
       class == "water" or class:find("water") then
        timer.Simple(0, function()
            ProcessWaterEntity(ent)
        end)
    end
end)

-- Add console command to manually trigger replacement
concommand.Add("rtx_water_replace_textures", function(ply, cmd, args)
    local texture = args[1] or config.replacementTexture
    ReplaceWaterTextures(texture)
end)