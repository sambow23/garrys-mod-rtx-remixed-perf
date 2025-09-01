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
    -- Render queues and frame/job state
    local queues = RemixRenderCore._queues or { opaque = {}, translucent = {} }
    local frameState = RemixRenderCore._frame or { began = false, skybox = false }
    local jobs = RemixRenderCore._jobs or {}

    local function safeCall(id, fn, ...)
        local ok, a, b, c, d = pcall(fn, ...)
        if not ok then
            ErrorNoHalt("[RemixRenderCore] Handler '" .. tostring(id) .. "' error: " .. tostring(a) .. "\n")
            return nil
        end
        return a, b, c, d
    end

    -- ============================
    -- Frame Orchestration + Render Queue
    -- ============================
    function RemixRenderCore.BeginFrame(_, bSkybox)
        -- Clear queues once per opaque frame begin
        queues.opaque = {}
        queues.translucent = {}
        frameState.began = true
        frameState.skybox = bSkybox or false
        -- Advance scheduled jobs conservatively
        RemixRenderCore.StepJobs(0.0015)
    end

    local function normalizeColor(col)
        if not col then return nil end
        if istable(col) and col.r then
            return { r = (col.r or 255) / 255, g = (col.g or 255) / 255, b = (col.b or 255) / 255 }
        end
        return nil
    end

    function RemixRenderCore.Submit(item)
        -- item = { material=IMaterial, mesh=IMesh, matrix=Matrix|nil, translucent=bool|nil, color=Color|{r,g,b}|nil }
        if not item or not item.material or not item.mesh then return end
        local q = item.translucent and queues.translucent or queues.opaque
        -- store normalized color for fast modulation
        if item.color then item._ncolor = normalizeColor(item.color) end
        q[#q + 1] = item
    end

    local function flushQueue(queue)
        if #queue == 0 then return end
        -- Sort by material to reduce state changes
        table.sort(queue, function(a, b)
            local an = a.material and a.material:GetName() or ""
            local bn = b.material and b.material:GetName() or ""
            return an < bn
        end)
        local lastMat = nil
        for i = 1, #queue do
            local it = queue[i]
            if it.material ~= lastMat then
                render.SetMaterial(it.material)
                lastMat = it.material
            end
            if it._ncolor then
                render.SetColorModulation(it._ncolor.r, it._ncolor.g, it._ncolor.b)
            end
            if it.matrix then cam.PushModelMatrix(it.matrix) end
            it.mesh:Draw()
            if it.matrix then cam.PopModelMatrix() end
            if it._ncolor then render.SetColorModulation(1, 1, 1) end
        end
    end

    function RemixRenderCore.FlushPass(translucent)
        if not frameState.began then return end
        if translucent then
            flushQueue(queues.translucent)
        else
            flushQueue(queues.opaque)
        end
        -- Do not reset began flag; multiple flushes per frame are okay
    end

    local function installAggregator(hookName)
        if attached[hookName] then return end
        attached[hookName] = true

        hook.Add(hookName, "RemixRenderCore-" .. hookName, function(...)
            local list = handlers[hookName]
            if not list then return end

            -- Build ordered call list by priority (ascending), then id
            local ordered = {}
            for id, entry in pairs(list) do
                if isfunction(entry) then
                    ordered[#ordered + 1] = { id = id, fn = entry, prio = 100 }
                elseif istable(entry) and isfunction(entry.fn) then
                    ordered[#ordered + 1] = { id = id, fn = entry.fn, prio = tonumber(entry.prio) or 100 }
                end
            end
            table.sort(ordered, function(a, b)
                if a.prio == b.prio then return tostring(a.id) < tostring(b.id) end
                return a.prio < b.prio
            end)

            local aggregatedReturn = nil
            for i = 1, #ordered do
                local it = ordered[i]
                local ret = select(1, safeCall(it.id, it.fn, ...))
                if ret ~= nil then
                    aggregatedReturn = aggregatedReturn or ret
                end
            end
            return aggregatedReturn
        end)
    end

    function RemixRenderCore.Register(hookName, id, fn)
        if not hookName or not id or not fn then return end
        handlers[hookName] = handlers[hookName] or {}
        if isfunction(fn) then
            handlers[hookName][id] = fn
        elseif istable(fn) and isfunction(fn.fn) then
            handlers[hookName][id] = { fn = fn.fn, prio = tonumber(fn.prio) or 100 }
        else
            return
        end
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
    RemixRenderCore._queues = queues
    RemixRenderCore._frame = frameState
    RemixRenderCore._jobs = jobs

    -- ============================
    -- Shared Material Filtering
    -- ============================
    function RemixRenderCore.BuildMatcherList(str)
        local list = {}
        if not str or str == "" then return list end
        for token in string.gmatch(str, "[^,]+") do
            token = string.Trim(string.lower(token))
            if token ~= "" then list[#list+1] = token end
        end
        return list
    end

    function RemixRenderCore.IsMaterialAllowed(matName, whitelist, blacklist)
        if not matName then return false end
        local lname = string.lower(matName)
        
        -- Check blacklist first
        local bl = RemixRenderCore.BuildMatcherList(blacklist)
        for i = 1, #bl do
            if string.find(lname, bl[i], 1, true) then return false end
        end
        
        -- Check whitelist
        local wl = RemixRenderCore.BuildMatcherList(whitelist)
        if #wl == 0 then return true end -- No whitelist means allow all
        for i = 1, #wl do
            if string.find(lname, wl[i], 1, true) then return true end
        end
        return false
    end

    -- Spatial binning utilities removed; no longer used

    -- ============================
    -- Bounds Calculation Utilities
    -- ============================
    function RemixRenderCore.CreateBounds()
        return {
            mins = Vector(math.huge, math.huge, math.huge),
            maxs = Vector(-math.huge, -math.huge, -math.huge)
        }
    end

    function RemixRenderCore.UpdateBounds(bounds, pos)
        if pos.x < bounds.mins.x then bounds.mins.x = pos.x end
        if pos.y < bounds.mins.y then bounds.mins.y = pos.y end
        if pos.z < bounds.mins.z then bounds.mins.z = pos.z end
        if pos.x > bounds.maxs.x then bounds.maxs.x = pos.x end
        if pos.y > bounds.maxs.y then bounds.maxs.y = pos.y end
        if pos.z > bounds.maxs.z then bounds.maxs.z = pos.z end
    end

    function RemixRenderCore.GetBoundsCenter(mins, maxs)
        return (mins + maxs) * 0.5
    end

    -- ============================
    -- Vertex Validation
    -- ============================
    function RemixRenderCore.ValidateVertex(pos)
        -- Check for nil or invalid structure
        if not pos or not pos.x or not pos.y or not pos.z then
            return false
        end
        
        -- Check for NaN (NaN != NaN in Lua)
        if pos.x ~= pos.x or pos.y ~= pos.y or pos.z ~= pos.z then
            return false
        end
        
        -- Check for extreme values
        local maxCoord = 16384
        if math.abs(pos.x) > maxCoord or 
           math.abs(pos.y) > maxCoord or 
           math.abs(pos.z) > maxCoord then
            return false
        end
        
        return true
    end

    -- ============================
    -- Debug Utilities
    -- ============================
    local debugPrefixes = {}
    
    function RemixRenderCore.CreateDebugPrint(prefix, convar)
        debugPrefixes[prefix] = convar
        return function(...)
            if convar and convar:GetBool() then
                print("[" .. prefix .. "]", ...)
            end
        end
    end

    -- ============================
    -- Distance Culling Helper
    -- ============================
    function RemixRenderCore.ShouldCullByDistance(pos, playerPos, maxDist)
        if maxDist <= 0 then return false end
        return pos:DistToSqr(playerPos) > (maxDist * maxDist)
    end

    function RemixRenderCore.GetMaterial(name)
        if not name or name == "" then name = "debug/debugwhite" end
        local mat = matCache[name]
        if mat ~= nil then return mat end
        mat = Material(name)
        matCache[name] = mat
        return mat
    end

    -- ============================
    -- Lightweight Job Scheduler
    -- ============================
    function RemixRenderCore.ScheduleJob(id, fn)
        if not id or not isfunction(fn) then return end
        jobs[id] = fn
    end

    function RemixRenderCore.CancelJob(id)
        jobs[id] = nil
    end

    function RemixRenderCore.StepJobs(budgetMs)
        budgetMs = budgetMs or 1.5 / 1000
        local start = SysTime()
        for id, fn in pairs(jobs) do
            local ok = true
            local res
            ok, res = pcall(fn)
            if not ok or res == false then
                jobs[id] = nil
            end
            if SysTime() - start > budgetMs then break end
        end
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

            panel:Help("2D Skybox")
            panel:CheckBox("2D Skybox Enable", "rtx_sky2d_enable")
            panel:TextEntry("2D Skybox Name Override", "rtx_sky2d_name")
            panel:NumSlider("2D Skybox Brightness", "rtx_sky2d_brightness", 0, 5, 2)
            panel:CheckBox("2D Skybox Debug", "rtx_sky2d_debug")
            panel:CheckBox("2D Skybox Use DepthRange", "rtx_sky2d_use_depthrange")
            panel:NumSlider("2D Skybox Depth Near", "rtx_sky2d_depthnear", 0, 1, 3)
            panel:CheckBox("2D Skybox Swap Up/Down", "rtx_sky2d_swap_ud")
            panel:Help("Per-face rotation (deg)")
            panel:NumSlider("Rot Right", "rtx_sky2d_rot_rt", 0, 360, 0)
            panel:NumSlider("Rot Left", "rtx_sky2d_rot_lf", 0, 360, 0)
            panel:NumSlider("Rot Back", "rtx_sky2d_rot_bk", 0, 360, 0)
            panel:NumSlider("Rot Front", "rtx_sky2d_rot_ft", 0, 360, 0)
            panel:NumSlider("Rot Up", "rtx_sky2d_rot_up", 0, 360, 0)
            panel:NumSlider("Rot Down", "rtx_sky2d_rot_dn", 0, 360, 0)

            panel:NumSlider("World Chunk Size", "rtx_mwr_chunk_size", 4096, 65536, 0)
            panel:NumSlider("World Distance (0=off)", "rtx_mwr_distance", 0, 524288, 0)
            panel:TextEntry("World Material Whitelist", "rtx_mwr_mat_whitelist")
            panel:TextEntry("World Material Blacklist", "rtx_mwr_mat_blacklist")
            -- Removed bin size controls

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

    -- Centralized flush hooks: begin frame on PreDrawOpaque, flush on PostDraw* passes
    RemixRenderCore.Register("PreDrawOpaqueRenderables", "RemixFrame-Begin", { fn = function(bDrawingDepth, bDrawingSkybox)
        RemixRenderCore.BeginFrame(bDrawingDepth, bDrawingSkybox)
    end, prio = 0 })

    RemixRenderCore.Register("PostDrawOpaqueRenderables", "RemixFrame-FlushOpaque", { fn = function()
        RemixRenderCore.FlushPass(false)
    end, prio = 1000 })

    RemixRenderCore.Register("PostDrawTranslucentRenderables", "RemixFrame-FlushTrans", { fn = function()
        RemixRenderCore.FlushPass(true)
    end, prio = 1000 })

    -- Global cleanup
    hook.Add("ShutDown", "RemixRenderCoreCleanup", function()
        RemixRenderCore.DestroyTrackedMeshes()
        for k in pairs(matCache) do matCache[k] = nil end
        for k in pairs(statsFns) do statsFns[k] = nil end
    end)
end

return RemixRenderCore


