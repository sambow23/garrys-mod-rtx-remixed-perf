TOOL.Category		= "RTX Remix"
TOOL.Name			= "Remix RT Light"
TOOL.Command		= nil
TOOL.ConfigName		= ""

-- Client ConVars (persisted per-user)
TOOL.ClientConVar["light_type"]	= "sphere" -- sphere, rect, disk, cylinder, distant, dome
TOOL.ClientConVar["radius"]		= "20"
TOOL.ClientConVar["brightness"]	= "1"
TOOL.ClientConVar["color_r"]		= "255"
TOOL.ClientConVar["color_g"]		= "220"
TOOL.ClientConVar["color_b"]		= "180"
TOOL.ClientConVar["volumetric"]	= "1"
TOOL.ClientConVar["shape_enabled"] = "0"
-- Shaping
TOOL.ClientConVar["cone"]		= "90"
TOOL.ClientConVar["softness"]	= "0.1"
TOOL.ClientConVar["focus"]		= "1.0"
TOOL.ClientConVar["yaw"]		= "0"
TOOL.ClientConVar["pitch"]		= "-90"
-- Rect/Disk sizes and Cylinder, Distant, Dome
TOOL.ClientConVar["xsize"]		= "40"
TOOL.ClientConVar["ysize"]		= "40"
TOOL.ClientConVar["xradius"]		= "20"
TOOL.ClientConVar["yradius"]		= "20"
TOOL.ClientConVar["axislen"]		= "40"
TOOL.ClientConVar["distantang"]	= "0.5"
TOOL.ClientConVar["dometex"]		= ""

if CLIENT then
    language.Add("tool.remix_rt_light.name", "Remix RT Light")
    language.Add("tool.remix_rt_light.desc", "Spawn and edit RTX Remix analytical lights")
    language.Add("tool.remix_rt_light.0", "Left-click: Spawn light | Right-click: Update targeted light | Reload: Open editor on targeted light")
end

local function computeRadianceVector(r, g, b, brightness)
    local scale = math.max(0, brightness or 1)
    return Vector((r/12)*scale, (g/12)*scale, (b/12)*scale)
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not trace.HitPos then return false end

    local pos = trace.HitPos + (trace.HitNormal or Vector(0,0,1)) * 16
    local ang = Angle(0, ply:EyeAngles().y, 0)

    local ent = ents.Create("remix_rt_light")
    if not IsValid(ent) then return false end
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    -- Apply settings
    local lt = self:GetClientInfo("light_type") or "sphere"
    ent.LightType = lt

    local radius = math.Clamp(math.floor(self:GetClientNumber("radius") or 20), 1, 200)
    ent:SetNWFloat("rtx_light_radius", radius)

    local brightness = self:GetClientNumber("brightness") or 1
    ent:SetNWFloat("rtx_light_brightness", brightness)
    ent:SetNWBool("rtx_light_shape_enabled", (self:GetClientNumber("shape_enabled") or 0) ~= 0)
    ent:SetNWFloat("rtx_light_volumetric", self:GetClientNumber("volumetric") or 1)
    ent:SetNWFloat("rtx_light_shape_cone", self:GetClientNumber("cone") or 90)
    ent:SetNWFloat("rtx_light_shape_softness", self:GetClientNumber("softness") or 0.1)
    ent:SetNWFloat("rtx_light_shape_focus", self:GetClientNumber("focus") or 1.0)
    ent:SetNWFloat("rtx_light_dir_yaw", self:GetClientNumber("yaw") or 0)
    ent:SetNWFloat("rtx_light_dir_pitch", self:GetClientNumber("pitch") or -90)
    ent:SetNWFloat("rtx_light_xsize", self:GetClientNumber("xsize") or radius*2)
    ent:SetNWFloat("rtx_light_ysize", self:GetClientNumber("ysize") or radius*2)
    ent:SetNWFloat("rtx_light_xradius", self:GetClientNumber("xradius") or radius)
    ent:SetNWFloat("rtx_light_yradius", self:GetClientNumber("yradius") or radius)
    ent:SetNWFloat("rtx_light_axis_len", self:GetClientNumber("axislen") or radius*2)
    ent:SetNWFloat("rtx_light_distant_angle", self:GetClientNumber("distantang") or 0.5)
    ent:SetNWString("rtx_light_dome_tex", self:GetClientInfo("dometex") or "")

    local r = self:GetClientNumber("color_r") or 255
    local g = self:GetClientNumber("color_g") or 220
    local b = self:GetClientNumber("color_b") or 180
    ent:SetNWVector("rtx_light_col", computeRadianceVector(r, g, b, brightness))

    undo.Create("Remix RT Light")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    return true
end

-- Right-click: update an existing light under the crosshair
function TOOL:RightClick(trace)
    if CLIENT then return true end
    if not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    if not isstring(ent:GetClass()) or not string.StartWith(ent:GetClass(), "remix_rt_light") and ent:GetClass() ~= "remix_rt_light" then
        return false
    end

    local lt = self:GetClientInfo("light_type") or "sphere"
    ent.LightType = lt

    local radius = math.Clamp(math.floor(self:GetClientNumber("radius") or 20), 1, 200)
    ent:SetNWFloat("rtx_light_radius", radius)

    local brightness = self:GetClientNumber("brightness") or 1
    ent:SetNWFloat("rtx_light_brightness", brightness)
    ent:SetNWBool("rtx_light_shape_enabled", (self:GetClientNumber("shape_enabled") or 0) ~= 0)
    ent:SetNWFloat("rtx_light_volumetric", self:GetClientNumber("volumetric") or 1)
    ent:SetNWFloat("rtx_light_shape_cone", self:GetClientNumber("cone") or 90)
    ent:SetNWFloat("rtx_light_shape_softness", self:GetClientNumber("softness") or 0.1)
    ent:SetNWFloat("rtx_light_shape_focus", self:GetClientNumber("focus") or 1.0)
    ent:SetNWFloat("rtx_light_dir_yaw", self:GetClientNumber("yaw") or 0)
    ent:SetNWFloat("rtx_light_dir_pitch", self:GetClientNumber("pitch") or -90)
    ent:SetNWFloat("rtx_light_xsize", self:GetClientNumber("xsize") or radius*2)
    ent:SetNWFloat("rtx_light_ysize", self:GetClientNumber("ysize") or radius*2)
    ent:SetNWFloat("rtx_light_xradius", self:GetClientNumber("xradius") or radius)
    ent:SetNWFloat("rtx_light_yradius", self:GetClientNumber("yradius") or radius)
    ent:SetNWFloat("rtx_light_axis_len", self:GetClientNumber("axislen") or radius*2)
    ent:SetNWFloat("rtx_light_distant_angle", self:GetClientNumber("distantang") or 0.5)
    ent:SetNWString("rtx_light_dome_tex", self:GetClientInfo("dometex") or "")

    local r = self:GetClientNumber("color_r") or 255
    local g = self:GetClientNumber("color_g") or 220
    local b = self:GetClientNumber("color_b") or 180
    ent:SetNWVector("rtx_light_col", computeRadianceVector(r, g, b, brightness))

    return true
end

-- Reload: open the entity’s context editor (client)
function TOOL:Reload(trace)
    if CLIENT then
        if IsValid(trace.Entity) and isfunction(properties.Get) then
            local prop = properties.Get("remix_rt_light_edit")
            if prop and prop.Filter and prop:Filter(trace.Entity, LocalPlayer()) and prop.Action then
                prop:Action(trace.Entity)
                return true
            end
        end
    end
    return false
end

-- Ghosting (optional): not implemented for simplicity
function TOOL:Think()
end

function TOOL.BuildCPanel(panel)
    panel:Help("Spawn and edit RTX Remix analytical lights. Use Right-click to apply settings to an existing light.")

    local combo = panel:ComboBox("Light Type", "remix_rt_light_light_type")
    combo:AddChoice("Sphere", "sphere")
    combo:AddChoice("Rect", "rect")
    combo:AddChoice("Disk", "disk")
    combo:AddChoice("Cylinder", "cylinder")
    combo:AddChoice("Distant", "distant")
    combo:AddChoice("Dome", "dome")

    panel:NumSlider("Radius", "remix_rt_light_radius", 1, 200, 0)
    panel:NumSlider("Brightness", "remix_rt_light_brightness", 0, 10, 2)
    panel:NumSlider("Volumetrics", "remix_rt_light_volumetric", 0, 5, 2)

    local shapeToggle = vgui.Create("DCheckBoxLabel", panel)
    shapeToggle:SetText("Enable Light Shaping (Sphere)")
    shapeToggle:SetConVar("remix_rt_light_shape_enabled")
    panel:AddItem(shapeToggle)

    local cone = panel:NumSlider("Cone Angle (Sphere)", "remix_rt_light_cone", 0, 180, 0)
    local softness = panel:NumSlider("Cone Softness (Sphere)", "remix_rt_light_softness", 0, 1, 2)
    local focus = panel:NumSlider("Focus Exponent (Sphere)", "remix_rt_light_focus", 0, 10, 2)
    local yaw = panel:NumSlider("Direction Yaw", "remix_rt_light_yaw", -180, 180, 0)
    local pitch = panel:NumSlider("Direction Pitch", "remix_rt_light_pitch", -90, 90, 0)

    local xsize = panel:NumSlider("Rect X Size", "remix_rt_light_xsize", 1, 400, 0)
    local ysize = panel:NumSlider("Rect Y Size", "remix_rt_light_ysize", 1, 400, 0)
    local xradius = panel:NumSlider("Disk X Radius", "remix_rt_light_xradius", 1, 200, 0)
    local yradius = panel:NumSlider("Disk Y Radius", "remix_rt_light_yradius", 1, 200, 0)
    local axislen = panel:NumSlider("Cylinder Axis Length", "remix_rt_light_axislen", 1, 400, 0)
    local distantang = panel:NumSlider("Distant Angular Diameter", "remix_rt_light_distantang", 0, 10, 2)
    local dometex = panel:TextEntry("Dome Texture Path", "remix_rt_light_dometex")

    local function refresh()
        local lt = combo:GetSelected() and select(2, combo:GetSelected()) or GetConVar("remix_rt_light_light_type"):GetString()
        -- defaults: hide all
        shapeToggle:SetVisible(false)
        cone:SetVisible(false)
        softness:SetVisible(false)
        focus:SetVisible(false)
        xsize:SetVisible(false)
        ysize:SetVisible(false)
        xradius:SetVisible(false)
        yradius:SetVisible(false)
        axislen:SetVisible(false)
        distantang:SetVisible(false)
        dometex:SetVisible(false)
        yaw:SetVisible(false)
        pitch:SetVisible(false)
        -- per-type
        if lt == "sphere" then
            shapeToggle:SetVisible(true)
            cone:SetVisible(true)
            softness:SetVisible(true)
            focus:SetVisible(true)
            yaw:SetVisible(true)
            pitch:SetVisible(true)
        elseif lt == "rect" then
            xsize:SetVisible(true)
            ysize:SetVisible(true)
            yaw:SetVisible(true)
            pitch:SetVisible(true)
        elseif lt == "disk" then
            xradius:SetVisible(true)
            yradius:SetVisible(true)
            yaw:SetVisible(true)
            pitch:SetVisible(true)
        elseif lt == "cylinder" then
            axislen:SetVisible(true)
        elseif lt == "distant" then
            distantang:SetVisible(true)
            yaw:SetVisible(true)
            pitch:SetVisible(true)
        elseif lt == "dome" then
            dometex:SetVisible(true)
        end
    end
    refresh()
    function combo:OnSelect()
        refresh()
    end

    panel:AddControl("Color", {
        Label = "Color",
        Red = "remix_rt_light_color_r",
        Green = "remix_rt_light_color_g",
        Blue = "remix_rt_light_color_b",
        ShowAlpha = 0,
        ShowHSV = 1,
        ShowRGB = 1,
        Multiplier = 1
    })
end


