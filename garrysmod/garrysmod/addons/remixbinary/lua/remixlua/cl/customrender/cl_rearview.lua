-- -- Places a RenderTarget camera at the local player's eyes, looking 180 degrees behind, prevents culling for dynamic entities

-- if SERVER then return end

-- local REARVIEW = REARVIEW or {}
-- REARVIEW.rtName = "rearview_rt"
-- REARVIEW.matName = "rearview_rt_mat"
-- REARVIEW.w = 512
-- REARVIEW.h = 512
-- REARVIEW.enabled = false
-- REARVIEW._rendering = false
-- REARVIEW._panel = nil
-- REARVIEW.lastView = nil

-- local function CreateRT()
--     if REARVIEW.rt and REARVIEW.rt:IsError() == false then return end

--     -- Create a render target and material to display it
--     REARVIEW.rt = GetRenderTargetEx(
--         REARVIEW.rtName,
--         REARVIEW.w,
--         REARVIEW.h,
--         RT_SIZE_OFFSCREEN,
--         MATERIAL_RT_DEPTH_SHARED,
--         0,
--         CREATERENDERTARGETFLAGS_HDR,
--         IMAGE_FORMAT_RGBA8888
--     )

--     REARVIEW.mat = CreateMaterial(REARVIEW.matName, "UnlitGeneric", {
--         ["$basetexture"] = REARVIEW.rt:GetName(),
--         ["$vertexcolor"] = 1,
--         ["$vertexalpha"] = 1,
--         ["$translucent"] = 1,
--         ["$no_fullbright"] = 1
--     })

--     -- Ensure material uses our RT as base texture
--     if REARVIEW.mat and REARVIEW.rt then
--         REARVIEW.mat:SetTexture("$basetexture", REARVIEW.rt)
--     end
-- end

-- local function DestroyRT()
--     -- GMod doesn't expose explicit destroy; just drop references
--     REARVIEW.rt = nil
--     REARVIEW.mat = nil
-- end

-- -- Apply size from the rearview_size convar; recreates RT and resizes panel if needed
-- local function ApplySizeFromConVar()
--     local cv = GetConVar and GetConVar("rtx_rearview_size")
--     local s = (cv and tonumber(cv:GetInt())) or REARVIEW.w or 512
--     if not s or s < 1 then s = 1 end

--     local changed = (REARVIEW.w ~= s) or (REARVIEW.h ~= s)
--     REARVIEW.w = s
--     REARVIEW.h = s

--     if changed then
--         DestroyRT()
--         if IsValid(REARVIEW._panel) then
--             REARVIEW._panel:SetSize(REARVIEW.w, REARVIEW.h)
--             REARVIEW._panel:SetPos(ScrW() - REARVIEW.w - 24, ScrH() - REARVIEW.h - 160)
--         end
--     end
-- end

-- local function GetRearAngles()
--     local lp = LocalPlayer()
--     local ang = (REARVIEW.lastView and REARVIEW.lastView.angles)
--         or (IsValid(lp) and lp:EyeAngles())
--         or EyeAngles()
--     -- Add configurable yaw offset (default 180 for rear view)
--     local yawAdd = 180
--     do
--         local cv = GetConVar and GetConVar("rtx_rearview_yaw_add")
--         if cv then yawAdd = cv:GetFloat() end
--     end
--     -- Lock vertical rotation: zero pitch and roll so we only rotate left/right
--     return Angle(0, ang.y + yawAdd, 0)
-- end

-- -- Compute camera origin with local offsets (forward/right/up relative to yaw-only basis)
-- local function GetCameraOrigin()
--     local lp = LocalPlayer()
--     local baseOrigin = (REARVIEW.lastView and REARVIEW.lastView.origin)
--         or ((IsValid(lp) and lp:EyePos()) or EyePos())
--     local baseAng = (REARVIEW.lastView and REARVIEW.lastView.angles)
--         or ((IsValid(lp) and lp:EyeAngles()) or EyeAngles())

--     -- Use yaw-only for offset basis to avoid vertical drift when pitch changes
--     local yawOnly = Angle(0, baseAng.y, 0)
--     local fwd = yawOnly:Forward()
--     local right = yawOnly:Right()
--     local up = Vector(0, 0, 1)

--     local offF = 0
--     local offR = 0
--     local offU = 0
--     do
--         local cvF = GetConVar and GetConVar("rtx_rearview_off_forward")
--         local cvR = GetConVar and GetConVar("rtx_rearview_off_right")
--         local cvU = GetConVar and GetConVar("rtx_rearview_off_up")
--         if cvF then offF = cvF:GetFloat() end
--         if cvR then offR = cvR:GetFloat() end
--         if cvU then offU = cvU:GetFloat() end
--     end

--     return baseOrigin + fwd * offF + right * offR + up * offU
-- end

-- local function UpdateRearRT()
--     if not REARVIEW.enabled then return end
--     if REARVIEW._rendering then return end
--     if not IsValid(LocalPlayer()) then return end

--     CreateRT()
--     if not REARVIEW.rt then return end

--     REARVIEW._rendering = true

--     render.PushRenderTarget(REARVIEW.rt)
--     render.Clear(0, 0, 0, 255, true, true)

--     -- Choose FOV: use rearview_fov if > 0, otherwise follow current camera fov or player's fov_desired
--     local desiredFov = -1
--     do
--         local rvFovCv = GetConVar and GetConVar("rtx_rearview_fov")
--         if rvFovCv then desiredFov = rvFovCv:GetFloat() end
--     end
--     local useFov
--     if desiredFov and desiredFov > 0 then
--         useFov = math.Clamp(desiredFov, 30, 500)
--     else
--         useFov = (REARVIEW.lastView and REARVIEW.lastView.fov)
--             or ((GetConVar and GetConVar("fov_desired") and GetConVar("fov_desired"):GetFloat()) or 90)
--     end

--     local view = {
--         origin = GetCameraOrigin(),
--         angles = GetRearAngles(),
--         x = 0,
--         y = 0,
--         w = REARVIEW.w,
--         h = REARVIEW.h,
--         fov = useFov,
--         drawviewmodel = false,
--         drawhud = false,
--         dopostprocess = false,
--         drawmonitors = false
--     }

--     -- Render scene into our RT
--     render.RenderView(view)

--     render.PopRenderTarget()
--     REARVIEW._rendering = false
-- end

-- -- Update the RT once per frame safely
-- hook.Add("PreRender", "RearView_UpdateRT", function()
--     if not REARVIEW.enabled then return end
--     UpdateRearRT()
-- end)

-- -- Capture the current camera each frame; this reflects final camera used by engine for rendering
-- hook.Add("RenderScene", "RearView_CaptureView", function(origin, angles, fov)
--     if not REARVIEW.enabled then return end
--     if REARVIEW._rendering then return end -- don't capture while we render our own RT
--     REARVIEW.lastView = REARVIEW.lastView or {}
--     REARVIEW.lastView.origin = origin
--     REARVIEW.lastView.angles = angles
--     REARVIEW.lastView.fov = fov
-- end)

-- -- Also capture from CalcView so we follow custom camera logic provided by the gamemode/addons
-- hook.Add("CalcView", "RearView_CalcViewCapture", function(ply, pos, ang, fov)
--     if not REARVIEW.enabled then return end
--     if REARVIEW._rendering then return end
--     REARVIEW.lastView = REARVIEW.lastView or {}
--     REARVIEW.lastView.origin = pos
--     REARVIEW.lastView.angles = ang
--     REARVIEW.lastView.fov = fov
--     -- do not override CalcView; return nil
-- end)

-- -- Panel to draw the RT texture
-- local PANEL = {}

-- function PANEL:Init()
--     self:SetSize(REARVIEW.w, REARVIEW.h)
--     self:SetPos(ScrW() - self:GetWide() - 24, ScrH() - self:GetTall() - 160)
--     self:SetMouseInputEnabled(false)
--     self:SetKeyboardInputEnabled(false)
--     self:SetAlpha(230)
--     self:SetTooltip("Rear View Camera")

--     -- Simple corner drag to resize with Shift key
--     self._dragging = false
--     self._dragOffset = { x = 0, y = 0 }
-- end

-- function PANEL:Paint(w, h)
--     if not REARVIEW.mat then return end

--     surface.SetDrawColor(255, 255, 255, 255)
--     surface.SetMaterial(REARVIEW.mat)
--     surface.DrawTexturedRect(0, 0, w, h)

--     -- Optional border
--     surface.SetDrawColor(0, 0, 0, 180)
--     surface.DrawOutlinedRect(0, 0, w, h, 2)
-- end

-- vgui.Register("DRearView", PANEL, "DPanel")

-- local function OpenPanel()
--     if IsValid(REARVIEW._panel) then REARVIEW._panel:Remove() end

--     REARVIEW._panel = vgui.Create("DRearView")
--     REARVIEW._panel:SetVisible(true)

--     -- Make sure RT exists and mat is set
--     -- Apply persisted size before creating RT
--     ApplySizeFromConVar()
--     CreateRT()
-- end

-- local function ClosePanel()
--     if IsValid(REARVIEW._panel) then
--         REARVIEW._panel:Remove()
--         REARVIEW._panel = nil
--     end
-- end

-- local function SetEnabled(enable)
--     REARVIEW.enabled = enable and true or false

--     if REARVIEW.enabled then
--         OpenPanel()
--     else
--         ClosePanel()
--     end
-- end

-- -- ConVars and commands
-- CreateClientConVar("rtx_rearview_enabled", "0", true, false, "Enable the rear-view camera panel")
-- CreateClientConVar("rtx_rearview_size", "512", true, false, "Rear-view panel size (square), requires toggle to re-create")
-- CreateClientConVar("rtx_rearview_fov", "-1", true, false, "Rear-view camera FOV in degrees. Set -1 to follow player FOV (fov_desired)")
-- -- Movement/offset convars
-- CreateClientConVar("rtx_rearview_off_forward", "0", true, false, "Rear-view local forward offset in units")
-- CreateClientConVar("rtx_rearview_off_right", "0", true, false, "Rear-view local right offset in units")
-- CreateClientConVar("rtx_rearview_off_up", "0", true, false, "Rear-view local up offset in units")
-- CreateClientConVar("rtx_rearview_yaw_add", "180", true, false, "Additional yaw in degrees (default 180 = look behind)")

-- cvars.AddChangeCallback("rtx_rearview_enabled", function(convar, old, new)
--     local enable = tonumber(new) == 1
--     SetEnabled(enable)
-- end, "rearview_enabled_cb")

-- -- React to size changes via convar (persists across maps/sessions)
-- cvars.AddChangeCallback("rtx_rearview_size", function(convar, old, new)
--     ApplySizeFromConVar()
-- end, "rearview_size_cb")

-- concommand.Add("rtx_rearview_toggle", function()
--     local cv = GetConVar("rtx_rearview_enabled")
--     if not cv then return end
--     cv:SetBool(not cv:GetBool())
-- end, nil, "Toggle the rear-view camera panel")

-- concommand.Add("rtx_rearview_setsize", function(ply, cmd, args)
--     local s = tonumber(args and args[1])
--     if not s or s < 1 then return end
--     RunConsoleCommand("rtx_rearview_size", tostring(math.floor(s)))
-- end, nil, "Set rear-view panel size (pixels)")

-- concommand.Add("rtx_rearview_setfov", function(ply, cmd, args)
--     local f = tonumber(args and args[1])
--     if not f then return end

--     if f < 0 then
--         RunConsoleCommand("rtx_rearview_fov", "-1")
--         return
--     end

--     f = math.Clamp(f, 30, 500)
--     RunConsoleCommand("rtx_rearview_fov", tostring(f))
-- end, nil, "Set rear-view camera FOV in degrees. Use -1 to follow your player FOV")

-- -- Offset helpers
-- concommand.Add("rtx_rearview_setoffset", function(ply, cmd, args)
--     local f = tonumber(args and args[1])
--     local r = tonumber(args and args[2])
--     local u = tonumber(args and args[3])
--     if not f or not r or not u then return end
--     RunConsoleCommand("rtx_rearview_off_forward", tostring(f))
--     RunConsoleCommand("rtx_rearview_off_right", tostring(r))
--     RunConsoleCommand("rtx_rearview_off_up", tostring(u))
-- end, nil, "Set rear-view local offsets: forward right up")

-- concommand.Add("rtx_rearview_nudge", function(ply, cmd, args)
--     local axis = tostring(args and args[1] or "")
--     local d = tonumber(args and args[2]) or 0
--     axis = string.lower(axis)
--     local function add(name)
--         local cv = GetConVar and GetConVar(name)
--         local cur = cv and cv:GetFloat() or 0
--         RunConsoleCommand(name, tostring(cur + d))
--     end
--     if axis == "f" or axis == "forward" then add("rtx_rearview_off_forward") return end
--     if axis == "r" or axis == "right" then add("rtx_rearview_off_right") return end
--     if axis == "u" or axis == "up" then add("rtx_rearview_off_up") return end
--     if axis == "y" or axis == "yaw" then add("rtx_rearview_yaw_add") return end
-- end, nil, "Nudge an offset: rearview_nudge <f|r|u|yaw> <delta>")

-- concommand.Add("rtx_rearview_resetoffset", function()
--     RunConsoleCommand("rtx_rearview_off_forward", "0")
--     RunConsoleCommand("rtx_rearview_off_right", "0")
--     RunConsoleCommand("rtx_rearview_off_up", "0")
--     RunConsoleCommand("rtx_rearview_yaw_add", "180")
-- end, nil, "Reset rear-view offsets and yaw to defaults")

-- -- Auto-create on join if convar persisted
-- hook.Add("InitPostEntity", "RearView_Init", function()
--     if GetConVar("rtx_rearview_enabled") and GetConVar("rtx_rearview_enabled"):GetBool() then
--         SetEnabled(true)
--     end
-- end)
