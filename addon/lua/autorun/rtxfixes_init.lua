if SERVER then
    cleanup.Register("rtx_lights")
end

if CLIENT then
    require((BRANCH == "x86-64" or BRANCH == "chromium" ) and "RTXFixesBinary" or "RTXFixesBinary_32bit")

    -- Monitor light creation/destruction for cleanup purposes only
    hook.Add("OnEntityCreated", "rtx_fixes_monitor", function(ent)
        if IsValid(ent) and ent:GetClass() == "base_rtx_light" then
            -- Call DrawRTXLights when a new light is created
            DrawRTXLights()
        end
    end)

    hook.Add("EntityRemoved", "rtx_fixes_monitor", function(ent)
        if IsValid(ent) and ent:GetClass() == "base_rtx_light" then
            -- No need to call DrawRTXLights on removal as the light is destroyed
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
    end)
end