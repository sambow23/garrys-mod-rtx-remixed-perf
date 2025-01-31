if SERVER then
    cleanup.Register("rtx_lights")
end

if CLIENT then
    require((BRANCH == "x86-64" or BRANCH == "chromium" ) and "RTXFixesBinary" or "RTXFixesBinary_32bit")

    -- Add console command to spawn a test light
    concommand.Add("rtx_test_light", function(ply)
        -- ... existing code ...
    end)

    local hook_name = "rtx_fixes_render"
    local function UpdateRenderHook()
        local lights = ents.FindByClass("base_rtx_light")
        local hasLights = false
        for _, ent in ipairs(lights) do
            if IsValid(ent) and ent.rtxLightHandle then
                hasLights = true
                break
            end
        end

        -- Only add hook if lights exist
        if hasLights and not hook.GetTable()["PostDrawOpaqueRenderables"][hook_name] then
            hook.Add("PostDrawOpaqueRenderables", hook_name, function()
                DrawRTXLights()
            end)
        -- Remove hook if no lights exist
        elseif not hasLights and hook.GetTable()["PostDrawOpaqueRenderables"][hook_name] then
            hook.Remove("PostDrawOpaqueRenderables", hook_name)
        end
    end

    -- Monitor light creation/destruction
    hook.Add("OnEntityCreated", "rtx_fixes_monitor", function(ent)
        if IsValid(ent) and ent:GetClass() == "base_rtx_light" then
            UpdateRenderHook()
        end
    end)

    hook.Add("EntityRemoved", "rtx_fixes_monitor", function(ent)
        if IsValid(ent) and ent:GetClass() == "base_rtx_light" then
            UpdateRenderHook()
        end
    end)

    -- Add cleanup hook
    hook.Add("PostCleanupMap", "rtx_fixes_cleanup", function()
        -- Cleanup all RTX lights
        for _, ent in ipairs(ents.FindByClass("base_rtx_light")) do
            if IsValid(ent) and ent.rtxLightHandle then
                pcall(function()
                    DestroyRTXLight(ent.rtxLightHandle)
                end)
                ent.rtxLightHandle = nil
            end
        end
        UpdateRenderHook()
    end)
end