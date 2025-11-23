
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
        emissiveIntensity = 10.0, -- Make it glow bright!
        emissiveColorConstant = { x = 1.0, y = 0.0, z = 0.0 } -- Red glow
    }
    
    -- Using Opaque extension for PBR parameters
    local opaqueInfo = {
        albedoConstant = { x = 1.0, y = 0.0, z = 0.0 },
        roughnessConstant = 0.5,
        metallicConstant = 0.0,
        emissiveIntensity = 10.0,
        emissiveColorConstant = { x = 1.0, y = 0.0, z = 0.0 }
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
    
    local s = 50 -- Half size - MUCH BIGGER (100 unit cube)
    -- Source coordinate system: X=Forward, Y=Left, Z=Up
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
    if testMaterialId then
        matHandle = testMaterialId
    end

    local meshInfo = {
        hash = 0xAA11BB22, -- New hash to avoid collisions
        surfaces = {
            {
                vertices = verts,
                indices = inds,
                material = 0 -- Use default material (0) to rule out material issues
            }
        }
    }
    
    if RemixMesh and RemixMesh.CreateMesh then
        testMeshId = RemixMesh.CreateMesh("TestCube", meshInfo)
        print("[RemixTest] Created test mesh: " .. tostring(testMeshId))
        
        -- Register as persistent mesh so Remix handles instancing automatically
        if RemixMesh.RegisterPersistentMesh then
            local success = RemixMesh.RegisterPersistentMesh(testMeshId)
            print("[RemixTest] Registered as persistent mesh: " .. tostring(success))
        end
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
        
        if not testMeshId then
            print("[RemixTest] ERROR: Failed to create mesh!")
            showTestMesh = false
            return
        end
        
        print("[RemixTest] Test mesh ENABLED (ID: " .. tostring(testMeshId) .. ")")
        
        -- Set initial transform with GAMEPLAY category flag (0x01)
        if testMeshId and RemixMesh.SetPersistentMeshTransform then
            local ply = LocalPlayer()
            if IsValid(ply) then
                local pos = ply:GetPos() + ply:GetForward() * 100 + Vector(0, 0, 50)
                local ang = Angle(0, 0, 0)
                
                local matrix = Matrix()
                matrix:SetTranslation(pos)
                matrix:SetAngles(ang)
                
                local transform = {
                    {matrix:GetField(1,1), matrix:GetField(1,2), matrix:GetField(1,3), matrix:GetField(1,4)},
                    {matrix:GetField(2,1), matrix:GetField(2,2), matrix:GetField(2,3), matrix:GetField(2,4)},
                    {matrix:GetField(3,1), matrix:GetField(3,2), matrix:GetField(3,3), matrix:GetField(3,4)}
                }
                
                -- Try category 0 (Default/World)
                local success = RemixMesh.SetPersistentMeshTransform(testMeshId, transform, 0, true) -- double-sided!
                print("[RemixTest] Set persistent mesh transform: " .. tostring(success))
                print("[RemixTest] Position: " .. tostring(pos))
            else
                print("[RemixTest] ERROR: No valid player!")
            end
        else
            print("[RemixTest] ERROR: SetPersistentMeshTransform not available!")
        end
    else
        print("[RemixTest] Test mesh DISABLED")
        -- Unregister persistent mesh
        if testMeshId and RemixMesh.UnregisterPersistentMesh then
            RemixMesh.UnregisterPersistentMesh(testMeshId)
        end
    end
end)

-- Update transform each frame with rotation (Remix handles the actual draw)
hook.Add("Think", "RemixTestMeshUpdate", function()
    if not showTestMesh or not testMeshId then return end
    if not RemixMesh or not RemixMesh.SetPersistentMeshTransform then return end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local pos = ply:GetPos() + ply:GetForward() * 100 + Vector(0, 0, 50)
    local ang = Angle(0, CurTime() * 50, 0)  -- Rotating animation
    
    local matrix = Matrix()
    matrix:SetTranslation(pos)
    matrix:SetAngles(ang)
    
    local transform = {
        {matrix:GetField(1,1), matrix:GetField(1,2), matrix:GetField(1,3), matrix:GetField(1,4)},
        {matrix:GetField(2,1), matrix:GetField(2,2), matrix:GetField(2,3), matrix:GetField(2,4)},
        {matrix:GetField(3,1), matrix:GetField(3,2), matrix:GetField(3,3), matrix:GetField(3,4)}
    }
    
    -- Try category 0 (Default/World)
    RemixMesh.SetPersistentMeshTransform(testMeshId, transform, 0, true) -- double-sided!
end)

-- NOTE: AutoInstancePersistentMeshes is called automatically by the native Present callback
-- registered in module.cpp, so no need to call RemixResource.Present() from Lua


