-- Material Inspector
-- This tool allows you to inspect textures and materials of objects and world geometry you're looking at

local function GetMaterialInfo()
    local ply = LocalPlayer()
    local trace = ply:GetEyeTrace()
    
    print("\n====== Material Inspector ======")
    
    if trace.HitWorld then
        -- World geometry information
        print("Type: World Geometry")
        
        -- Get the texture name from the surface
        local textureName = trace.HitTexture
        print("Texture Name: " .. (textureName or "Unknown"))
        
        -- Get more detailed material information
        local matSys = Material(textureName)
        if matSys then
            print("Material Properties:")
            print("- Base Texture: " .. (matSys:GetTexture("$basetexture") and matSys:GetTexture("$basetexture"):GetName() or "None"))
            print("- Normal Map: " .. (matSys:GetTexture("$bumpmap") and matSys:GetTexture("$bumpmap"):GetName() or "None"))
            print("- Alpha: " .. tostring(matSys:GetFloat("$alpha") or 1))
            
            -- Check if it's a surfaceprop
            local surfaceProp = matSys:GetString("$surfaceprop")
            if surfaceProp and surfaceProp ~= "" then
                print("Surface Property: " .. surfaceProp)
            end
        end
        
        -- Print hit position for reference
        print(string.format("Hit Position: %.2f, %.2f, %.2f", trace.HitPos.x, trace.HitPos.y, trace.HitPos.z))
        
    elseif IsValid(trace.Entity) then
        -- Entity information
        print("Type: Entity")
        
        -- Get the entity's material
        local mat = trace.Entity:GetMaterial()
        local texturePath = ""
        
        if mat and mat ~= "" then
            local materialObj = Material(mat)
            if materialObj then
                texturePath = materialObj:GetTexture("$basetexture")
                if texturePath then
                    texturePath = texturePath:GetName()
                end
            end
        end
        
        -- Print material information
        print("Material: " .. (mat ~= "" and mat or "No custom material"))
        print("Base Texture: " .. (texturePath ~= "" and texturePath or "No texture path found"))
        
        -- Try to get model texture info
        local model = trace.Entity:GetModel()
        if model then
            print("Model: " .. model)
        end
        
        -- Get entity class
        print("Entity Class: " .. trace.Entity:GetClass())
        
        -- Print default material (if different from custom material)
        local defaultMat = trace.Entity:GetMaterials()
        if defaultMat and #defaultMat > 0 then
            print("\nDefault Materials:")
            for i, matPath in ipairs(defaultMat) do
                print(i .. ": " .. matPath)
            end
        end
    else
        print("No valid target found")
    end
    
    -- Print surface properties from the trace
    print("\nSurface Properties:")
    print("Surface Name: " .. (trace.SurfaceName or "Unknown"))
    print("Surface Properties: " .. (trace.SurfaceProps or "Unknown"))
    print("Surface Flags: " .. (trace.SurfaceFlags or "0"))
    
    print("==============================\n")
end

-- Register the console command
concommand.Add("inspect_material", GetMaterialInfo, nil, "Shows material and texture information of world geometry or entities you're looking at")