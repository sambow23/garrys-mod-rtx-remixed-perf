-- Places a RenderTarget camera at the local player's eyes, looking 180 degrees behind, prevents culling for dynamic entities

if SERVER then return end

local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

local REARVIEW = REARVIEW or {}
REARVIEW.rtName = "rearview_rt"
REARVIEW.matName = "rearview_rt_mat"
REARVIEW.w = 512
REARVIEW.h = 512
REARVIEW.enabled = false
REARVIEW._rendering = false
REARVIEW._panel = nil
REARVIEW.lastView = nil

-- Entity filtering for selective rendering
REARVIEW.filterMode = "dynamic_only" -- "all", "whitelist", "blacklist", "dynamic_only"
REARVIEW.classWhitelist = {} -- Set of class names to include (when filterMode = "whitelist")
REARVIEW.classBlacklist = {} -- Set of class names to exclude (when filterMode = "blacklist")
REARVIEW._hiddenEntities = {} -- Temporary storage for entities hidden during RT rendering
REARVIEW._filteredEntityCache = nil -- Cached list of entities to hide
REARVIEW._filterCacheFrame = -1 -- Frame number when cache was last built
REARVIEW._filterCacheRebuildInterval = 30 -- Rebuild cache every N frames

local function CreateRT()
    if REARVIEW.rt and REARVIEW.rt:IsError() == false then return end

    -- Create a render target and material to display it
    REARVIEW.rt = GetRenderTargetEx(
        REARVIEW.rtName,
        REARVIEW.w,
        REARVIEW.h,
        RT_SIZE_OFFSCREEN,
        MATERIAL_RT_DEPTH_SHARED,
        0,
        CREATERENDERTARGETFLAGS_HDR,
        IMAGE_FORMAT_RGBA8888
    )

    REARVIEW.mat = CreateMaterial(REARVIEW.matName, "UnlitGeneric", {
        ["$basetexture"] = REARVIEW.rt:GetName(),
        ["$vertexcolor"] = 1,
        ["$vertexalpha"] = 1,
        ["$translucent"] = 1,
        ["$no_fullbright"] = 1
    })

    -- Ensure material uses our RT as base texture
    if REARVIEW.mat and REARVIEW.rt then
        REARVIEW.mat:SetTexture("$basetexture", REARVIEW.rt)
    end
end

local function DestroyRT()
    -- GMod doesn't expose explicit destroy; just drop references
    REARVIEW.rt = nil
    REARVIEW.mat = nil
end

-- Apply size from the rearview_size convar; recreates RT and resizes panel if needed
local function ApplySizeFromConVar()
    local cv = GetConVar and GetConVar("rtx_rearview_size")
    local s = (cv and tonumber(cv:GetInt())) or REARVIEW.w or 512
    if not s or s < 1 then s = 1 end

    local changed = (REARVIEW.w ~= s) or (REARVIEW.h ~= s)
    REARVIEW.w = s
    REARVIEW.h = s

    if changed then
        DestroyRT()
        if IsValid(REARVIEW._panel) then
            REARVIEW._panel:SetSize(REARVIEW.w, REARVIEW.h)
            REARVIEW._panel:SetPos(ScrW() - REARVIEW.w - 24, ScrH() - REARVIEW.h - 160)
        end
    end
end

local function GetRearAngles()
    local lp = LocalPlayer()
    local ang = (REARVIEW.lastView and REARVIEW.lastView.angles)
        or (IsValid(lp) and lp:EyeAngles())
        or EyeAngles()
    -- Add configurable yaw offset (default 180 for rear view)
    local yawAdd = 180
    do
        local cv = GetConVar and GetConVar("rtx_rearview_yaw_add")
        if cv then yawAdd = cv:GetFloat() end
    end
    -- Lock vertical rotation: zero pitch and roll so we only rotate left/right
    return Angle(0, ang.y + yawAdd, 0)
end

-- Compute camera origin with local offsets (forward/right/up relative to yaw-only basis)
local function GetCameraOrigin()
    local lp = LocalPlayer()
    local baseOrigin = (REARVIEW.lastView and REARVIEW.lastView.origin)
        or ((IsValid(lp) and lp:EyePos()) or EyePos())
    local baseAng = (REARVIEW.lastView and REARVIEW.lastView.angles)
        or ((IsValid(lp) and lp:EyeAngles()) or EyeAngles())

    -- Use yaw-only for offset basis to avoid vertical drift when pitch changes
    local yawOnly = Angle(0, baseAng.y, 0)
    local fwd = yawOnly:Forward()
    local right = yawOnly:Right()
    local up = Vector(0, 0, 1)

    local offF = 0
    local offR = 0
    local offU = 0
    do
        local cvF = GetConVar and GetConVar("rtx_rearview_off_forward")
        local cvR = GetConVar and GetConVar("rtx_rearview_off_right")
        local cvU = GetConVar and GetConVar("rtx_rearview_off_up")
        if cvF then offF = cvF:GetFloat() end
        if cvR then offR = cvR:GetFloat() end
        if cvU then offU = cvU:GetFloat() end
    end

    return baseOrigin + fwd * offF + right * offR + up * offU
end

-- Check if an entity should be rendered in the rear-view RT
local function ShouldRenderEntity(ent)
    if not IsValid(ent) then return false end
    
    local class = ent:GetClass()
    
    -- Filter mode: all (render everything)
    if REARVIEW.filterMode == "all" then
        return true
    end
    
    -- Filter mode: whitelist (only render classes in the whitelist)
    if REARVIEW.filterMode == "whitelist" then
        return REARVIEW.classWhitelist[class] == true
    end
    
    -- Filter mode: blacklist (render everything except classes in the blacklist)
    if REARVIEW.filterMode == "blacklist" then
        return REARVIEW.classBlacklist[class] ~= true
    end
    
    -- Filter mode: dynamic_only (only render dynamic entities: players, NPCs, physics props, vehicles)
    if REARVIEW.filterMode == "dynamic_only" then
        -- Exclude particles and effects
        if class:find("particle") or 
           class:find("^env_sprite") or 
           class:find("^env_steam") or 
           class:find("^env_fire") or 
           class:find("^env_smokestack") or 
           class:find("^info_particle") then
            return false
        end
        
        -- Players
        if ent:IsPlayer() then return true end
        
        -- NPCs
        if ent:IsNPC() then return true end
        
        -- Vehicles
        if ent:IsVehicle() then return true end
        
        -- Ragdolls
        if class == "prop_ragdoll" or class == "class C_ClientRagdoll" then return true end
        
        -- Physics props (all physics props, not just moveable ones)
        if class == "prop_physics" or class == "prop_physics_multiplayer" or class == "prop_physics_override" then
            return true
        end
        
        -- Dynamic props
        if class == "prop_dynamic" or class == "prop_dynamic_override" then
            return true
        end
        
        -- Brush-based entities (doors, breakables, details)
        if class == "func_door" or class == "func_door_rotating" then return true end
        if class == "func_breakable" or class == "func_breakable_surf" then return true end
        if class == "func_detail" then return true end
        
        -- Other common moveable prop types
        if class:find("^prop_") and ent:GetPhysicsObject():IsValid() then
            return true
        end
        
        return false
    end
    
    return true
end

-- Rebuild the filtered entity cache
local function RebuildFilterCache()
    REARVIEW._filteredEntityCache = {}
    
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and not ShouldRenderEntity(ent) then
            REARVIEW._filteredEntityCache[#REARVIEW._filteredEntityCache + 1] = ent
        end
    end
    
    REARVIEW._filterCacheFrame = FrameNumber()
end

-- Hide entities that should not render in the RT (using cache)
local function HideFilteredEntities()
    -- Rebuild cache if stale or doesn't exist
    local currentFrame = FrameNumber()
    if not REARVIEW._filteredEntityCache or 
       (currentFrame - REARVIEW._filterCacheFrame) >= REARVIEW._filterCacheRebuildInterval then
        RebuildFilterCache()
    end
    
    REARVIEW._hiddenEntities = {}
    
    -- Use cached list instead of iterating all entities
    for i = 1, #REARVIEW._filteredEntityCache do
        local ent = REARVIEW._filteredEntityCache[i]
        if IsValid(ent) then
            local wasHidden = ent:GetNoDraw()
            if not wasHidden then
                REARVIEW._hiddenEntities[ent] = true
                ent:SetNoDraw(true)
            end
        end
    end
end

-- Restore entities that were hidden for RT rendering
local function RestoreFilteredEntities()
    for ent, _ in pairs(REARVIEW._hiddenEntities) do
        if IsValid(ent) then
            ent:SetNoDraw(false)
        end
    end
    REARVIEW._hiddenEntities = {}
end

-- Invalidate cache when entities spawn or are removed
hook.Add("OnEntityCreated", "RearView_InvalidateCache", function()
    if REARVIEW.enabled then
        REARVIEW._filteredEntityCache = nil
    end
end)

hook.Add("EntityRemoved", "RearView_InvalidateCache", function()
    if REARVIEW.enabled then
        REARVIEW._filteredEntityCache = nil
    end
end)

local function UpdateRearRT()
    if not REARVIEW.enabled then return end
    if REARVIEW._rendering then return end
    if not IsValid(LocalPlayer()) then return end

    CreateRT()
    if not REARVIEW.rt then return end

    REARVIEW._rendering = true

    -- Wrap entire render process in pcall for safety
    local success, err = pcall(function()
        render.PushRenderTarget(REARVIEW.rt)
        render.Clear(0, 0, 0, 255, true, true)

        -- Choose FOV: use rearview_fov if > 0, otherwise follow current camera fov or player's fov_desired
        local desiredFov = -1
        do
            local rvFovCv = GetConVar and GetConVar("rtx_rearview_fov")
            if rvFovCv then desiredFov = rvFovCv:GetFloat() end
        end
        local useFov
        if desiredFov and desiredFov > 0 then
            useFov = math.Clamp(desiredFov, 30, 500)
        else
            useFov = (REARVIEW.lastView and REARVIEW.lastView.fov)
                or ((GetConVar and GetConVar("fov_desired") and GetConVar("fov_desired"):GetFloat()) or 90)
        end

        local view = {
            origin = GetCameraOrigin(),
            angles = GetRearAngles(),
            x = 0,
            y = 0,
            w = REARVIEW.w,
            h = REARVIEW.h,
            fov = useFov,
            drawviewmodel = false,
            drawhud = false,
            dopostprocess = false,
            drawmonitors = false
        }

        -- Hide filtered entities before rendering
        HideFilteredEntities()

        -- Set flag to suppress particles (checked by hook below)
        REARVIEW._suppressParticles = (REARVIEW.filterMode == "dynamic_only")

        -- Render scene into our RT (flag as offscreen so other systems like skybox skip per-frame logic)
        if RenderCore and RenderCore.PushOffscreen then RenderCore.PushOffscreen() end
        render.RenderView(view)
        if RenderCore and RenderCore.PopOffscreen then RenderCore.PopOffscreen() end

        -- Clear suppression flag
        REARVIEW._suppressParticles = false

        -- Restore filtered entities after rendering
        RestoreFilteredEntities()

        render.PopRenderTarget()
    end)

    -- Always reset rendering flag and restore entities, even if error occurred
    REARVIEW._rendering = false
    REARVIEW._suppressParticles = false -- Safety: clear suppression flag
    RestoreFilteredEntities() -- Safety: ensure entities are restored even on error

    if not success then
        ErrorNoHalt("[RearView] Render error: " .. tostring(err) .. "\n")
    end
end

-- Update the RT once per frame safely
hook.Add("PreRender", "RearView_UpdateRT", function()
    if not REARVIEW.enabled then return end
    UpdateRearRT()
end)

-- Suppress translucent renderables (including particles) during RT render
hook.Add("PreDrawTranslucentRenderables", "RearView_SuppressTranslucent", function(bDrawingDepth, bDrawingSkybox)
    if REARVIEW._suppressParticles and not bDrawingDepth and not bDrawingSkybox then
        return true -- Skip translucent renderables (particles, beams, etc.)
    end
end)

-- Capture from CalcView so we follow custom camera logic provided by the gamemode/addons
-- Note: Using CalcView only (not RenderScene) to avoid redundant captures - CalcView is more accurate
hook.Add("CalcView", "RearView_CaptureView", function(ply, pos, ang, fov)
    if not REARVIEW.enabled then return end
    if REARVIEW._rendering then return end
    REARVIEW.lastView = REARVIEW.lastView or {}
    REARVIEW.lastView.origin = pos
    REARVIEW.lastView.angles = ang
    REARVIEW.lastView.fov = fov
    -- do not override CalcView; return nil
end)

-- Panel to draw the RT texture
local PANEL = {}

function PANEL:Init()
    self:SetSize(REARVIEW.w, REARVIEW.h)
    self:SetPos(ScrW() - self:GetWide() - 24, ScrH() - self:GetTall() - 160)
    self:SetMouseInputEnabled(false)
    self:SetKeyboardInputEnabled(false)
    self:SetAlpha(230)
    self:SetTooltip("Rear View Camera")

    -- Simple corner drag to resize with Shift key
    self._dragging = false
    self._dragOffset = { x = 0, y = 0 }
end

function PANEL:Paint(w, h)
    if not REARVIEW.mat then return end

    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(REARVIEW.mat)
    surface.DrawTexturedRect(0, 0, w, h)

    -- Optional border
    surface.SetDrawColor(0, 0, 0, 180)
    surface.DrawOutlinedRect(0, 0, w, h, 2)
end

vgui.Register("DRearView", PANEL, "DPanel")

local function OpenPanel()
    if IsValid(REARVIEW._panel) then REARVIEW._panel:Remove() end

    REARVIEW._panel = vgui.Create("DRearView")
    REARVIEW._panel:SetVisible(true)

    -- Make sure RT exists and mat is set
    -- Apply persisted size before creating RT
    ApplySizeFromConVar()
    CreateRT()
end

local function ClosePanel()
    if IsValid(REARVIEW._panel) then
        REARVIEW._panel:Remove()
        REARVIEW._panel = nil
    end
end

local function SetEnabled(enable)
    REARVIEW.enabled = enable and true or false

    if REARVIEW.enabled then
        OpenPanel()
    else
        ClosePanel()
    end
end

-- ConVars and commands
CreateClientConVar("rtx_rearview_enabled", "0", true, false, "Enable the rear-view RT camera to prevent culling")
CreateClientConVar("rtx_rearview_size", "1", true, false, "Rear-view panel size (square), requires toggle to re-create")
CreateClientConVar("rtx_rearview_fov", "173", true, false, "Rear-view camera FOV in degrees. Set -1 to follow player FOV (fov_desired)")
-- Movement/offset convars
CreateClientConVar("rtx_rearview_off_forward", "2000", true, false, "Rear-view local forward offset in units")
CreateClientConVar("rtx_rearview_off_right", "0", true, false, "Rear-view local right offset in units")
CreateClientConVar("rtx_rearview_off_up", "0", true, false, "Rear-view local up offset in units")
CreateClientConVar("rtx_rearview_yaw_add", "180", true, false, "Additional yaw in degrees (default 180 = look behind)")
-- Filtering convars
CreateClientConVar("rtx_rearview_filter_mode", "dynamic_only", true, false, "Filter mode: all, whitelist, blacklist, dynamic_only")

cvars.AddChangeCallback("rtx_rearview_enabled", function(convar, old, new)
    local enable = tonumber(new) == 1
    SetEnabled(enable)
end, "rearview_enabled_cb")

-- React to size changes via convar (persists across maps/sessions)
cvars.AddChangeCallback("rtx_rearview_size", function(convar, old, new)
    ApplySizeFromConVar()
end, "rearview_size_cb")

concommand.Add("rtx_rearview_toggle", function()
    local cv = GetConVar("rtx_rearview_enabled")
    if not cv then return end
    cv:SetBool(not cv:GetBool())
end, nil, "Toggle the rear-view RT camera to prevent culling")

concommand.Add("rtx_rearview_setsize", function(ply, cmd, args)
    local s = tonumber(args and args[1])
    if not s or s < 1 then return end
    RunConsoleCommand("rtx_rearview_size", tostring(math.floor(s)))
end, nil, "Set rear-view panel size (pixels)")

concommand.Add("rtx_rearview_setfov", function(ply, cmd, args)
    local f = tonumber(args and args[1])
    if not f then return end

    if f < 0 then
        RunConsoleCommand("rtx_rearview_fov", "-1")
        return
    end

    f = math.Clamp(f, 30, 500)
    RunConsoleCommand("rtx_rearview_fov", tostring(f))
end, nil, "Set rear-view camera FOV in degrees. Use -1 to follow your player FOV")

-- Offset helpers
concommand.Add("rtx_rearview_setoffset", function(ply, cmd, args)
    local f = tonumber(args and args[1])
    local r = tonumber(args and args[2])
    local u = tonumber(args and args[3])
    if not f or not r or not u then return end
    RunConsoleCommand("rtx_rearview_off_forward", tostring(f))
    RunConsoleCommand("rtx_rearview_off_right", tostring(r))
    RunConsoleCommand("rtx_rearview_off_up", tostring(u))
end, nil, "Set rear-view local offsets: forward right up")

concommand.Add("rtx_rearview_nudge", function(ply, cmd, args)
    local axis = tostring(args and args[1] or "")
    local d = tonumber(args and args[2]) or 0
    axis = string.lower(axis)
    local function add(name)
        local cv = GetConVar and GetConVar(name)
        local cur = cv and cv:GetFloat() or 0
        RunConsoleCommand(name, tostring(cur + d))
    end
    if axis == "f" or axis == "forward" then add("rtx_rearview_off_forward") return end
    if axis == "r" or axis == "right" then add("rtx_rearview_off_right") return end
    if axis == "u" or axis == "up" then add("rtx_rearview_off_up") return end
    if axis == "y" or axis == "yaw" then add("rtx_rearview_yaw_add") return end
end, nil, "Nudge an offset: rearview_nudge <f|r|u|yaw> <delta>")

concommand.Add("rtx_rearview_resetoffset", function()
    RunConsoleCommand("rtx_rearview_off_forward", "2000")
    RunConsoleCommand("rtx_rearview_off_right", "0")
    RunConsoleCommand("rtx_rearview_off_up", "0")
    RunConsoleCommand("rtx_rearview_yaw_add", "180")
end, nil, "Reset rear-view offsets and yaw to defaults")

-- Filtering commands
concommand.Add("rtx_rearview_filter_mode", function(ply, cmd, args)
    local mode = tostring(args and args[1] or "all"):lower()
    if mode ~= "all" and mode ~= "whitelist" and mode ~= "blacklist" and mode ~= "dynamic_only" then
        print("[RearView] Invalid filter mode. Options: all, whitelist, blacklist, dynamic_only")
        return
    end
    REARVIEW.filterMode = mode
    REARVIEW._filteredEntityCache = nil -- Invalidate cache on mode change
    RunConsoleCommand("rtx_rearview_filter_mode", mode)
    print("[RearView] Filter mode set to: " .. mode)
end, nil, "Set filter mode: all, whitelist, blacklist, dynamic_only")

concommand.Add("rtx_rearview_whitelist_add", function(ply, cmd, args)
    local class = tostring(args and args[1] or "")
    if class == "" then
        print("[RearView] Usage: rtx_rearview_whitelist_add <classname>")
        return
    end
    REARVIEW.classWhitelist[class] = true
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Added to whitelist: " .. class)
end, nil, "Add entity class to whitelist")

concommand.Add("rtx_rearview_whitelist_remove", function(ply, cmd, args)
    local class = tostring(args and args[1] or "")
    if class == "" then
        print("[RearView] Usage: rtx_rearview_whitelist_remove <classname>")
        return
    end
    REARVIEW.classWhitelist[class] = nil
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Removed from whitelist: " .. class)
end, nil, "Remove entity class from whitelist")

concommand.Add("rtx_rearview_whitelist_clear", function()
    REARVIEW.classWhitelist = {}
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Whitelist cleared")
end, nil, "Clear whitelist")

concommand.Add("rtx_rearview_whitelist_list", function()
    print("[RearView] Whitelist:")
    local count = 0
    for class, _ in pairs(REARVIEW.classWhitelist) do
        print("  - " .. class)
        count = count + 1
    end
    if count == 0 then
        print("  (empty)")
    end
end, nil, "List whitelisted classes")

concommand.Add("rtx_rearview_blacklist_add", function(ply, cmd, args)
    local class = tostring(args and args[1] or "")
    if class == "" then
        print("[RearView] Usage: rtx_rearview_blacklist_add <classname>")
        return
    end
    REARVIEW.classBlacklist[class] = true
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Added to blacklist: " .. class)
end, nil, "Add entity class to blacklist")

concommand.Add("rtx_rearview_blacklist_remove", function(ply, cmd, args)
    local class = tostring(args and args[1] or "")
    if class == "" then
        print("[RearView] Usage: rtx_rearview_blacklist_remove <classname>")
        return
    end
    REARVIEW.classBlacklist[class] = nil
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Removed from blacklist: " .. class)
end, nil, "Remove entity class from blacklist")

concommand.Add("rtx_rearview_blacklist_clear", function()
    REARVIEW.classBlacklist = {}
    REARVIEW._filteredEntityCache = nil -- Invalidate cache
    print("[RearView] Blacklist cleared")
end, nil, "Clear blacklist")

concommand.Add("rtx_rearview_blacklist_list", function()
    print("[RearView] Blacklist:")
    local count = 0
    for class, _ in pairs(REARVIEW.classBlacklist) do
        print("  - " .. class)
        count = count + 1
    end
    if count == 0 then
        print("  (empty)")
    end
end, nil, "List blacklisted classes")

concommand.Add("rtx_rearview_list_entities", function()
    print("[RearView] All entity classes currently in world:")
    local classes = {}
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) then
            local class = ent:GetClass()
            classes[class] = (classes[class] or 0) + 1
        end
    end
    local sorted = {}
    for class, count in pairs(classes) do
        table.insert(sorted, {class = class, count = count})
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    for _, entry in ipairs(sorted) do
        print(string.format("  %3dx %s", entry.count, entry.class))
    end
end, nil, "List all entity classes in the world")

-- Auto-create on join if convar persisted
hook.Add("InitPostEntity", "RearView_Init", function()
    if GetConVar("rtx_rearview_enabled") and GetConVar("rtx_rearview_enabled"):GetBool() then
        SetEnabled(true)
    end
    
    -- Load filter mode from convar
    local filterCv = GetConVar("rtx_rearview_filter_mode")
    if filterCv then
        local mode = filterCv:GetString():lower()
        if mode == "all" or mode == "whitelist" or mode == "blacklist" or mode == "dynamic_only" then
            REARVIEW.filterMode = mode
        end
    end
end)
