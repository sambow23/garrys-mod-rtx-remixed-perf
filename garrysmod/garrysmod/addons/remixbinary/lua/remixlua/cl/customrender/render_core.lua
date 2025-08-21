if not CLIENT then return end

RemixRenderCore = RemixRenderCore or {}

do
    local handlers = RemixRenderCore._handlers or {}
    local attached = RemixRenderCore._attached or {}
    local matCache = RemixRenderCore._materials or {}
    local meshRefs = RemixRenderCore._meshRefs or setmetatable({}, { __mode = "kv" })
    local statsFns = RemixRenderCore._stats or {}
    local tokens = RemixRenderCore._tokens or {}
    local rebuildSinks = RemixRenderCore._rebuildSinks or {}

    local function safeCall(id, fn, ...)
        local ok, a, b, c, d = pcall(fn, ...)
        if not ok then
            ErrorNoHalt("[RemixRenderCore] Handler '" .. tostring(id) .. "' error: " .. tostring(a) .. "\n")
            return nil
        end
        return a, b, c, d
    end

    local function installAggregator(hookName)
        if attached[hookName] then return end
        attached[hookName] = true

        hook.Add(hookName, "RemixRenderCore-" .. hookName, function(...)
            local list = handlers[hookName]
            if not list then return end

            local aggregatedReturn = nil
            for id, fn in pairs(list) do
                if isfunction(fn) then
                    local ret = select(1, safeCall(id, fn, ...))
                    if ret ~= nil then
                        aggregatedReturn = aggregatedReturn or ret
                    end
                end
            end
            return aggregatedReturn
        end)
    end

    function RemixRenderCore.Register(hookName, id, fn)
        if not hookName or not id or not isfunction(fn) then return end
        handlers[hookName] = handlers[hookName] or {}
        handlers[hookName][id] = fn
        installAggregator(hookName)
    end

    function RemixRenderCore.Unregister(hookName, id)
        local list = handlers[hookName]
        if not list then return end
        list[id] = nil
        -- Optional: remove aggregator if empty
        local hasAny = false
        for _, _ in pairs(list) do hasAny = true break end
        if not hasAny then
            handlers[hookName] = nil
            if attached[hookName] then
                hook.Remove(hookName, "RemixRenderCore-" .. hookName)
                attached[hookName] = nil
            end
        end
    end

    RemixRenderCore._handlers = handlers
    RemixRenderCore._attached = attached
    RemixRenderCore._materials = matCache
    RemixRenderCore._meshRefs = meshRefs
    RemixRenderCore._stats = statsFns
    RemixRenderCore._tokens = tokens
    RemixRenderCore._rebuildSinks = rebuildSinks

    function RemixRenderCore.GetMaterial(name)
        if not name or name == "" then name = "debug/debugwhite" end
        local mat = matCache[name]
        if mat ~= nil then return mat end
        mat = Material(name)
        matCache[name] = mat
        return mat
    end

    function RemixRenderCore.TrackMesh(meshObj)
        if not meshObj then return end
        meshRefs[meshObj] = true
    end

    function RemixRenderCore.DestroyTrackedMeshes()
        for m, _ in pairs(meshRefs) do
            if m and m.Destroy then
                m:Destroy()
            end
            meshRefs[m] = nil
        end
    end

    -- Debounce utility and rebuild dispatch
    local debounceTimers = {}
    function RemixRenderCore.Debounce(id, delay, fn)
        if not id or not isfunction(fn) then return end
        delay = delay or 0.2
        if debounceTimers[id] then
            timer.Remove(debounceTimers[id])
        end
        local tname = "RemixDebounce-" .. id
        debounceTimers[id] = tname
        timer.Create(tname, delay, 1, function()
            debounceTimers[id] = nil
            fn()
        end)
    end

    function RemixRenderCore.RegisterRebuildSink(id, fn)
        if not id or not isfunction(fn) then return end
        rebuildSinks[id] = fn
    end

    function RemixRenderCore.NewToken(name)
        if not name then name = tostring(SysTime()) end
        local tok = { name = name, cancelled = false }
        local prev = tokens[name]
        if prev then prev.cancelled = true end
        tokens[name] = tok
        return tok
    end

    function RemixRenderCore.CancelToken(name)
        local tok = tokens[name]
        if tok then tok.cancelled = true end
    end

    function RemixRenderCore.RequestRebuild(reason)
        RemixRenderCore.Debounce("GlobalRebuild", 0.25, function()
            for id, fn in pairs(rebuildSinks) do
                local token = RemixRenderCore.NewToken(id)
                safeCall(id, fn, token, reason)
            end
        end)
    end

    -- Unified capture mode toggle
    local captureConVar = CreateClientConVar("rtx_capture_mode", "0", true, false, "RTX Remix capture mode")
    cvars.AddChangeCallback("rtx_capture_mode", function(_, _, new)
        local on = (new == "1")
        RunConsoleCommand("r_drawworld", on and "0" or "1")
        RunConsoleCommand("r_drawstaticprops", on and "0" or "1")
    end, "RemixRenderCoreCapture")

    -- Stats registry for unified debug overlay
    function RemixRenderCore.RegisterStats(id, fn)
        if not id or not isfunction(fn) then return end
        statsFns[id] = fn
    end

    function RemixRenderCore.UnregisterStats(id)
        statsFns[id] = nil
    end

    local debugConVar = CreateClientConVar("rtx_render_debug", "0", true, false, "Show Remix render debug overlay")
    hook.Add("HUDPaint", "RemixRenderCoreDebug", function()
        if not debugConVar:GetBool() then return end
        local x, y = 10, 10
        draw.SimpleText("Remix Render Debug", "DermaDefaultBold", x, y, Color(255,255,0))
        y = y + 16
        for id, fn in pairs(statsFns) do
            if isfunction(fn) then
                local ok, line = pcall(fn)
                if ok and line and line ~= "" then
                    draw.SimpleText(line, "DermaDefault", x, y, Color(255,255,255))
                    y = y + 14
                end
            end
        end
    end)

    -- Console helpers
    concommand.Add("rtx_rebuild_all", function()
        RemixRenderCore.RequestRebuild("console")
    end)

    concommand.Add("rtx_clear_caches", function()
        RemixRenderCore.DestroyTrackedMeshes()
        for k in pairs(matCache) do matCache[k] = nil end
        print("[RemixRenderCore] Cleared mesh/material caches.")
    end)

    -- Unified configuration menu
    hook.Add("PopulateToolMenu", "RemixUnifiedMenu", function()
        spawnmenu.AddToolMenuOption("Utilities", "User", "RTX_Remix_Rendering", "RTX Remix Rendering", "", "", function(panel)
            panel:ClearControls()

            panel:CheckBox("Enable Custom World Rendering", "rtx_mwr")
            panel:ControlHelp("Renders the world using chunked meshes")

            panel:CheckBox("Remix Capture Mode", "rtx_capture_mode")
            panel:ControlHelp("Toggles engine draw flags for RTX Remix capture")

            panel:CheckBox("Show Unified Debug Overlay", "rtx_render_debug")

            panel:NumSlider("World Chunk Size", "rtx_mwr_chunk_size", 4096, 65536, 0)
            panel:NumSlider("World Distance (0=off)", "rtx_mwr_distance", 0, 524288, 0)
            panel:CheckBox("World PVS Culling", "rtx_mwr_pvs_cull")
            panel:TextEntry("World Material Whitelist", "rtx_mwr_mat_whitelist")
            panel:TextEntry("World Material Blacklist", "rtx_mwr_mat_blacklist")
            panel:NumSlider("Static Props Bin Size", "rtx_spr_bin_size", 1024, 65536, 0)
            panel:NumSlider("Displacements Bin Size", "rtx_cdr_bin_size", 1024, 65536, 0)

            panel:Help("")
            panel:CheckBox("Displacements Enable", "rtx_cdr_enable")
            panel:CheckBox("Displacements Debug", "rtx_cdr_debug")
            panel:CheckBox("Displacements Wireframe", "rtx_cdr_wireframe")
            panel:NumSlider("Displacements Distance", "rtx_cdr_distance", 0, 524288, 0)
            panel:TextEntry("Displacement Mat Whitelist", "rtx_cdr_mat_whitelist")
            panel:TextEntry("Displacement Mat Blacklist", "rtx_cdr_mat_blacklist")

            panel:Help("")
            panel:CheckBox("Static Props Enable", "rtx_spr_enable")
            panel:CheckBox("Static Props Debug", "rtx_spr_debug")
            panel:NumSlider("Static Props Distance", "rtx_spr_distance", 0, 524288, 0)
            panel:TextEntry("Static Props Mat Whitelist", "rtx_spr_mat_whitelist")
            panel:TextEntry("Static Props Mat Blacklist", "rtx_spr_mat_blacklist")
        end)
    end)

    -- Global cleanup
    hook.Add("ShutDown", "RemixRenderCoreCleanup", function()
        RemixRenderCore.DestroyTrackedMeshes()
        for k in pairs(matCache) do matCache[k] = nil end
        for k in pairs(statsFns) do statsFns[k] = nil end
    end)
end

return RemixRenderCore


