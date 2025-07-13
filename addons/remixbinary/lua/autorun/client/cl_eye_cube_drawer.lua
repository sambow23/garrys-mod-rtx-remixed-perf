-- -- Eye Cube Drawer
-- -- Draws cubes at NPC/ragdoll eye positions for debugging/visualization

-- local eye_cube_enabled = CreateClientConVar("rtx_eye_cube_enabled", "0", true, false, "Enable drawing cubes at NPC/ragdoll eye positions")
-- local eye_cube_size = CreateClientConVar("rtx_eye_cube_size", "2", true, false, "Size of the eye cubes")
-- local eye_cube_color_r = CreateClientConVar("rtx_eye_cube_color_r", "255", true, false, "Red component of eye cube color")
-- local eye_cube_color_g = CreateClientConVar("rtx_eye_cube_color_g", "0", true, false, "Green component of eye cube color")
-- local eye_cube_color_b = CreateClientConVar("rtx_eye_cube_color_b", "0", true, false, "Blue component of eye cube color")
-- local eye_cube_alpha = CreateClientConVar("rtx_eye_cube_alpha", "200", true, false, "Alpha/transparency of eye cubes")
-- local eye_cube_individual = CreateClientConVar("rtx_eye_cube_individual", "1", true, false, "Draw individual left/right eye cubes (1) or single center cube (0)")
-- local eye_cube_separation = CreateClientConVar("rtx_eye_cube_separation", "3", true, false, "Distance between individual eye cubes")
-- local eye_cube_forward_offset = CreateClientConVar("rtx_eye_cube_forward_offset", "3", true, false, "Forward offset from head bone for eye positioning")
-- local eye_cube_right_offset = CreateClientConVar("rtx_eye_cube_right_offset", "0", true, false, "Right offset from head bone for eye positioning")
-- local eye_cube_up_offset = CreateClientConVar("rtx_eye_cube_up_offset", "2", true, false, "Up offset from head bone for eye positioning")
-- local eye_cube_angle_pitch = CreateClientConVar("rtx_eye_cube_angle_pitch", "0", true, false, "Pitch angle correction for head bone orientation")
-- local eye_cube_angle_yaw = CreateClientConVar("rtx_eye_cube_angle_yaw", "-90", true, false, "Yaw angle correction for head bone orientation")
-- local eye_cube_angle_roll = CreateClientConVar("rtx_eye_cube_angle_roll", "0", true, false, "Roll angle correction for head bone orientation")
-- local eye_cube_bone_priority = CreateClientConVar("rtx_eye_cube_bone_priority", "1", true, false, "Bone priority: 0=Head bone only, 1=Eye bones preferred, 2=Eye bones only")
-- local eye_cube_draw_mode = CreateClientConVar("rtx_eye_cube_draw_mode", "0", true, false, "Draw mode: 0=Dev texture cubes, 1=Generic iris, 2=Model eyeball, 3=Simple wireframe")
-- local eye_cube_iris_size = CreateClientConVar("rtx_eye_cube_iris_size", "1.5", true, false, "Size multiplier for iris texture")
-- local eye_cube_auto_detect = CreateClientConVar("rtx_eye_cube_auto_detect", "1", true, false, "Auto-detect model eyeball materials")
-- local eye_cube_prefer_iris = CreateClientConVar("rtx_eye_cube_prefer_iris", "1", true, false, "Prefer $iris texture over full eyeball texture when available")

-- -- Function to check if an entity should have eye cubes drawn
-- local function ShouldDrawEyeCube(ent)
--     if not IsValid(ent) then return false end
    
--     -- Check if it's an NPC or ragdoll
--     if ent:IsNPC() or ent:GetClass() == "prop_ragdoll" then
--         return true
--     end
    
--     -- Also check for players if desired
--     if ent:IsPlayer() and ent ~= LocalPlayer() then
--         return true
--     end
    
--     return false
-- end

-- -- Materials for different draw modes
-- local devTextureMaterial = Material("dev/dev_measuregeneric01")
-- local irisMaterial = Material("models/alyx/eyeball_l") -- Common Source engine iris texture
-- local wireframeMaterial = Material("models/wireframe")

-- -- Cache for model eyeball materials
-- local modelEyeballCache = {}

-- -- Cache for created iris materials
-- local irisMatCache = {}

-- -- Cache for original eyeball materials (for restoration)
-- local originalEyeballMaterials = {}

-- -- Cache for eyeball material indices
-- local eyeballMaterialIndices = {}

-- -- Function to extract $iris texture from a material and create a VertexLitGeneric version
-- local function GetIrisTextureFromMaterial(material)
--     if not material or material:IsError() then return nil end
    
--     -- Try to get the $iris parameter from the material
--     local irisTexture = material:GetString("$iris")
--     if irisTexture and irisTexture ~= "" then
--         -- Check cache first
--         if irisMatCache[irisTexture] then
--             return irisMatCache[irisTexture]
--         end
        
--         -- Create a new VertexLitGeneric material using the iris texture
--         local irisMatName = "rtx_eye_iris_" .. string.gsub(irisTexture, "[^%w]", "_")
--         local irisMat = CreateMaterial(irisMatName, "VertexLitGeneric", {
--             ["$basetexture"] = irisTexture,
--             ["$model"] = 1,
--             ["$nocull"] = 1,
--             ["$halflambert"] = 1,
--             ["$nodecal"] = 1
--         })
        
--         if irisMat and not irisMat:IsError() then
--             -- Cache the created material
--             irisMatCache[irisTexture] = irisMat
--             return irisMat
--         end
--     end
    
--     return nil
-- end

-- -- Function to detect eyeball materials from a model
-- local function GetModelEyeballMaterial(ent)
--     if not IsValid(ent) then return nil, nil end
    
--     local model = ent:GetModel()
--     if not model then return nil, nil end
    
--     -- Check cache first
--     if modelEyeballCache[model] then
--         return modelEyeballCache[model].eyeball, modelEyeballCache[model].iris
--     end
    
--     -- Common eyeball material name patterns
--     local eyePatterns = {
--         "eye", "eyeball", "iris", "pupil", "cornea",
--         "eye_l", "eye_r", "eyeball_l", "eyeball_r",
--         "left_eye", "right_eye", "lefteye", "righteye"
--     }
    
--     -- Get all materials from the model
--     local materials = ent:GetMaterials()
--     local foundEyeMaterial = nil
--     local foundIrisMaterial = nil
    
--     for _, materialPath in ipairs(materials) do
--         local materialName = string.lower(materialPath)
        
--         -- Check if material name contains eye-related keywords
--         for _, pattern in ipairs(eyePatterns) do
--             if string.find(materialName, pattern, 1, true) then
--                 -- Try to load the material
--                 local mat = Material(materialPath)
--                 if mat and not mat:IsError() then
--                     foundEyeMaterial = mat
                    
--                     -- Try to extract $iris texture from this material
--                     foundIrisMaterial = GetIrisTextureFromMaterial(mat)
                    
--                     break
--                 end
--             end
--         end
        
--         if foundEyeMaterial then break end
--     end
    
--     -- If no specific eye material found, try to find any material with "models/" prefix
--     if not foundEyeMaterial then
--         for _, materialPath in ipairs(materials) do
--             if string.StartWith(string.lower(materialPath), "models/") then
--                 local mat = Material(materialPath)
--                 if mat and not mat:IsError() then
--                     -- Use the first valid model material as fallback
--                     foundEyeMaterial = mat
                    
--                     -- Still try to extract $iris texture
--                     foundIrisMaterial = GetIrisTextureFromMaterial(mat)
                    
--                     break
--                 end
--             end
--         end
--     end
    
--     -- Cache the result (even if nil)
--     modelEyeballCache[model] = {
--         eyeball = foundEyeMaterial,
--         iris = foundIrisMaterial
--     }
    
--     return foundEyeMaterial, foundIrisMaterial
-- end

-- -- Function to find eyeball material indices on a model
-- local function GetEyeballMaterialIndices(ent)
--     if not IsValid(ent) then return {} end
    
--     local model = ent:GetModel()
--     if not model then return {} end
    
--     -- Check cache first
--     if eyeballMaterialIndices[model] then
--         return eyeballMaterialIndices[model]
--     end
    
--     local indices = {}
--     local materials = ent:GetMaterials()
    
--     -- Common eyeball material name patterns
--     local eyePatterns = {
--         "eye", "eyeball", "iris", "pupil", "cornea",
--         "eye_l", "eye_r", "eyeball_l", "eyeball_r",
--         "left_eye", "right_eye", "lefteye", "righteye"
--     }
    
--     for i, materialPath in ipairs(materials) do
--         local materialName = string.lower(materialPath)
        
--         -- Check if material name contains eye-related keywords
--         for _, pattern in ipairs(eyePatterns) do
--             if string.find(materialName, pattern, 1, true) then
--                 -- Store the material index (0-based for SetSubMaterial)
--                 table.insert(indices, i - 1)
--                 break
--             end
--         end
--     end
    
--     -- Cache the result
--     eyeballMaterialIndices[model] = indices
    
--     return indices
-- end

-- -- Function to apply iris texture to model's eyeball materials
-- local function ApplyIrisToModelEyeball(ent)
--     if not IsValid(ent) then return end
    
--     local model = ent:GetModel()
--     if not model then return end
    
--     -- Get the iris material to apply
--     local eyeballMat, irisMat = GetModelEyeballMaterial(ent)
--     local materialToUse = nil
    
--     if eye_cube_prefer_iris:GetBool() and irisMat then
--         materialToUse = irisMat
--     elseif eyeballMat then
--         materialToUse = eyeballMat
--     else
--         materialToUse = irisMaterial -- Fallback to generic iris
--     end
    
--     -- Get eyeball material indices
--     local indices = GetEyeballMaterialIndices(ent)
    
--     if #indices > 0 then
--         -- Store original materials if not already stored
--         if not originalEyeballMaterials[ent] then
--             originalEyeballMaterials[ent] = {}
--             for _, index in ipairs(indices) do
--                 originalEyeballMaterials[ent][index] = ent:GetSubMaterial(index)
--             end
--         end
        
--         -- Apply iris material to all eyeball submaterials
--         for _, index in ipairs(indices) do
--             ent:SetSubMaterial(index, materialToUse:GetName())
--         end
--     end
-- end

-- -- Function to restore original eyeball materials
-- local function RestoreOriginalEyeballMaterials(ent)
--     if not IsValid(ent) then return end
    
--     if originalEyeballMaterials[ent] then
--         for index, originalMaterial in pairs(originalEyeballMaterials[ent]) do
--             ent:SetSubMaterial(index, originalMaterial)
--         end
--         originalEyeballMaterials[ent] = nil
--     end
-- end

-- -- Function to draw a solid cube with dev texture
-- local function DrawDevTextureCube(pos, ang, size, color)
--     local halfSize = size * 0.5
    
--     -- Set up rendering
--     render.SetMaterial(devTextureMaterial)
--     render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
--     render.SetBlend(color.a / 255)
    
--     -- Create a matrix for positioning and rotation
--     local matrix = Matrix()
--     matrix:SetTranslation(pos)
--     matrix:SetAngles(ang)
--     matrix:SetScale(Vector(size, size, size))
    
--     -- Push the matrix
--     cam.PushModelMatrix(matrix)
    
--     -- Draw cube faces using quads
--     render.DrawQuadEasy(Vector(0, 0, halfSize), Vector(0, 0, 1), halfSize, halfSize) -- Top
--     render.DrawQuadEasy(Vector(0, 0, -halfSize), Vector(0, 0, -1), halfSize, halfSize) -- Bottom
--     render.DrawQuadEasy(Vector(halfSize, 0, 0), Vector(1, 0, 0), halfSize, halfSize) -- Right
--     render.DrawQuadEasy(Vector(-halfSize, 0, 0), Vector(-1, 0, 0), halfSize, halfSize) -- Left
--     render.DrawQuadEasy(Vector(0, halfSize, 0), Vector(0, 1, 0), halfSize, halfSize) -- Front
--     render.DrawQuadEasy(Vector(0, -halfSize, 0), Vector(0, -1, 0), halfSize, halfSize) -- Back
    
--     -- Pop the matrix
--     cam.PopModelMatrix()
    
--     -- Reset render state
--     render.SetColorModulation(1, 1, 1)
--     render.SetBlend(1)
-- end

-- -- Function to draw an iris texture (flat circle facing forward)
-- local function DrawIrisTexture(pos, ang, size, color)
--     local irisSize = size * eye_cube_iris_size:GetFloat()
    
--     -- Set up rendering
--     render.SetMaterial(irisMaterial)
--     render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
--     render.SetBlend(color.a / 255)
    
--     -- Draw a quad facing the forward direction
--     local forward = ang:Forward()
--     local right = ang:Right()
--     local up = ang:Up()
    
--     -- Create iris quad vertices
--     local halfSize = irisSize * 0.5
--     local v1 = pos - right * halfSize - up * halfSize
--     local v2 = pos + right * halfSize - up * halfSize
--     local v3 = pos + right * halfSize + up * halfSize
--     local v4 = pos - right * halfSize + up * halfSize
    
--     -- Draw the iris as a textured quad
--     render.DrawQuad(v1, v2, v3, v4)
    
--     -- Reset render state
--     render.SetColorModulation(1, 1, 1)
--     render.SetBlend(1)
-- end

-- -- Function to draw model's eyeball texture
-- local function DrawModelEyeball(ent, pos, ang, size, color)
--     local eyeballMaterial = nil
--     local irisMat = nil
    
--     if eye_cube_auto_detect:GetBool() then
--         eyeballMaterial, irisMat = GetModelEyeballMaterial(ent)
--     end
    
--     -- Choose which material to use based on preference and availability
--     local materialToUse = nil
--     if eye_cube_prefer_iris:GetBool() and irisMat then
--         -- Prefer $iris texture if available and preference is set
--         materialToUse = irisMat
--     elseif eyeballMaterial then
--         -- Use full eyeball material
--         materialToUse = eyeballMaterial
--     else
--         -- Fallback to generic iris
--         materialToUse = irisMaterial
--     end
    
--     local irisSize = size * eye_cube_iris_size:GetFloat()
    
--     -- Set up rendering
--     render.SetMaterial(materialToUse)
--     render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
--     render.SetBlend(color.a / 255)
    
--     -- Draw a quad facing the forward direction
--     local forward = ang:Forward()
--     local right = ang:Right()
--     local up = ang:Up()
    
--     -- Create eyeball quad vertices
--     local halfSize = irisSize * 0.5
--     local v1 = pos - right * halfSize - up * halfSize
--     local v2 = pos + right * halfSize - up * halfSize
--     local v3 = pos + right * halfSize + up * halfSize
--     local v4 = pos - right * halfSize + up * halfSize
    
--     -- Draw the eyeball as a textured quad
--     render.DrawQuad(v1, v2, v3, v4)
    
--     -- Reset render state
--     render.SetColorModulation(1, 1, 1)
--     render.SetBlend(1)
-- end

-- -- Function to draw simple wireframe (more stable, less visual noise)
-- local function DrawSimpleWireframe(pos, ang, size, color)
--     -- Draw a simple cross pattern
--     local forward = ang:Forward()
--     local right = ang:Right()
--     local up = ang:Up()
--     local halfSize = size * 0.5
    
--     render.SetColorMaterial()
    
--     -- Draw cross lines
--     render.DrawBeam(pos - right * halfSize, pos + right * halfSize, 1, 0, 1, color)
--     render.DrawBeam(pos - up * halfSize, pos + up * halfSize, 1, 0, 1, color)
--     render.DrawBeam(pos - forward * halfSize, pos + forward * halfSize, 1, 0, 1, color)
-- end

-- -- Universal drawing function that chooses the appropriate method
-- local function DrawEyeIndicator(ent, pos, ang, size, color)
--     local drawMode = eye_cube_draw_mode:GetInt()
    
--     if drawMode == 1 then
--         DrawIrisTexture(pos, ang, size, color)
--     elseif drawMode == 2 then
--         DrawModelEyeball(ent, pos, ang, size, color)
--     elseif drawMode == 3 then
--         DrawSimpleWireframe(pos, ang, size, color)
--     else
--         DrawDevTextureCube(pos, ang, size, color)
--     end
-- end

-- -- Function to get individual eye positions and angles using bones/attachments
-- local function GetIndividualEyePositions(ent, centerPos, eyeAngles)
--     local leftEyePos, rightEyePos
--     local actualEyeAngles = eyeAngles -- Default fallback
    
--     -- Try to find eye attachments first (often most accurate)
--     local leftEyeAttach = ent:LookupAttachment("lefteye") or ent:LookupAttachment("left_eye") or ent:LookupAttachment("eye_left") or ent:LookupAttachment("eyes")
--     local rightEyeAttach = ent:LookupAttachment("righteye") or ent:LookupAttachment("right_eye") or ent:LookupAttachment("eye_right")
    
--     -- Try to find eye bones
--     local leftEyeBone = ent:LookupBone("ValveBiped.Bip01_L_Eye") or ent:LookupBone("Bip01 L Eye") or ent:LookupBone("L Eye")
--     local rightEyeBone = ent:LookupBone("ValveBiped.Bip01_R_Eye") or ent:LookupBone("Bip01 R Eye") or ent:LookupBone("R Eye")
--     local headBone = ent:LookupBone("ValveBiped.Bip01_Head1") or ent:LookupBone("Bip01 Head1") or ent:LookupBone("Head")
    
--     -- Get bone priority setting
--     local bonePriority = eye_cube_bone_priority:GetInt()
    
--     -- Try attachments first (highest priority)
--     if leftEyeAttach and leftEyeAttach > 0 then
--         local leftAttachData = ent:GetAttachment(leftEyeAttach)
--         if leftAttachData then
--             -- Apply angle corrections first
--             local pitchCorrection = eye_cube_angle_pitch:GetFloat()
--             local yawCorrection = eye_cube_angle_yaw:GetFloat()
--             local rollCorrection = eye_cube_angle_roll:GetFloat()
--             actualEyeAngles = Angle(leftAttachData.Ang.p + pitchCorrection, leftAttachData.Ang.y + yawCorrection, leftAttachData.Ang.r + rollCorrection)
            
--             -- Apply position offsets to attachment position
--             local forwardOffset = eye_cube_forward_offset:GetFloat()
--             local rightOffset = eye_cube_right_offset:GetFloat()
--             local upOffset = eye_cube_up_offset:GetFloat()
            
--             local forward = actualEyeAngles:Forward()
--             local right = actualEyeAngles:Right()
--             local up = actualEyeAngles:Up()
            
--             local positionOffset = forward * forwardOffset + right * rightOffset + up * upOffset
--             leftEyePos = leftAttachData.Pos + positionOffset
            
--             -- If we have right eye attachment too, use it
--             if rightEyeAttach and rightEyeAttach > 0 then
--                 local rightAttachData = ent:GetAttachment(rightEyeAttach)
--                 if rightAttachData then
--                     -- Apply same corrections to right eye
--                     local rightCorrectedAng = Angle(rightAttachData.Ang.p + pitchCorrection, rightAttachData.Ang.y + yawCorrection, rightAttachData.Ang.r + rollCorrection)
--                     rightEyePos = rightAttachData.Pos + positionOffset
                    
--                     -- Average the angles from both attachments
--                     actualEyeAngles = Angle(
--                         (actualEyeAngles.p + rightCorrectedAng.p) * 0.5,
--                         (actualEyeAngles.y + rightCorrectedAng.y) * 0.5,
--                         (actualEyeAngles.r + rightCorrectedAng.r) * 0.5
--                     )
--                 else
--                     -- Calculate right eye from left eye position
--                     local separation = eye_cube_separation:GetFloat()
--                     rightEyePos = leftEyePos + right * separation
--                 end
--             else
--                 -- Calculate right eye from left eye position
--                 local separation = eye_cube_separation:GetFloat()
--                 rightEyePos = leftEyePos + right * separation
--             end
            
--             return leftEyePos, rightEyePos, actualEyeAngles
--         end
--     end
    
--     -- Get head bone angles for real-time head movement tracking
--     if headBone then
--         local headPos, headAng = ent:GetBonePosition(headBone)
--         if headPos and headAng then
--             -- Apply adjustable angle corrections for different model types
--             local pitchCorrection = eye_cube_angle_pitch:GetFloat()
--             local yawCorrection = eye_cube_angle_yaw:GetFloat()
--             local rollCorrection = eye_cube_angle_roll:GetFloat()
--             local correctedAng = Angle(headAng.p + pitchCorrection, headAng.y + yawCorrection, headAng.r + rollCorrection)
--             actualEyeAngles = correctedAng
            
--             if leftEyeBone and rightEyeBone and bonePriority > 0 then
--                 -- Check if eye bones have their own angles (more stable)
--                 local leftEyePos_temp, leftEyeAng = ent:GetBonePosition(leftEyeBone)
--                 local rightEyePos_temp, rightEyeAng = ent:GetBonePosition(rightEyeBone)
                
--                 if leftEyeAng and rightEyeAng then
--                     -- Use eye bone positions and their own corrected angles for maximum stability
--                     -- Use the average of left and right eye angles, corrected
--                     local avgEyeAng = Angle(
--                         (leftEyeAng.p + rightEyeAng.p) * 0.5,
--                         (leftEyeAng.y + rightEyeAng.y) * 0.5,
--                         (leftEyeAng.r + rightEyeAng.r) * 0.5
--                     )
--                     actualEyeAngles = Angle(avgEyeAng.p + pitchCorrection, avgEyeAng.y + yawCorrection, avgEyeAng.r + rollCorrection)
                    
--                     -- Apply position offsets to eye bone positions
--                     local forwardOffset = eye_cube_forward_offset:GetFloat()
--                     local rightOffset = eye_cube_right_offset:GetFloat()
--                     local upOffset = eye_cube_up_offset:GetFloat()
                    
--                     local forward = actualEyeAngles:Forward()
--                     local right = actualEyeAngles:Right()
--                     local up = actualEyeAngles:Up()
                    
--                     local positionOffset = forward * forwardOffset + right * rightOffset + up * upOffset
--                     leftEyePos = leftEyePos_temp + positionOffset
--                     rightEyePos = rightEyePos_temp + positionOffset
--                 else
--                     -- Fallback: use eye bone positions with head bone angles
--                     -- Apply position offsets to eye bone positions
--                     local forwardOffset = eye_cube_forward_offset:GetFloat()
--                     local rightOffset = eye_cube_right_offset:GetFloat()
--                     local upOffset = eye_cube_up_offset:GetFloat()
                    
--                     local forward = correctedAng:Forward()
--                     local right = correctedAng:Right()
--                     local up = correctedAng:Up()
                    
--                     local positionOffset = forward * forwardOffset + right * rightOffset + up * upOffset
--                     leftEyePos = leftEyePos_temp + positionOffset
--                     rightEyePos = rightEyePos_temp + positionOffset
--                     actualEyeAngles = correctedAng
--                 end
--             else
--                 -- Calculate eye positions from head bone using corrected angles
--                 local correctedRight = correctedAng:Right()
--                 local correctedForward = correctedAng:Forward()
--                 local correctedUp = correctedAng:Up()
                
--                 -- Model-specific eye offsets from head bone using corrected orientation
--                 local forwardOffset = eye_cube_forward_offset:GetFloat()
--                 local upOffset = eye_cube_up_offset:GetFloat()
--                 local eyeOffset = correctedForward * forwardOffset + correctedUp * upOffset
--                 local eyeSeparation = eye_cube_separation:GetFloat()
                
--                 leftEyePos = headPos + eyeOffset - correctedRight * (eyeSeparation * 0.5)
--                 rightEyePos = headPos + eyeOffset + correctedRight * (eyeSeparation * 0.5)
--             end
--         else
--             -- Fallback to center position method
--             local separation = eye_cube_separation:GetFloat()
--             local right = eyeAngles:Right()
--             leftEyePos = centerPos - right * (separation * 0.5)
--             rightEyePos = centerPos + right * (separation * 0.5)
--         end
--     else
--         -- Final fallback to center position method
--         local separation = eye_cube_separation:GetFloat()
--         local right = eyeAngles:Right()
--         leftEyePos = centerPos - right * (separation * 0.5)
--         rightEyePos = centerPos + right * (separation * 0.5)
--     end
    
--     return leftEyePos, rightEyePos, actualEyeAngles
-- end

-- -- Main drawing function
-- local function DrawEyeCubes()
--     if not eye_cube_enabled:GetBool() then 
--         -- Restore all materials when disabled
--         for ent, _ in pairs(originalEyeballMaterials) do
--             RestoreOriginalEyeballMaterials(ent)
--         end
--         return 
--     end
    
--     local size = eye_cube_size:GetFloat()
--     local drawIndividual = eye_cube_individual:GetBool()
--     local baseColor = Color(
--         eye_cube_color_r:GetInt(),
--         eye_cube_color_g:GetInt(),
--         eye_cube_color_b:GetInt(),
--         eye_cube_alpha:GetInt()
--     )
    
--     -- Get all entities
--     for _, ent in ipairs(ents.GetAll()) do
--         if ShouldDrawEyeCube(ent) then
--             -- Get eye position and angles using the entity methods
--             local eyePos = ent:EyePos()
--             local eyeAngles = ent:EyeAngles()
            
--             -- Only draw if we got valid positions
--             if eyePos and eyeAngles then
--                 if drawIndividual then
--                     -- Draw individual left and right eye cubes
--                     local leftEyePos, rightEyePos, actualEyeAngles = GetIndividualEyePositions(ent, eyePos, eyeAngles)
                    
--                     -- Left eye (slightly blue tinted)
--                     local leftColor = Color(baseColor.r, baseColor.g, math.min(255, baseColor.b + 50), baseColor.a)
--                     DrawEyeIndicator(ent, leftEyePos, actualEyeAngles, size * 0.8, leftColor)
                    
--                     -- Right eye (slightly red tinted)
--                     local rightColor = Color(math.min(255, baseColor.r + 50), baseColor.g, baseColor.b, baseColor.a)
--                     DrawEyeIndicator(ent, rightEyePos, actualEyeAngles, size * 0.8, rightColor)
                    
--                     -- Draw direction lines from both eyes using actual eye angles
--                     local forward = actualEyeAngles:Forward()
--                     local lineLength = size * 2
                    
--                     render.SetColorMaterial()
--                     render.DrawBeam(leftEyePos, leftEyePos + forward * lineLength, 0.8, 0, 1, leftColor)
--                     render.DrawBeam(rightEyePos, rightEyePos + forward * lineLength, 0.8, 0, 1, rightColor)
--                 else
--                     -- For single center cube, try to get head bone angles too
--                     local headBone = ent:LookupBone("ValveBiped.Bip01_Head1") or ent:LookupBone("Bip01 Head1") or ent:LookupBone("Head")
--                     local actualAngles = eyeAngles
                    
--                     if headBone then
--                         local _, headAng = ent:GetBonePosition(headBone)
--                         if headAng then
--                             -- Apply the same adjustable coordinate system correction
--                             local pitchCorrection = eye_cube_angle_pitch:GetFloat()
--                             local yawCorrection = eye_cube_angle_yaw:GetFloat()
--                             local rollCorrection = eye_cube_angle_roll:GetFloat()
--                             actualAngles = Angle(headAng.p + pitchCorrection, headAng.y + yawCorrection, headAng.r + rollCorrection)
--                         end
--                     end
                    
--                     -- Draw single center indicator with head bone angles
--                     DrawEyeIndicator(ent, eyePos, actualAngles, size, baseColor)
                    
--                     -- Draw direction line
--                     local forward = actualAngles:Forward()
--                     local endPos = eyePos + forward * (size * 2)
                    
--                     render.SetColorMaterial()
--                     render.DrawBeam(eyePos, endPos, 1, 0, 1, Color(baseColor.r, baseColor.g, baseColor.b, math.min(255, baseColor.a + 55)))
--                 end
--             end
--         end
--     end
    
--     -- Clean up materials for entities that no longer should have eye cubes or are invalid
--     for ent, _ in pairs(originalEyeballMaterials) do
--         if not IsValid(ent) or not ShouldDrawEyeCube(ent) then
--             RestoreOriginalEyeballMaterials(ent)
--         end
--     end
-- end

-- -- Hook into the 3D rendering
-- hook.Add("PostDrawOpaqueRenderables", "DrawEyeCubes", DrawEyeCubes)

-- -- Clean up materials when shutting down
-- hook.Add("ShutDown", "EyeCubeCleanup", function()
--     for ent, _ in pairs(originalEyeballMaterials) do
--         RestoreOriginalEyeballMaterials(ent)
--     end
-- end)

-- -- Console commands for easy control
-- concommand.Add("rtx_eye_cube_toggle", function()
--     local current = eye_cube_enabled:GetBool()
--     RunConsoleCommand("rtx_eye_cube_enabled", current and "0" or "1")
--     chat.AddText(Color(100, 255, 100), "[Eye Cube] ", Color(255, 255, 255), current and "Disabled" or "Enabled")
-- end, nil, "Toggle eye cube drawing on/off")

-- concommand.Add("rtx_eye_cube_mode", function()
--     local current = eye_cube_individual:GetBool()
--     RunConsoleCommand("rtx_eye_cube_individual", current and "0" or "1")
--     chat.AddText(Color(100, 255, 100), "[Eye Cube] ", Color(255, 255, 255), "Mode: " .. (current and "Single center cube" or "Individual left/right eyes"))
-- end, nil, "Toggle between single center cube and individual left/right eye cubes")

-- -- Derma Panel for Eye Cube Settings
-- local function CreateEyeCubePanel()
--     -- Close existing panel if it exists
--     if IsValid(EyeCubePanel) then
--         EyeCubePanel:Close()
--     end
    
--     local frame = vgui.Create("DFrame")
--     frame:SetTitle("Eye Cube Settings")
--     frame:SetSize(400, 650)
--     frame:Center()
--     frame:SetDeleteOnClose(true)
--     frame:SetDraggable(true)
--     frame:MakePopup()
    
--     EyeCubePanel = frame
    
--     local y = 30
    
--     -- Enable/Disable checkbox
--     local enableCheck = vgui.Create("DCheckBox", frame)
--     enableCheck:SetPos(20, y)
--     enableCheck:SetValue(eye_cube_enabled:GetBool())
--     enableCheck.OnChange = function(self, val)
--         RunConsoleCommand("rtx_eye_cube_enabled", val and "1" or "0")
--     end
    
--     local enableLabel = vgui.Create("DLabel", frame)
--     enableLabel:SetPos(45, y)
--     enableLabel:SetText("Enable Eye Cubes")
--     enableLabel:SizeToContents()
    
--     y = y + 30
    
--     -- Individual eyes checkbox
--     local individualCheck = vgui.Create("DCheckBox", frame)
--     individualCheck:SetPos(20, y)
--     individualCheck:SetValue(eye_cube_individual:GetBool())
--     individualCheck.OnChange = function(self, val)
--         RunConsoleCommand("rtx_eye_cube_individual", val and "1" or "0")
--     end
    
--     local individualLabel = vgui.Create("DLabel", frame)
--     individualLabel:SetPos(45, y)
--     individualLabel:SetText("Individual Left/Right Eyes")
--     individualLabel:SizeToContents()
    
--     y = y + 30
    
--     -- Draw mode selection
--     local drawModeLabel = vgui.Create("DLabel", frame)
--     drawModeLabel:SetPos(20, y)
--     drawModeLabel:SetText("Draw Mode:")
--     drawModeLabel:SizeToContents()
    
--     local drawModeCombo = vgui.Create("DComboBox", frame)
--     drawModeCombo:SetPos(100, y)
--     drawModeCombo:SetSize(200, 20)
--     drawModeCombo:AddChoice("Dev Texture Cubes", 0)
--     drawModeCombo:AddChoice("Generic Iris", 1)
--     drawModeCombo:AddChoice("Model Eyeball", 2)
--     drawModeCombo:AddChoice("Simple Wireframe", 3)
--     drawModeCombo:ChooseOptionID(eye_cube_draw_mode:GetInt() + 1)
--     drawModeCombo.OnSelect = function(self, index, value, data)
--         RunConsoleCommand("rtx_eye_cube_draw_mode", tostring(data))
--     end
    
--     y = y + 30
    
--     -- Auto-detect checkbox
--     local autoDetectCheck = vgui.Create("DCheckBox", frame)
--     autoDetectCheck:SetPos(20, y)
--     autoDetectCheck:SetValue(eye_cube_auto_detect:GetBool())
--     autoDetectCheck.OnChange = function(self, val)
--         RunConsoleCommand("rtx_eye_cube_auto_detect", val and "1" or "0")
--     end
    
--     local autoDetectLabel = vgui.Create("DLabel", frame)
--     autoDetectLabel:SetPos(45, y)
--     autoDetectLabel:SetText("Auto-detect Model Eyeball Materials")
--     autoDetectLabel:SizeToContents()
    
--     y = y + 30
    
--     -- Prefer iris checkbox
--     local preferIrisCheck = vgui.Create("DCheckBox", frame)
--     preferIrisCheck:SetPos(20, y)
--     preferIrisCheck:SetValue(eye_cube_prefer_iris:GetBool())
--     preferIrisCheck.OnChange = function(self, val)
--         RunConsoleCommand("rtx_eye_cube_prefer_iris", val and "1" or "0")
--     end
    
--     local preferIrisLabel = vgui.Create("DLabel", frame)
--     preferIrisLabel:SetPos(45, y)
--     preferIrisLabel:SetText("Prefer $iris Texture (VMT Parameter)")
--     preferIrisLabel:SizeToContents()
    
--     y = y + 40
    
--     -- Helper function to create sliders
--     local function CreateSlider(parent, label, convar, min, max, decimals)
--         local labelObj = vgui.Create("DLabel", parent)
--         labelObj:SetPos(20, y)
--         labelObj:SetText(label)
--         labelObj:SizeToContents()
        
--         local slider = vgui.Create("DNumSlider", parent)
--         slider:SetPos(20, y + 20)
--         slider:SetSize(350, 20)
--         slider:SetMin(min)
--         slider:SetMax(max)
--         slider:SetDecimals(decimals or 1)
--         slider:SetValue(convar:GetFloat())
--         slider.OnValueChanged = function(self, val)
--             RunConsoleCommand(convar:GetName(), tostring(val))
--         end
        
--         y = y + 50
--         return slider
--     end
    
--     -- Size slider
--     CreateSlider(frame, "Size:", eye_cube_size, 0.5, 10, 1)
    
--     -- Iris size slider (only relevant for iris mode)
--     CreateSlider(frame, "Iris Size Multiplier:", eye_cube_iris_size, 0.1, 3, 1)
    
--     -- Separation slider
--     CreateSlider(frame, "Eye Separation:", eye_cube_separation, 1, 10, 1)
    
--     -- Forward offset slider
--     CreateSlider(frame, "Forward Offset:", eye_cube_forward_offset, -5, 10, 1)
    
--     -- Right offset slider
--     CreateSlider(frame, "Right Offset:", eye_cube_right_offset, -5, 10, 1)
    
--     -- Up offset slider
--     CreateSlider(frame, "Up Offset:", eye_cube_up_offset, -5, 10, 1)
    
--     -- Angle correction sliders
--     y = y + 10
--     local angleLabel = vgui.Create("DLabel", frame)
--     angleLabel:SetPos(20, y)
--     angleLabel:SetText("Angle Corrections:")
--     angleLabel:SizeToContents()
--     y = y + 25
    
--     CreateSlider(frame, "Pitch Correction:", eye_cube_angle_pitch, -180, 180, 0)
--     CreateSlider(frame, "Yaw Correction:", eye_cube_angle_yaw, -180, 180, 0)
--     CreateSlider(frame, "Roll Correction:", eye_cube_angle_roll, -180, 180, 0)
    
--     -- Color sliders
--     y = y + 10
--     local colorLabel = vgui.Create("DLabel", frame)
--     colorLabel:SetPos(20, y)
--     colorLabel:SetText("Color Settings:")
--     colorLabel:SizeToContents()
--     y = y + 25
    
--     CreateSlider(frame, "Red:", eye_cube_color_r, 0, 255, 0)
--     CreateSlider(frame, "Green:", eye_cube_color_g, 0, 255, 0)
--     CreateSlider(frame, "Blue:", eye_cube_color_b, 0, 255, 0)
--     CreateSlider(frame, "Alpha:", eye_cube_alpha, 0, 255, 0)
    
--     -- Buttons at the bottom
--     local buttonY = frame:GetTall() - 60
    
--     -- Reset button
--     local resetBtn = vgui.Create("DButton", frame)
--     resetBtn:SetPos(20, buttonY)
--     resetBtn:SetSize(80, 25)
--     resetBtn:SetText("Reset")
--     resetBtn.DoClick = function()
--         RunConsoleCommand("rtx_eye_cube_size", "2")
--         RunConsoleCommand("rtx_eye_cube_separation", "3")
--         RunConsoleCommand("rtx_eye_cube_forward_offset", "3")
--         RunConsoleCommand("rtx_eye_cube_right_offset", "0")
--         RunConsoleCommand("rtx_eye_cube_up_offset", "2")
--         RunConsoleCommand("rtx_eye_cube_angle_pitch", "0")
--         RunConsoleCommand("rtx_eye_cube_angle_yaw", "-90")
--         RunConsoleCommand("rtx_eye_cube_angle_roll", "0")
--         RunConsoleCommand("rtx_eye_cube_draw_mode", "0")
--         RunConsoleCommand("rtx_eye_cube_iris_size", "1.5")
--         RunConsoleCommand("rtx_eye_cube_auto_detect", "1")
--         RunConsoleCommand("rtx_eye_cube_prefer_iris", "1")
--         RunConsoleCommand("rtx_eye_cube_bone_priority", "1")
--         RunConsoleCommand("rtx_eye_cube_color_r", "255")
--         RunConsoleCommand("rtx_eye_cube_color_g", "0")
--         RunConsoleCommand("rtx_eye_cube_color_b", "0")
--         RunConsoleCommand("rtx_eye_cube_alpha", "200")
--         frame:Close()
--         timer.Simple(0.1, CreateEyeCubePanel) -- Recreate panel with new values
--     end
    
--     -- Debug button
--     local debugBtn = vgui.Create("DButton", frame)
--     debugBtn:SetPos(110, buttonY)
--     debugBtn:SetSize(80, 25)
--     debugBtn:SetText("Debug")
--     debugBtn.DoClick = function()
--         RunConsoleCommand("rtx_eye_cube_debug")
--     end
    
--     -- Target button
--     local targetBtn = vgui.Create("DButton", frame)
--     targetBtn:SetPos(200, buttonY)
--     targetBtn:SetSize(80, 25)
--     targetBtn:SetText("Set Target")
--     targetBtn.DoClick = function()
--         RunConsoleCommand("rtx_eye_cube_target")
--     end
    
--     -- Close button
--     local closeBtn = vgui.Create("DButton", frame)
--     closeBtn:SetPos(290, buttonY)
--     closeBtn:SetSize(80, 25)
--     closeBtn:SetText("Close")
--     closeBtn.DoClick = function()
--         frame:Close()
--     end
-- end

-- concommand.Add("rtx_eye_cube_panel", CreateEyeCubePanel, nil, "Open the Eye Cube settings panel")

-- concommand.Add("rtx_eye_cube_debug", function(ply, cmd, args)
--     local trace = LocalPlayer():GetEyeTrace()
--     local ent = trace.Entity
    
--     if IsValid(ent) and ShouldDrawEyeCube(ent) then
--         chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Entity: " .. ent:GetClass())
--         chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Model: " .. (ent:GetModel() or "Unknown"))
        
--         -- Check for eye attachments
--         local leftEyeAttach = ent:LookupAttachment("lefteye") or ent:LookupAttachment("left_eye") or ent:LookupAttachment("eye_left") or ent:LookupAttachment("eyes")
--         local rightEyeAttach = ent:LookupAttachment("righteye") or ent:LookupAttachment("right_eye") or ent:LookupAttachment("eye_right")
        
--         -- Check for eye bones
--         local leftEyeBone = ent:LookupBone("ValveBiped.Bip01_L_Eye") or ent:LookupBone("Bip01 L Eye") or ent:LookupBone("L Eye")
--         local rightEyeBone = ent:LookupBone("ValveBiped.Bip01_R_Eye") or ent:LookupBone("Bip01 R Eye") or ent:LookupBone("R Eye")
--         local headBone = ent:LookupBone("ValveBiped.Bip01_Head1") or ent:LookupBone("Bip01 Head1") or ent:LookupBone("Head")
        
--         -- Show attachment information
--         if leftEyeAttach and leftEyeAttach > 0 then
--             local attachData = ent:GetAttachment(leftEyeAttach)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Left eye attachment found: ID " .. leftEyeAttach)
--             if attachData then
--                 chat.AddText(Color(150, 150, 255), "  Position: " .. tostring(attachData.Pos))
--                 chat.AddText(Color(150, 150, 255), "  Angles: " .. tostring(attachData.Ang))
--             end
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No left eye attachment found")
--         end
        
--         if rightEyeAttach and rightEyeAttach > 0 then
--             local attachData = ent:GetAttachment(rightEyeAttach)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Right eye attachment found: ID " .. rightEyeAttach)
--             if attachData then
--                 chat.AddText(Color(150, 150, 255), "  Position: " .. tostring(attachData.Pos))
--                 chat.AddText(Color(150, 150, 255), "  Angles: " .. tostring(attachData.Ang))
--             end
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No right eye attachment found")
--         end
        
--         if leftEyeBone then
--             local pos, ang = ent:GetBonePosition(leftEyeBone)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Left eye bone found: " .. ent:GetBoneName(leftEyeBone))
--             chat.AddText(Color(150, 150, 255), "  Position: " .. tostring(pos))
--             chat.AddText(Color(150, 150, 255), "  Angles: " .. (ang and tostring(ang) or "nil"))
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No left eye bone found")
--         end
        
--         if rightEyeBone then
--             local pos, ang = ent:GetBonePosition(rightEyeBone)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Right eye bone found: " .. ent:GetBoneName(rightEyeBone))
--             chat.AddText(Color(150, 150, 255), "  Position: " .. tostring(pos))
--             chat.AddText(Color(150, 150, 255), "  Angles: " .. (ang and tostring(ang) or "nil"))
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No right eye bone found")
--         end
        
--         if headBone then
--             local pos, ang = ent:GetBonePosition(headBone)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Head bone found: " .. ent:GetBoneName(headBone))
--             chat.AddText(Color(150, 150, 255), "  Position: " .. tostring(pos))
--             chat.AddText(Color(150, 150, 255), "  Angles: " .. (ang and tostring(ang) or "nil"))
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No head bone found")
--         end
        
--         -- Show current bone priority setting
--         local bonePriority = eye_cube_bone_priority:GetInt()
--         local priorityText = bonePriority == 0 and "Head bone only" or (bonePriority == 1 and "Eye bones preferred" or "Eye bones only")
--         chat.AddText(Color(200, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Bone priority: " .. priorityText)
        
--         -- Show material detection info
--         if eye_cube_auto_detect:GetBool() then
--             local eyeballMat, irisMat = GetModelEyeballMaterial(ent)
--             if eyeballMat then
--                 chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Detected eyeball material: Found")
                
--                 if irisMat then
--                     chat.AddText(Color(100, 255, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Detected $iris texture: Found (VertexLitGeneric)")
--                     local preferIris = eye_cube_prefer_iris:GetBool()
--                     chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Using: " .. (preferIris and "$iris texture (VertexLitGeneric)" or "Full eyeball material"))
--                 else
--                     chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No $iris texture found in VMT")
--                 end
--             else
--                 chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No eyeball material detected")
--             end
            
--             -- Show all materials for reference
--             local materials = ent:GetMaterials()
--             chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Model materials (" .. #materials .. "):")
--             for i, mat in ipairs(materials) do
--                 if i <= 5 then -- Show first 5 materials
--                     chat.AddText(Color(200, 200, 200), "  " .. i .. ": " .. mat)
--                 elseif i == 6 then
--                     chat.AddText(Color(200, 200, 200), "  ... and " .. (#materials - 5) .. " more")
--                     break
--                 end
--             end
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "Auto-detect disabled")
--         end
        
--         -- List some bones for reference
--         chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Bone count: " .. ent:GetBoneCount())
        
--         -- List attachments
--         local attachmentCount = 0
--         for i = 1, 50 do -- Check first 50 attachment slots
--             local attachData = ent:GetAttachment(i)
--             if attachData then
--                 attachmentCount = attachmentCount + 1
--             end
--         end
--         chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Attachment count: " .. attachmentCount)
        
--         if args[1] == "bones" then
--             chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Listing all bones:")
--             for i = 0, math.min(ent:GetBoneCount() - 1, 20) do -- Limit to first 20 bones
--                 local boneName = ent:GetBoneName(i)
--                 if boneName and boneName ~= "" then
--                     chat.AddText(Color(200, 200, 200), "  " .. i .. ": " .. boneName)
--                 end
--             end
--         elseif args[1] == "attachments" then
--             chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Listing all attachments:")
--             for i = 1, 50 do -- Check first 50 attachment slots
--                 local attachData = ent:GetAttachment(i)
--                 if attachData then
--                     chat.AddText(Color(200, 200, 200), "  " .. i .. ": " .. tostring(attachData.Pos))
--                 end
--             end
--         else
--             chat.AddText(Color(150, 150, 255), "[Eye Cube Debug] ", Color(255, 255, 255), "Use 'rtx_eye_cube_debug bones' or 'rtx_eye_cube_debug attachments' for full lists")
--         end
--     else
--         chat.AddText(Color(255, 100, 100), "[Eye Cube Debug] ", Color(255, 255, 255), "No valid NPC/ragdoll found in crosshair")
--     end
-- end, nil, "Debug bone information for the targeted entity")

-- concommand.Add("rtx_eye_cube_target", function(ply, cmd, args)
--     if not eye_cube_enabled:GetBool() then
--         chat.AddText(Color(255, 100, 100), "[Eye Cube] ", Color(255, 255, 255), "Eye cubes are disabled. Enable with rtx_eye_cube_toggle")
--         return
--     end
    
--     -- Get the entity the player is looking at
--     local trace = LocalPlayer():GetEyeTrace()
--     local ent = trace.Entity
    
--     if IsValid(ent) and ShouldDrawEyeCube(ent) then
--         -- Use SetEyeTarget if the entity supports it (mainly for NPCs)
--         if ent.SetEyeTarget then
--             local targetPos = LocalPlayer():EyePos()
--             ent:SetEyeTarget(targetPos)
--             chat.AddText(Color(100, 255, 100), "[Eye Cube] ", Color(255, 255, 255), "Set eye target for " .. ent:GetClass())
--         else
--             chat.AddText(Color(255, 200, 100), "[Eye Cube] ", Color(255, 255, 255), "Entity doesn't support SetEyeTarget: " .. ent:GetClass())
--         end
--     else
--         chat.AddText(Color(255, 100, 100), "[Eye Cube] ", Color(255, 255, 255), "No valid NPC/ragdoll found in crosshair")
--     end
-- end, nil, "Make the targeted NPC look at you using SetEyeTarget")

-- -- Print help on load
-- timer.Simple(1, function()
--     if eye_cube_enabled:GetBool() then
--         chat.AddText(Color(100, 255, 100), "[Eye Cube] ", Color(255, 255, 255), "Loaded! Use 'rtx_eye_cube_panel' to open settings GUI")
--     end
-- end) 