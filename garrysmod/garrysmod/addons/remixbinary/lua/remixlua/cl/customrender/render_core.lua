if not CLIENT then return end

RemixRenderCore = RemixRenderCore or {}

do
    local handlers = RemixRenderCore._handlers or {}
    local attached = RemixRenderCore._attached or {}
    local matCache = RemixRenderCore._materials or {}
    local meshRefs = RemixRenderCore._meshRefs or {}
    local statsFns = RemixRenderCore._stats or {}
    local tokens = RemixRenderCore._tokens or {}
    local rebuildSinks = RemixRenderCore._rebuildSinks or {}
    -- Render queues and frame/job state
    local queues = RemixRenderCore._queues or { opaque = { buckets = {}, order = {} }, translucent = { buckets = {}, order = {} } }
    local frameState = RemixRenderCore._frame or { began = false, skybox = false }
    local jobs = RemixRenderCore._jobs or {}
    local offscreenCount = RemixRenderCore._offscreenCount or 0
    local frameBudgetHistory = RemixRenderCore._frameBudgetHistory or {}
    local FRAME_BUDGET_SAMPLES = 10

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
        queues.opaque = { buckets = {}, order = {} }
        queues.translucent = { buckets = {}, order = {} }
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
        -- bucket by material to avoid per-frame material name sorting
        local buckets = q.buckets
        local order = q.order
        local mat = item.material
        local bucket = buckets[mat]
        if not bucket then
            bucket = {}
            buckets[mat] = bucket
            order[#order + 1] = mat
        end
        bucket[#bucket + 1] = item
    end

    -- Depth sort helper for translucent meshes
    local function getItemDepth(item, camPos)
        if not item.matrix then return 0 end
        local pos = item.matrix:GetTranslation()
        return pos:DistToSqr(camPos)
    end

    local function flushQueue(queue, translucent)
        if not queue or not queue.order then return end
        local lastMat = nil
        local order = queue.order
        local buckets = queue.buckets
        
        -- For translucent, we need depth sorting
        if translucent then
            local camPos = EyePos()
            local allItems = {}
            
            -- Collect all items from all buckets
            for i = 1, #order do
                local mat = order[i]
                local bucket = buckets[mat]
                if bucket and #bucket > 0 then
                    for j = 1, #bucket do
                        allItems[#allItems + 1] = bucket[j]
                    end
                end
            end
            
            -- Sort back-to-front by distance
            table.sort(allItems, function(a, b)
                return getItemDepth(a, camPos) > getItemDepth(b, camPos)
            end)
            
            -- Render sorted items
            for i = 1, #allItems do
                local it = allItems[i]
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
        else
            -- Opaque: bucket by material (no sorting needed)
            for i = 1, #order do
                local mat = order[i]
                local bucket = buckets[mat]
                if bucket and #bucket > 0 then
                    if mat ~= lastMat then
                        render.SetMaterial(mat)
                        lastMat = mat
                    end
                    for j = 1, #bucket do
                        local it = bucket[j]
                        if it._ncolor then
                            render.SetColorModulation(it._ncolor.r, it._ncolor.g, it._ncolor.b)
                        end
                        if it.matrix then cam.PushModelMatrix(it.matrix) end
                        it.mesh:Draw()
                        if it.matrix then cam.PopModelMatrix() end
                        if it._ncolor then render.SetColorModulation(1, 1, 1) end
                    end
                end
            end
        end
    end

    function RemixRenderCore.FlushPass(translucent)
        if not frameState.began then return end
        if translucent then
            flushQueue(queues.translucent, true)
        else
            flushQueue(queues.opaque, false)
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
    RemixRenderCore._offscreenCount = offscreenCount
    RemixRenderCore._frameBudgetHistory = frameBudgetHistory

    -- ============================
    -- Offscreen RT Tracking
    -- ============================
    function RemixRenderCore.PushOffscreen()
        offscreenCount = (offscreenCount or 0) + 1
        RemixRenderCore._offscreenCount = offscreenCount
    end

    function RemixRenderCore.PopOffscreen()
        if not offscreenCount or offscreenCount == 0 then
            ErrorNoHalt("[RemixRenderCore] PopOffscreen called without matching Push!\n")
            offscreenCount = 0
            RemixRenderCore._offscreenCount = 0
            return
        end
        offscreenCount = offscreenCount - 1
        RemixRenderCore._offscreenCount = offscreenCount
    end

    function RemixRenderCore.IsOffscreen()
        return (offscreenCount or 0) > 0
    end

    -- ============================
    -- Shared Material Filtering & Caching
    -- ============================
    local _matcherCache = {}
    local _matcherCacheOrder = {}
    local MAX_MATCHER_CACHE = 100
    
    -- Material name lowercase cache
    local _lowerCache = setmetatable({}, {
        __index = function(t, str)
            if not str then return "" end
            local lower = string.lower(str)
            t[str] = lower
            return lower
        end
    })
    
    -- Centralized PVS cache
    local _pvsCache = nil
    local _pvsFrame = -1
    local _pvsLastLeaf = nil
    local _pvsUnavailable = false
    
    function RemixRenderCore.IsPVSValid(pvs)
        if not pvs then return false end
        for _, v in pairs(pvs) do
            if v then return true end
        end
        return false
    end
    
    function RemixRenderCore.GetPVS(eyePos)
        if _pvsUnavailable or not NikNaks or not NikNaks.CurrentMap or not eyePos then
            return nil
        end
        
        local frame = FrameNumber()
        if _pvsFrame == frame and RemixRenderCore.IsPVSValid(_pvsCache) then
            return _pvsCache
        end
        
        -- Try cached leaf lookup first
        if NikNaks.CurrentMap.PointInLeafCache then
            local leaf, changed = NikNaks.CurrentMap:PointInLeafCache(0, eyePos, _pvsLastLeaf)
            if not changed and RemixRenderCore.IsPVSValid(_pvsCache) then
                return _pvsCache
            end
            _pvsLastLeaf = leaf
        end
        
        -- Calculate new PVS
        local ok, newPVS = pcall(function() return NikNaks.CurrentMap:PVSForOrigin(eyePos) end)
        if ok and RemixRenderCore.IsPVSValid(newPVS) then
            _pvsCache = newPVS
            _pvsFrame = frame
            return _pvsCache
        elseif not ok then
            -- PVS is broken for this map, disable permanently
            _pvsUnavailable = true
            _pvsCache = nil
            print("[RemixRenderCore] PVS unavailable for this map (invalid cluster data), disabling PVS culling")
        end
        
        return nil
    end
    
    function RemixRenderCore.ResetPVS()
        _pvsCache = nil
        _pvsFrame = -1
        _pvsLastLeaf = nil
        _pvsUnavailable = false
    end
    
    function RemixRenderCore.GetLowerCase(str)
        return _lowerCache[str]
    end
    
    function RemixRenderCore.BuildMatcherList(str)
        if not str or str == "" then return {} end
        local cached = _matcherCache[str]
        if cached then return cached end
        local list = {}
        for token in string.gmatch(str, "[^,]+") do
            token = string.Trim(string.lower(token))
            if token ~= "" then list[#list+1] = token end
        end
        
        -- LRU eviction if cache is full
        if #_matcherCacheOrder >= MAX_MATCHER_CACHE then
            local oldest = table.remove(_matcherCacheOrder, 1)
            _matcherCache[oldest] = nil
        end
        
        _matcherCache[str] = list
        _matcherCacheOrder[#_matcherCacheOrder + 1] = str
        return list
    end

    function RemixRenderCore.IsMaterialAllowed(matName, whitelist, blacklist)
        if not matName then return false end
        local lname = _lowerCache[matName]
        
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
    -- Spatial Utilities
    -- ============================
    -- Integer-based chunk key hashing (avoids string concatenation)
    function RemixRenderCore.HashChunkKey(x, y, z)
        -- Use bit operations for fast hashing
        -- Supports coordinates -2048 to 2047 per axis (12 bits each, 36 bits total)
        x = bit.band(x + 2048, 0xFFF)
        y = bit.band(y + 2048, 0xFFF)
        z = bit.band(z + 2048, 0xFFF)
        return bit.bor(bit.lshift(x, 24), bit.lshift(y, 12), z)
    end
    
    -- Distance culling with epsilon to prevent popping at boundaries
    function RemixRenderCore.ShouldCullByDistance(pos, playerPos, maxDist)
        if maxDist <= 0 then return false end
        local epsilon = maxDist * 0.05 -- 5% hysteresis
        return pos:DistToSqr(playerPos) > ((maxDist + epsilon) * (maxDist + epsilon))
    end

    local matCacheOrder = RemixRenderCore._matCacheOrder or {}
    local matCacheAccess = RemixRenderCore._matCacheAccess or {}
    local MAX_MATERIAL_CACHE = 500
    RemixRenderCore._matCacheOrder = matCacheOrder
    RemixRenderCore._matCacheAccess = matCacheAccess
    
    function RemixRenderCore.GetMaterial(name)
        if not name or name == "" then name = "debug/debugwhite" end
        local mat = matCache[name]
        if mat ~= nil then
            -- Update access time for LRU
            matCacheAccess[name] = SysTime()
            return mat
        end
        
        -- LRU eviction if cache is full - evict least recently used
        if #matCacheOrder >= MAX_MATERIAL_CACHE then
            local oldestName = nil
            local oldestTime = math.huge
            for i = 1, #matCacheOrder do
                local n = matCacheOrder[i]
                local t = matCacheAccess[n] or 0
                if t < oldestTime then
                    oldestTime = t
                    oldestName = n
                end
            end
            if oldestName then
                matCache[oldestName] = nil
                matCacheAccess[oldestName] = nil
                for i = 1, #matCacheOrder do
                    if matCacheOrder[i] == oldestName then
                        table.remove(matCacheOrder, i)
                        break
                    end
                end
            end
        end
        
        mat = Material(name)
        matCache[name] = mat
        matCacheOrder[#matCacheOrder + 1] = name
        matCacheAccess[name] = SysTime()
        return mat
    end

    -- ============================
    -- Lightweight Job Scheduler
    -- ============================
    local jobArray = {}
    local jobsDirty = false
    
    function RemixRenderCore.ScheduleJob(id, fn)
        if not id or not isfunction(fn) then return end
        if not jobs[id] then
            jobsDirty = true
        end
        jobs[id] = fn
    end

    function RemixRenderCore.CancelJob(id)
        if jobs[id] then
            jobs[id] = nil
            jobsDirty = true
        end
    end

    -- Smoothed frame budget calculation
    function RemixRenderCore.UpdateFrameBudget(spent, currentBudget)
        currentBudget = currentBudget or 0.003
        
        -- Add to history
        frameBudgetHistory[#frameBudgetHistory + 1] = spent
        if #frameBudgetHistory > FRAME_BUDGET_SAMPLES then
            table.remove(frameBudgetHistory, 1)
        end
        
        -- Calculate exponential moving average
        local avg = 0
        local weight = 1.0
        local totalWeight = 0
        for i = #frameBudgetHistory, 1, -1 do
            avg = avg + frameBudgetHistory[i] * weight
            totalWeight = totalWeight + weight
            weight = weight * 0.8
        end
        avg = avg / totalWeight
        
        -- Adjust budget based on average, not single frame
        local newBudget = currentBudget
        if avg > currentBudget * 1.3 then
            newBudget = math.max(0.001, currentBudget * 0.95)
        elseif avg < currentBudget * 0.7 then
            newBudget = math.min(0.008, currentBudget * 1.05)
        end
        
        return newBudget
    end

    function RemixRenderCore.StepJobs(budgetMs)
        budgetMs = budgetMs or 1.5 / 1000
        
        -- Rebuild job array if dirty
        if jobsDirty then
            jobArray = {}
            for id, fn in pairs(jobs) do
                jobArray[#jobArray + 1] = {id = id, fn = fn}
            end
            jobsDirty = false
        end
        
        -- Process jobs using array iteration (faster than pairs)
        local start = SysTime()
        local i = 1
        while i <= #jobArray do
            local job = jobArray[i]
            local ok, res = pcall(job.fn)
            if not ok then
                ErrorNoHalt("[RemixRenderCore] Job '" .. tostring(job.id) .. "' error: " .. tostring(res) .. "\n")
                jobs[job.id] = nil
                table.remove(jobArray, i)
            elseif res == false then
                jobs[job.id] = nil
                table.remove(jobArray, i)
            else
                i = i + 1
            end
            if SysTime() - start > budgetMs then break end
        end
    end

    function RemixRenderCore.TrackMesh(meshObj)
        if not meshObj then return end
        meshRefs[meshObj] = true
    end

    function RemixRenderCore.DestroyMesh(meshObj)
        if not meshObj then return false end
        if not meshRefs[meshObj] then return false end
        
        local ok, err = pcall(function()
            if meshObj.Destroy then
                meshObj:Destroy()
            end
        end)
        
        if not ok then
            ErrorNoHalt("[RemixRenderCore] Failed to destroy mesh: " .. tostring(err) .. "\n")
        end
        
        meshRefs[meshObj] = nil
        return ok
    end

    function RemixRenderCore.DestroyTrackedMeshes()
        -- Collect meshes to destroy first (don't modify table during iteration)
        local toDestroy = {}
        for m, _ in pairs(meshRefs) do
            toDestroy[#toDestroy + 1] = m
        end
        
        local destroyed = 0
        local failed = 0
        
        -- Now safely destroy them
        for i = 1, #toDestroy do
            local m = toDestroy[i]
            if RemixRenderCore.DestroyMesh(m) then
                destroyed = destroyed + 1
            else
                failed = failed + 1
            end
        end
        
        if failed > 0 then
            ErrorNoHalt("[RemixRenderCore] Failed to destroy " .. failed .. " meshes (" .. destroyed .. " succeeded)\n")
        end
        
        return destroyed, failed
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
        RemixRenderCore.ResetPVS()
    end)
    
    hook.Add("PostCleanupMap", "RemixRenderCoreMapCleanup", function()
        RemixRenderCore.ResetPVS()
    end)
end

return RemixRenderCore


