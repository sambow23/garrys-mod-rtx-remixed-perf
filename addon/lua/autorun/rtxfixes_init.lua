if SERVER then
    cleanup.Register("rtx_lights")
end

if CLIENT then
    -- RTX binary module is now provided by the injected DLL
    -- Check if RTX functions are available
    if SetEnableRaytracing then
        print("[RTX] RTX Remix binary integration detected!")
    else
        print("[RTX] Warning: RTX Remix binary integration not found. Make sure the injector is running.")
    end
end

-- Disabled Remix API Light lua bindings

--     -- Draw lights each frame
--     hook.Add("PostDrawOpaqueRenderables", "rtx_fixes_render", function()
--         local count = 0
--         for _, ent in ipairs(ents.FindByClass("base_rtx_light")) do
--             if IsValid(ent) and ent.rtxLightHandle then
--                 count = count + 1
--             end
--         end
--         DrawRTXLights()
--     end)

--         -- Add cleanup hook
--     hook.Add("PostCleanupMap", "rtx_fixes_cleanup", function()
--         -- Cleanup all RTX lights
--         for _, ent in ipairs(ents.FindByClass("base_rtx_light")) do
--             if IsValid(ent) and ent.rtxLightHandle then
--                 pcall(function()
--                     DestroyRTXLight(ent.rtxLightHandle)
--                 end)
--                 ent.rtxLightHandle = nil
--             end
--         end
--     end)
-- end