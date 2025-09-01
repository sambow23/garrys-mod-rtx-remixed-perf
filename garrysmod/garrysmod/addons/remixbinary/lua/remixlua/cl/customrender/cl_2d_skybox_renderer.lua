if not CLIENT then return end
local RenderCore = include("remixlua/cl/customrender/render_core.lua") or RemixRenderCore

-- Custom 2D Skybox Renderer
-- Draws a classic 6-sided skybox even when r_drawworld is 0 (capture mode)
-- Author: CR

local cv_enable = CreateClientConVar("rtx_sky2d_enable", "1", true, false, "Enable custom 2D skybox rendering")
local cv_override = CreateClientConVar("rtx_sky2d_name", "", true, false, "Override skybox name (leave blank to use sv_skyname)")
local cv_brightness = CreateClientConVar("rtx_sky2d_brightness", "1.0", true, false, "Brightness multiplier for custom 2D skybox")
local cv_useDepthRange = CreateClientConVar("rtx_sky2d_use_depthrange", "1", true, false, "Use DepthRange(near,1) during 2D sky draw for RTX detection")
local cv_depthNear = CreateClientConVar("rtx_sky2d_depthnear", "0.999", true, false, "DepthRange near (0..1) when enabled")
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
            -- Hint to ignore Z for sky materials
            pcall(function()
                mat:SetInt("$ignorez", 1)
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

    -- Rendering parameters
    local origin = EyePos()
    local size = 16384 -- large enough to surround the map
    local br = math.max(0.0, cv_brightness:GetFloat())

    -- Render background cube with depth test/write disabled so it behaves like engine sky
    local fov = (IsValid(LocalPlayer()) and LocalPlayer().GetFOV and LocalPlayer():GetFOV()) or 90
    cam.Start3D(EyePos(), EyeAngles(), fov)
        render.SuppressEngineLighting(true)
        -- Disable depth test and disable depth writes
        render.OverrideDepthEnable(true, true)
        if cv_useDepthRange:GetBool() then
            local dn = math.Clamp(cv_depthNear:GetFloat() or 0.999, 0, 1)
            render.DepthRange(dn, 1)
        end
        render.SetColorModulation(br, br, br)

        -- Global rotation basis
        local ang = Angle(cv_rot_pitch:GetFloat() or 0, cv_rot_yaw:GetFloat() or 0, cv_rot_roll:GetFloat() or 0)
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
        if cv_swapLR:GetBool() then
            rtMat, lfMat = lfMat, rtMat
        end
        -- Right (rt): plane at +X, facing inward (-X)
        drawFace(rtMat, origin + axisX * size, -axisX, size, cv_rot_rt:GetFloat())
        -- Left (lf): plane at -X, facing inward (+X)
        drawFace(lfMat, origin - axisX * size,  axisX, size, cv_rot_lf:GetFloat())
        -- Back (bk): plane at -Y, facing inward (+Y)
        drawFace(mats["bk"], origin - axisY * size,  axisY, size, cv_rot_bk:GetFloat())
        -- Front (ft): plane at +Y, facing inward (-Y)
        drawFace(mats["ft"], origin + axisY * size, -axisY, size, cv_rot_ft:GetFloat())
        -- Up/Down with optional swap
        local upMat = mats["up"]
        local dnMat = mats["dn"]
        if cv_swapUD:GetBool() then
            upMat, dnMat = dnMat, upMat
        end
        -- Up (up): plane at +Z, facing inward (-Z)
        local gyaw = (cv_rot_yaw:GetFloat() or 0)
        drawFace(upMat, origin + axisZ * size, -axisZ, size, cv_rot_up:GetFloat() - gyaw)
        -- Down (dn): plane at -Z, facing inward (+Z)
        drawFace(dnMat, origin - axisZ * size,  axisZ, size, cv_rot_dn:GetFloat() - gyaw)

        render.SetColorModulation(1, 1, 1)
        if cv_useDepthRange:GetBool() then
            render.DepthRange(0, 1)
        end
        render.OverrideDepthEnable(false, false)
        render.SuppressEngineLighting(false)
    cam.End3D()
end

-- Draw very early in the frame so it acts as background
RenderCore.Register("PreDrawOpaqueRenderables", "RTX2DSky_Draw", { fn = function(bDrawingDepth, bDrawingSkybox)
    if bDrawingDepth then return end
    -- Only draw in world pass, not during skybox depth pass
    Draw2DSky()
end, prio = -10000 })

-- Also draw during the engine's 2D skybox phase so RTX Remix can tag it as a sky draw
RenderCore.Register("PostDraw2DSkyBox", "RTX2DSky_Draw2DPhase", { fn = function()
    Draw2DSky()
end, prio = -10000 })

-- And in the engine skybox phase as a fallback for detection
RenderCore.Register("PreDrawSkyBox", "RTX2DSky_DrawSkyPhase", { fn = function()
    Draw2DSky()
end, prio = -10000 })

-- Clear cache on shutdown/map change
RenderCore.Register("ShutDown", "RTX2DSky_Cleanup", function()
    skyCache = {}
end)

print("[Custom 2D Skybox] Loaded.")
