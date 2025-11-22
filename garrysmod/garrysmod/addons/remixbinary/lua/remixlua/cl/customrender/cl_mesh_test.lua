
local showTestMesh = false
local testMeshId = nil
local testMaterialId = nil

local function CreateTestMaterial()
    if testMaterialId then return end
    
    local matInfo = {
        hash = 0x1234567890, -- Unique hash
        albedoConstant = { x = 1.0, y = 0.0, z = 0.0 }, -- Red
        roughnessConstant = 0.5,
        metallicConstant = 0.0,
        emissiveIntensity = 0.0
    }
    
    -- Using Opaque extension for PBR parameters
    local opaqueInfo = {
        albedoConstant = { x = 1.0, y = 0.0, z = 0.0 },
        roughnessConstant = 0.5,
        metallicConstant = 0.0
    }
    
    if RemixMaterial and RemixMaterial.CreateOpaqueMaterial then
        testMaterialId = RemixMaterial.CreateOpaqueMaterial("TestRedMat", matInfo, opaqueInfo)
        print("[RemixTest] Created test material: " .. tostring(testMaterialId))
    end
end

local function CreateTestCube()
    if testMeshId then return end
    
    CreateTestMaterial()
    
    local verts = {}
    local inds = {}
    
    -- Helper to add quad
    local function AddQuad(v1, v2, v3, v4, n)
        local base = #verts
        table.insert(verts, { pos = v1, normal = n, texcoord = {0, 0}, color = 0xFFFFFFFF })
        table.insert(verts, { pos = v2, normal = n, texcoord = {1, 0}, color = 0xFFFFFFFF })
        table.insert(verts, { pos = v3, normal = n, texcoord = {1, 1}, color = 0xFFFFFFFF })
        table.insert(verts, { pos = v4, normal = n, texcoord = {0, 1}, color = 0xFFFFFFFF })
        
        table.insert(inds, base + 0)
        table.insert(inds, base + 1)
        table.insert(inds, base + 2)
        
        table.insert(inds, base + 0)
        table.insert(inds, base + 2)
        table.insert(inds, base + 3)
    end
    
    local s = 10 -- Half size
    -- Front (+Y in Source?) Source coordinate system: X=Forward, Y=Left, Z=Up
    -- Let's define standard box
    -- Front (+X)
    AddQuad(Vector(s, -s, s), Vector(s, s, s), Vector(s, s, -s), Vector(s, -s, -s), Vector(1, 0, 0))
    -- Back (-X)
    AddQuad(Vector(-s, s, s), Vector(-s, -s, s), Vector(-s, -s, -s), Vector(-s, s, -s), Vector(-1, 0, 0))
    -- Left (+Y)
    AddQuad(Vector(s, s, s), Vector(-s, s, s), Vector(-s, s, -s), Vector(s, s, -s), Vector(0, 1, 0))
    -- Right (-Y)
    AddQuad(Vector(-s, -s, s), Vector(s, -s, s), Vector(s, -s, -s), Vector(-s, -s, -s), Vector(0, -1, 0))
    -- Top (+Z)
    AddQuad(Vector(s, s, s), Vector(s, -s, s), Vector(-s, -s, s), Vector(-s, s, s), Vector(0, 0, 1))
    -- Bottom (-Z)
    AddQuad(Vector(s, -s, -s), Vector(s, s, -s), Vector(-s, s, -s), Vector(-s, -s, -s), Vector(0, 0, -1))

    local matHandle = 0
    if testMaterialId and RemixMaterial then
        -- We need the handle, but CreateMaterial returns ID. 
        -- We need RemixMaterial.GetMaterialHandle(id) if exposed?
        -- MaterialManager has GetMaterialHandle but it's not exposed to Lua in material_lua_bindings.cpp?
        -- Checking material_lua_bindings.cpp... it DOES expose it? 
        -- No, it exposes GetTextureHash, etc.
        -- Ah, material field in surface expects a HANDLE.
        -- Wait, my Lua binding for CreateMesh takes a number and calls GetMaterialHandle.
        -- So passing testMaterialId is correct!
        matHandle = testMaterialId
    end

    local meshInfo = {
        hash = 0x99887766, -- Arbitrary hash
        surfaces = {
            {
                vertices = verts,
                indices = inds,
                material = matHandle
            }
        }
    }
    
    if RemixMesh and RemixMesh.CreateMesh then
        testMeshId = RemixMesh.CreateMesh("TestCube", meshInfo)
        print("[RemixTest] Created test mesh: " .. tostring(testMeshId))
    else
        print("[RemixTest] RemixMesh.CreateMesh not available")
    end
end

concommand.Add("remix_test_mesh_spawn", function()
    showTestMesh = not showTestMesh
    if showTestMesh then
        if not testMeshId then
            CreateTestCube()
        end
        print("[RemixTest] Test mesh ENABLED")
    else
        print("[RemixTest] Test mesh DISABLED")
    end
end)

hook.Add("PostDrawTranslucentRenderables", "RemixTestMeshDraw", function()
    if not showTestMesh or not testMeshId then return end
    
    if not RemixInstance or not RemixInstance.DrawInstance then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    -- Position in front of player
    local pos = ply:GetPos() + ply:GetForward() * 100 + Vector(0, 0, 50)
    local ang = Angle(0, CurTime() * 50, 0)
    
    -- Construct transform matrix (row-major 3x4)
    local matrix = Matrix()
    matrix:SetTranslation(pos)
    matrix:SetAngles(ang)
    
    local transform = {
        { matrix:GetField(1,1), matrix:GetField(1,2), matrix:GetField(1,3), matrix:GetField(1,4) },
        { matrix:GetField(2,1), matrix:GetField(2,2), matrix:GetField(2,3), matrix:GetField(2,4) },
        { matrix:GetField(3,1), matrix:GetField(3,2), matrix:GetField(3,3), matrix:GetField(3,4) }
    }
    
    local instanceInfo = {
        meshId = testMeshId,
        transform = transform,
        categoryFlags = 0,
        doubleSided = false
    }
    
    RemixInstance.DrawInstance(instanceInfo)
end)

