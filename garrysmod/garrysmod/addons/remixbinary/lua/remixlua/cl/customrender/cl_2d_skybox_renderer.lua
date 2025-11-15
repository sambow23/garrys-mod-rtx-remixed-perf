if not CLIENT then return end
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

-- Custom 2D Skybox Renderer
-- Draws a 2D skybox
-- Author: CR

local cv_enable = CreateClientConVar("rtx_sky2d_enable", "1", true, false, "Enable custom 2D skybox rendering")
local cv_override = CreateClientConVar("rtx_sky2d_name", "", true, false, "Override skybox name (leave blank to use sv_skyname)")
local cv_brightness = CreateClientConVar("rtx_sky2d_brightness", "1.0", true, false, "Brightness multiplier for custom 2D skybox")
local cv_useDepthRange = CreateClientConVar("rtx_sky2d_use_depthrange", "1", true, false, "Use DepthRange(near,far) during 2D sky draw for RTX detection")
local cv_depthNear = CreateClientConVar("rtx_sky2d_depthnear", "0.999", true, false, "DepthRange near (0..1) when enabled")
local cv_depthFar  = CreateClientConVar("rtx_sky2d_depthfar",  "1.0",  true, false, "DepthRange far (0..1) when enabled")
-- Depth behavior and sizing
local cv_zTest  = CreateClientConVar("rtx_sky2d_ztest", "1", true, false, "Enable depth test during 2D sky draw")
local cv_zWrite = CreateClientConVar("rtx_sky2d_zwrites", "1", true, false, "Enable depth writes during 2D sky draw")
local cv_clearDepth = CreateClientConVar("rtx_sky2d_clear_depth", "0", true, false, "Clear depth buffer before drawing 2D sky")
local cv_size = CreateClientConVar("rtx_sky2d_size", "1", true, false, "Half-extent of the sky cube in units")
local cv_camNear = CreateClientConVar("rtx_sky2d_cam_znear", "1", true, false, "Camera z-near for 2D sky pass")
local cv_camFar  = CreateClientConVar("rtx_sky2d_cam_zfar", "65536", true, false, "Camera z-far for 2D sky pass")
local cv_disableCull = CreateClientConVar("rtx_sky2d_disable_cull", "0", true, false, "Disable backface culling when drawing sky quads")
local cv_swapUD = CreateClientConVar("rtx_sky2d_swap_ud", "0", true, false, "Swap up/down sky faces to match Source orientation")
local cv_swapLR = CreateClientConVar("rtx_sky2d_swap_lr", "1", true, false, "Swap left/right sky faces to match Source orientation")
-- Default all faces to 180 as per pictured working setup
local cv_rot_rt = CreateClientConVar("rtx_sky2d_rot_rt", "180", true, false, "Rotation deg for right face")
local cv_rot_lf = CreateClientConVar("rtx_sky2d_rot_lf", "180", true, false, "Rotation deg for left face")
local cv_rot_bk = CreateClientConVar("rtx_sky2d_rot_bk", "180", true, false, "Rotation deg for back face")
local cv_rot_ft = CreateClientConVar("rtx_sky2d_rot_ft", "180", true, false, "Rotation deg for front face")
local cv_rot_up = CreateClientConVar("rtx_sky2d_rot_up", "180", true, false, "Rotation deg for up face")
local cv_rot_dn = CreateClientConVar("rtx_sky2d_rot_dn", "180", true, false, "Rotation deg for down face")
-- Global rotation (rotates the entire cube orientation)
local cv_rot_yaw   = CreateClientConVar("rtx_sky2d_rot_yaw", "0", true, false, "Rotate entire skybox around Z (yaw) degrees")
local cv_rot_pitch = CreateClientConVar("rtx_sky2d_rot_pitch", "0", true, false, "Rotate entire skybox around Y (pitch) degrees")
local cv_rot_roll  = CreateClientConVar("rtx_sky2d_rot_roll", "0", true, false, "Rotate entire skybox around X (roll) degrees")
local cv_debug = CreateClientConVar("rtx_sky2d_debug", "0", true, false, "Debug prints for 2D skybox renderer")

local function DebugPrint(...)
    if cv_debug:GetBool() then
        print("[2D Skybox]", ...)
    end
end

-- Cache materials per sky name
local skyCache = {}
local lastDrawFrame = -1

-- Cached ConVar values (updated on change callbacks)
local cachedConVars = {
    size = 16384,
    brightness = 1.0,
    disableCull = false,
    clearDepth = false,
    zTest = false,
    zWrite = false,
    useDepthRange = false,
    depthNear = 0.999,
    depthFar = 1.0,
    rot_pitch = 0,
    rot_yaw = 0,
    rot_roll = 0,
    rot_rt = 0,
    rot_lf = 0,
    rot_bk = 0,
    rot_ft = 0,
    rot_up = 0,
    rot_dn = 0,
    swapLR = false,
    swapUD = false
}

-- Update cache from ConVars
local function UpdateConVarCache()
    cachedConVars.size = math.max(1024, math.floor(cv_size:GetFloat() or 16384))
    cachedConVars.brightness = math.max(0.0, cv_brightness:GetFloat())
    cachedConVars.disableCull = cv_disableCull:GetBool()
    cachedConVars.clearDepth = cv_clearDepth:GetBool()
    cachedConVars.zTest = cv_zTest:GetBool()
    cachedConVars.zWrite = cv_zWrite:GetBool()
    cachedConVars.useDepthRange = cv_useDepthRange:GetBool()
    cachedConVars.depthNear = math.Clamp(cv_depthNear:GetFloat() or 0.999, 0, 1)
    cachedConVars.depthFar = math.Clamp((cv_depthFar and cv_depthFar:GetFloat()) or 1, 0, 1)
    if cachedConVars.depthFar < cachedConVars.depthNear then
        cachedConVars.depthFar = cachedConVars.depthNear
    end
    cachedConVars.rot_pitch = cv_rot_pitch:GetFloat() or 0
    cachedConVars.rot_yaw = cv_rot_yaw:GetFloat() or 0
    cachedConVars.rot_roll = cv_rot_roll:GetFloat() or 0
    cachedConVars.rot_rt = cv_rot_rt:GetFloat()
    cachedConVars.rot_lf = cv_rot_lf:GetFloat()
    cachedConVars.rot_bk = cv_rot_bk:GetFloat()
    cachedConVars.rot_ft = cv_rot_ft:GetFloat()
    cachedConVars.rot_up = cv_rot_up:GetFloat()
    cachedConVars.rot_dn = cv_rot_dn:GetFloat()
    cachedConVars.swapLR = cv_swapLR:GetBool()
    cachedConVars.swapUD = cv_swapUD:GetBool()
end

-- Initialize cache
UpdateConVarCache()

-- Register change callbacks to invalidate cache
for name, _ in pairs({
    rtx_2dskybox_size = true,
    rtx_2dskybox_brightness = true,
    rtx_2dskybox_disable_cull = true,
    rtx_2dskybox_clear_depth = true,
    rtx_2dskybox_ztest = true,
    rtx_2dskybox_zwrite = true,
    rtx_2dskybox_use_depth_range = true,
    rtx_2dskybox_depth_near = true,
    rtx_2dskybox_depth_far = true,
    rtx_2dskybox_rot_pitch = true,
    rtx_2dskybox_rot_yaw = true,
    rtx_2dskybox_rot_roll = true,
    rtx_2dskybox_rot_rt = true,
    rtx_2dskybox_rot_lf = true,
    rtx_2dskybox_rot_bk = true,
    rtx_2dskybox_rot_ft = true,
    rtx_2dskybox_rot_up = true,
    rtx_2dskybox_rot_dn = true,
    rtx_2dskybox_swap_lr = true,
    rtx_2dskybox_swap_ud = true
}) do
    cvars.AddChangeCallback(name, UpdateConVarCache, "RTX2DSky_CacheUpdate")
end

local function getSkyName()
    local o = string.Trim(cv_override:GetString() or "")
    if o ~= "" then return o end
    local c = GetConVar("sv_skyname")
    local n = c and c:GetString() or "painted"
    return n ~= "" and n or "painted"
end

local function getSkyMaterials(name)
    local entry = skyCache[name]
    if entry then return entry end

    local sides = { "rt", "lf", "bk", "ft", "up", "dn" }
    local mats = {}
    for _, s in ipairs(sides) do
        local path = "skybox/" .. name .. s
        -- Use RenderCore material cache if available
        local mat = (RenderCore and RenderCore.GetMaterial) and RenderCore.GetMaterial(path) or Material(path)
        if mat and mat.SetInt then
            -- Keep $ignorez in sync with z-test setting so we can force-visibility when needed
            pcall(function()
                mat:SetInt("$ignorez", cv_zTest:GetBool() and 0 or 1)
            end)
        end
        mats[s] = mat
    end
    skyCache[name] = mats
    DebugPrint("Cached sky materials for:", name)
    return mats
end

local function drawFace(mat, pos, normal, size, rot)
    if not mat then return end
    render.SetMaterial(mat)
    render.DrawQuadEasy(pos, normal, size * 2, size * 2, color_white, rot or 0)
end

local function Draw2DSky()
    if not cv_enable:GetBool() then return end
    -- Avoid drawing multiple times per frame if multiple hooks call us
    -- Skip entirely during offscreen RT renders (e.g., rearview RenderView)
    if RenderCore and RenderCore.IsOffscreen and RenderCore.IsOffscreen() then
        return
    end
    local fn = FrameNumber()
    if lastDrawFrame == fn then return end
    lastDrawFrame = fn
    -- Only draw our sky when engine world is hidden to avoid double sky
    local cv_world = GetConVar("r_drawworld")
    local cv_opaque = GetConVar("r_drawopaqueworld")
    local cv_capture = GetConVar("rtx_capture_mode")
    local engineWorldOn = true
    if cv_world and cv_world:GetInt() == 0 then engineWorldOn = false end
    if cv_opaque and cv_opaque:GetInt() == 0 then engineWorldOn = false end
    if cv_capture and cv_capture:GetInt() == 1 then engineWorldOn = false end
    if engineWorldOn then return end

    local name = getSkyName()
    local mats = getSkyMaterials(name)

    -- Rendering parameters (use cached values)
    local origin = EyePos()
    local size = cachedConVars.size
    local br = cachedConVars.brightness
    
    render.SuppressEngineLighting(true)
    if cachedConVars.disableCull then
        render.CullMode(MATERIAL_CULLMODE_NONE)
    end
    -- Control depth test/write and optional clear
    if cachedConVars.clearDepth then
        render.ClearDepth()
    end
    render.OverrideDepthEnable(cachedConVars.zTest, cachedConVars.zWrite)
    if cachedConVars.useDepthRange then
        render.DepthRange(cachedConVars.depthNear, cachedConVars.depthFar)
    end
    render.SetColorModulation(br, br, br)

    -- Global rotation basis
    local ang = Angle(cachedConVars.rot_pitch, cachedConVars.rot_yaw, cachedConVars.rot_roll)
    local axisX = Vector(1, 0, 0)
    local axisY = Vector(0, 1, 0)
    local axisZ = Vector(0, 0, 1)
    axisX:Rotate(ang)
    axisY:Rotate(ang)
    axisZ:Rotate(ang)

    -- Sides
    -- Right/Left with optional swap
    local rtMat = mats["rt"]
    local lfMat = mats["lf"]
    if cachedConVars.swapLR then
        rtMat, lfMat = lfMat, rtMat
    end
    -- Right (rt): plane at +X, facing inward (-X)
    drawFace(rtMat, origin + axisX * size, -axisX, size, cachedConVars.rot_rt)
    -- Left (lf): plane at -X, facing inward (+X)
    drawFace(lfMat, origin - axisX * size,  axisX, size, cachedConVars.rot_lf)
    -- Back (bk): plane at -Y, facing inward (+Y)
    drawFace(mats["bk"], origin - axisY * size,  axisY, size, cachedConVars.rot_bk)
    -- Front (ft): plane at +Y, facing inward (-Y)
    drawFace(mats["ft"], origin + axisY * size, -axisY, size, cachedConVars.rot_ft)
    -- Up/Down with optional swap
    local upMat = mats["up"]
    local dnMat = mats["dn"]
    if cachedConVars.swapUD then
        upMat, dnMat = dnMat, upMat
    end
    -- Up (up): plane at +Z, facing inward (-Z)
    drawFace(upMat, origin + axisZ * size, -axisZ, size, cachedConVars.rot_up - cachedConVars.rot_yaw)
    -- Down (dn): plane at -Z, facing inward (+Z)
    drawFace(dnMat, origin - axisZ * size,  axisZ, size, cachedConVars.rot_dn - cachedConVars.rot_yaw)

    -- Restore render state
    render.SetColorModulation(1, 1, 1)
    if cachedConVars.useDepthRange then
        render.DepthRange(0, 1)
    end
    render.OverrideDepthEnable(false, false)
    if cachedConVars.disableCull then
        render.CullMode(MATERIAL_CULLMODE_CCW)
    end
    render.SuppressEngineLighting(false)
end

-- Draw very early in the frame so it acts as background
-- Note: Frame number guard in Draw2DSky() prevents multiple draws per frame even with multiple hooks
-- Using PreDrawOpaqueRenderables as primary hook for reliability
RenderCore.Register("PreDrawOpaqueRenderables", "RTX2DSky_Draw", { fn = function(bDrawingDepth, bDrawingSkybox)
    if bDrawingDepth then return end
    -- Only draw in world pass, not during skybox depth pass
    Draw2DSky()
end, prio = -10000 })

-- Clear cache on shutdown/map change
RenderCore.Register("ShutDown", "RTX2DSky_Cleanup", function()
    skyCache = {}
end)

print("[Custom 2D Skybox] Loaded.")
