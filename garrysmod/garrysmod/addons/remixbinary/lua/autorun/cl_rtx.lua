if not CLIENT then return end

if CLIENT then
    require((BRANCH == "x86-64" or BRANCH == "chromium" ) and "RTXFixesBinary" or "RTXFixesBinary")
end



-- Initialize NikNaks
require("niknaks")

-- Create debug ConVar here so it's available for DebugPrint
local cv_debug = CreateClientConVar("rtx_rt_debug", "0", true, false, "Enable debug messages for RT States")

-- Helper function for debug printing (moved up before sub-addon loading)
-- Made global so sub-addons can use it
function DebugPrint(message)
    if cv_debug:GetBool() then
        print(message)
    end
end

local function LoadSubAddons()
    -- Helper function to load files from a specific folder
    local function LoadFilesFromFolder(folder)
        local files, _ = file.Find(folder .. "*.lua", "LUA")
        
        if files then
            DebugPrint("[RTXF2] Found " .. #files .. " files in " .. folder)
            
            for _, fileName in ipairs(files) do
                local filePath = folder .. fileName
                local success, err = pcall(include, filePath)
                
                if not success then
                    DebugPrint("[RTXF2] Warning: Failed to load sub-addon: " .. filePath .. " - Error: " .. tostring(err))
                else
                    DebugPrint("[RTXF2] Successfully loaded sub-addon: " .. filePath)
                end
            end
        else
            DebugPrint("[RTXF2] No files found in " .. folder)
        end
    end

    -- Load client files when on client
    if CLIENT then
        -- Wait a moment to ensure shared files have loaded
        timer.Simple(0.1, function()
            DebugPrint("[RTXF2] Loading client files...")
            
            -- Verify shared files loaded correctly
            if not FlashlightOverride then
                DebugPrint("[RTXF2] WARNING: FlashlightOverride not found - shared files may not have loaded!")
            end
            
            LoadFilesFromFolder("remixlua/cl/")
            LoadFilesFromFolder("remixlua/cl/remixapi/")
        end)
    end
    
    -- Load server files when on server (shouldn't happen in cl_rtx.lua but kept for safety)
    if SERVER then
        DebugPrint("[RTXF2] Loading server files...")
        LoadFilesFromFolder("remixlua/sv/")
    end
end

-- Load all sub-addons
LoadSubAddons()


