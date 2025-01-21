-- if not CLIENT then return end

-- -- Cache known problematic materials to avoid repeated processing
-- local processedMaterials = {}

-- -- Extended shader mapping table
-- local SHADER_FALLBACKS = {
--     ["Eyes"] = "VertexLitGeneric",
--     ["EyeRefract"] = "VertexLitGeneric",
--     ["eyes"] = "VertexLitGeneric", -- Lowercase variant
--     ["eyerefract"] = "VertexLitGeneric", -- Lowercase variant
-- }

-- -- Known eye-related material patterns
-- local EYE_MATERIAL_PATTERNS = {
--     "eye",
--     "eyes",
--     "pupil",
--     "iris",
--     "cornea",
--     "eyeball",
--     "retina"
-- }

-- local function IsEyeMaterial(matName)
--     matName = matName:lower()
--     for _, pattern in ipairs(EYE_MATERIAL_PATTERNS) do
--         if matName:find(pattern) then
--             return true
--         end
--     end
--     return false
-- end

-- -- String helper functions
-- local function EndsWith(str, ending)
--     return ending == "" or str:sub(-#ending) == ending
-- end

-- local function ConvertToFallbackEyes(mat)
--     if not mat or mat:IsError() then return end
    
--     -- Store original parameters we want to preserve
--     local baseTexture = mat:GetTexture("$iris") or mat:GetTexture("$basetexture")
--     local ambientOcclTexture = mat:GetTexture("$ambientocclusion")
--     local color = mat:GetVector("$color") or Vector(1, 1, 1)
--     local alpha = mat:GetFloat("$alpha") or 1
    
--     -- Convert to VertexLitGeneric instead of Eyes_dx6
--     mat:SetShader("VertexLitGeneric")
    
--     -- Set basic parameters
--     if baseTexture then
--         mat:SetTexture("$basetexture", baseTexture)
--     end
    
--     if ambientOcclTexture then
--         mat:SetTexture("$ambientoccltexture", ambientOcclTexture)
--     end
    
--     -- Set up basic material properties
--     mat:SetVector("$color", color)
--     mat:SetFloat("$alpha", alpha)
--     mat:SetInt("$halflambert", 1)
--     mat:SetInt("$model", 1)
--     mat:SetInt("$nocull", 0)
--     mat:SetFloat("$phong", 1)
--     mat:SetFloat("$phongboost", 2)
--     mat:SetFloat("$phongexponent", 5)
    
--     -- Remove problematic parameters
--     local paramsToRemove = {
--         "$eyeballradius",
--         "$dilation",
--         "$corneatexture",
--         "$corneabumpstrength",
--         "$spheretexkillcombo",
--         "$parallaxstrength",
--         "$raytracesphere",
--         "$spheretexture",
--         "$maxdistance",
--         "$fadescale",
--         "$iris",
--         "$glossiness"
--     }
    
--     for _, param in ipairs(paramsToRemove) do
--         mat:SetUndefined(param)
--     end
    
--     return mat
-- end

-- local function ConvertWireframeToUnlit(mat)
--     if not mat or mat:IsError() then return end
    
--     -- Store original parameters
--     local baseTexture = mat:GetTexture("$basetexture")
--     local color = mat:GetVector("$color") or Vector(1, 1, 1)
--     local alpha = mat:GetFloat("$alpha") or 1
    
--     -- Convert to UnlitGeneric
--     mat:SetShader("UnlitGeneric")
    
--     if baseTexture then
--         mat:SetTexture("$basetexture", baseTexture)
--     end
    
--     -- Set basic parameters
--     mat:SetVector("$color", color)
--     mat:SetFloat("$alpha", alpha)
--     mat:SetInt("$nocull", 1)
--     mat:SetInt("$vertexcolor", 1)
--     mat:SetInt("$vertexalpha", 1)
    
--     return mat
-- end

-- local function FixupMaterial(filepath)
--     if not filepath or processedMaterials[filepath] then return end
    
--     local mattrim = (filepath:sub(0, #"materials/") == "materials/") and filepath:sub(#"materials/"+1) or filepath
--     local matname = mattrim:gsub(".vmt".."$", "")
--     local mat = Material(matname)
    
--     if not mat or mat:IsError() then return end
    
--     local shader = mat:GetShader():lower()
--     local fallbackShader = SHADER_FALLBACKS[shader]
    
--     -- Process if it's a known problematic shader or looks like an eye material
--     if fallbackShader or IsEyeMaterial(matname) then
--         print(string.format("[Eye Shader Fix] Converting material %s (shader: %s)", filepath, shader))
        
--         if shader == "wireframe" then
--         else
--             ConvertToFallbackEyes(mat)
--         end
        
--         processedMaterials[filepath] = true
--     end
-- end

-- -- Enhanced material scanning with error handling
-- local function ScanMaterials(dir)
--     local files, folders = file.Find(dir .. "*", "GAME")
    
--     if not files or not folders then return end
    
--     -- Process files in current directory
--     for _, f in ipairs(files) do
--         if EndsWith(f, ".vmt") then
--             local fullPath = dir .. f
--             local content = file.Read(fullPath, "GAME")
            
--             if content then
--                 -- Check for known shaders or eye-related content
--                 local shouldProcess = false
                
--                 -- Check shader type
--                 for shader in pairs(SHADER_FALLBACKS) do
--                     if content:lower():find('"shader"%s*"' .. shader:lower() .. '"') then
--                         shouldProcess = true
--                         break
--                     end
--                 end
                
--                 -- Check for eye-related patterns
--                 if not shouldProcess then
--                     for _, pattern in ipairs(EYE_MATERIAL_PATTERNS) do
--                         if content:lower():find(pattern) then
--                             shouldProcess = true
--                             break
--                         end
--                     end
--                 end
                
--                 if shouldProcess then
--                     local success, err = pcall(function()
--                         FixupMaterial(fullPath)
--                     end)
                    
--                     if not success then
--                         print("[Eye Shader Fix] Error processing material: " .. fullPath)
--                         print(err)
--                     end
--                 end
--             end
--         end
--     end
    
--     -- Recursively process subfolders
--     for _, folder in ipairs(folders) do
--         ScanMaterials(dir .. folder .. "/")
--     end
-- end

-- -- Main function to apply fixes
-- local function ApplyEyeFixes()
--     if not GetConVar("eye_shader_fix"):GetBool() then return end
    
--     print("[Eye Shader Fix] Starting material fixes...")
    
--     -- Clear the processed materials cache
--     table.Empty(processedMaterials)
    
--     -- Scan common directories
--     local directories = {
--         "materials/models/",
--         "materials/characters/",
--         "materials/humans/",
--     }
    
--     for _, dir in ipairs(directories) do
--         local success, err = pcall(function()
--             ScanMaterials(dir)
--         end)
        
--         if not success then
--             print("[Eye Shader Fix] Error scanning directory: " .. dir)
--             print(err)
--         end
--     end
    
--     -- Force material reload on existing entities
--     for _, ent in ipairs(ents.GetAll()) do
--         if IsValid(ent) then
--             local model = ent:GetModel()
--             if model then
--                 for _, mat in ipairs(ent:GetMaterials()) do
--                     local success, err = pcall(function()
--                         FixupMaterial(mat)
--                     end)
                    
--                     if not success then
--                         print("[Eye Shader Fix] Error processing entity material: " .. mat)
--                         print(err)
--                     end
--                 end
--             end
--         end
--     end
    
--     print("[Eye Shader Fix] Material fixing complete")
-- end

-- -- Create ConVar
-- CreateClientConVar("eye_shader_fix", "1", true, false, "Enable eye shader fixes for low DX levels")

-- -- Hook into InitPostEntity to apply fixes when the game loads
-- hook.Add("InitPostEntity", "EyeShaderFix", function()
--     timer.Simple(1, function()
--         local success, err = pcall(ApplyEyeFixes)
--         if not success then
--             print("[Eye Shader Fix] Error during initialization:")
--             print(err)
--         end
--     end)
-- end)

-- -- Add console command to manually reapply fixes
-- concommand.Add("eye_shader_fix_reload", function()
--     local success, err = pcall(ApplyEyeFixes)
--     if not success then
--         print("[Eye Shader Fix] Error during reload:")
--         print(err)
--     end
-- end)

-- -- Material precache hook to catch late-loaded materials
-- hook.Add("PreloadModels", "EyeShaderFix_Precache", function()
--     timer.Simple(0, function()
--         local success, err = pcall(ApplyEyeFixes)
--         if not success then
--             print("[Eye Shader Fix] Error during precache:")
--             print(err)
--         end
--     end)
-- end)

-- -- Add to the menu
-- hook.Add("PopulateToolMenu", "EyeShaderFixMenu", function()
--     spawnmenu.AddToolMenuOption("Utilities", "User", "EyeShaderFix", "Eye Shader Fix", "", "", function(panel)
--         panel:ClearControls()
        
--         panel:CheckBox("Enable Eye Shader Fix", "eye_shader_fix")
--         panel:ControlHelp("Converts problematic eye shaders to DX6 fallback")
        
--         panel:Button("Reapply Fixes", "eye_shader_fix_reload")
--     end)
-- end)