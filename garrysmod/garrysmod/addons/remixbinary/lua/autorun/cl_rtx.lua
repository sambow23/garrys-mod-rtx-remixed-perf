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

-- Master toggle for applying a preset of render cvars
local cv_custom_render = CreateClientConVar("rtx_custom_render", "0", true, false, "Toggle Remix custom render preset")

local function ApplyCustomRenderPreset(enable)
    RunConsoleCommand("r_drawopaqueworld", enable and "0" or "1")
    RunConsoleCommand("r_drawstaticprops", enable and "0" or "1")
    RunConsoleCommand("r_DrawDisp", enable and "0" or "1")
    RunConsoleCommand("r_drawdecals", enable and "0" or "1")
    RunConsoleCommand("r_DrawDetailProps", enable and "0" or "1")
    RunConsoleCommand("rtx_mwr", enable and "1" or "0")
    RunConsoleCommand("rtx_spr_enable", enable and "1" or "0")
    RunConsoleCommand("rtx_cdr_enable", enable and "1" or "0")
end

cvars.AddChangeCallback("rtx_custom_render", function(name, oldValue, newValue)
    local enable = tonumber(newValue) == 1
    ApplyCustomRenderPreset(enable)
end, "gmrtx_custom_render_preset_cb")

-- Apply initial state on load
ApplyCustomRenderPreset(cv_custom_render:GetBool())

local function LoadSubAddons()
    local foldersToLoad = {}
    
    -- Always load shared files first
    table.insert(foldersToLoad, "remixlua/sh/")
    
    -- Load client files when on client
    if CLIENT then
        table.insert(foldersToLoad, "remixlua/cl/")
        table.insert(foldersToLoad, "remixlua/cl/remixapi/")
        table.insert(foldersToLoad, "remixlua/cl/customrender/")
    end
    
    -- Load server files when on server
    if SERVER then
        table.insert(foldersToLoad, "remixlua/sv/")
    end
    
    for _, folder in ipairs(foldersToLoad) do
        local files, _ = file.Find(folder .. "*.lua", "LUA")
        
        if files then
            DebugPrint("[gmRTX] Found " .. #files .. " files in " .. folder)
            
            for _, fileName in ipairs(files) do
                local filePath = folder .. fileName
                local success, err = pcall(include, filePath)
                
                if not success then
                    DebugPrint("[gmRTX] Warning: Failed to load sub-addon: " .. filePath .. " - Error: " .. tostring(err))
                else
                    DebugPrint("[gmRTX] Successfully loaded sub-addon: " .. filePath)
                end
            end
        else
            DebugPrint("[gmRTX] No files found in " .. folder)
        end
    end
end

-- Load all sub-addons
LoadSubAddons()

