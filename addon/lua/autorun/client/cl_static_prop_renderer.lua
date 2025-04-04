-- Custom Static Prop Renderer
-- Re-Renders all static props to bypass engine culling 
-- Author: CR

-- Notes:
-- 1. This is replacing FVF, but that being said, we most likely need to set render bounds for specific entities that are not static props. As I believe there is no way to make them not cull otherwise, hopefully I'm wrong.

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

-- Create our global table
StaticPropsRenderer = StaticPropsRenderer or {}
StaticPropsRenderer.VERSION = 1.3
StaticPropsRenderer.UI = StaticPropsRenderer.UI or {}
StaticPropsRenderer.Enabled = true
StaticPropsRenderer.RenderDistance = 1500 -- Default render distance if no map preset is found. // This is kept at a relatively low value as rendering all props on the map at once is expensive.
StaticPropsRenderer.Props = {}
StaticPropsRenderer.Models = {}
StaticPropsRenderer.RenderCount = 0
StaticPropsRenderer.MaxRenderPerFrame = 5000
StaticPropsRenderer.Debug = false

-- Wait for NikNaks to be loaded
timer.Simple(1, function()
    if not NikNaks then
        print("[StaticPropsRenderer] Error: NikNaks library not found!")
        return
    end
    
    -- Initialize the system once NikNaks is available
    StaticPropsRenderer:Initialize()
end)

function StaticPropsRenderer:Initialize()
    print("[StaticPropsRenderer] Initializing...")
    
    -- Check if we have a valid BSP object
    if not NikNaks.CurrentMap then
        print("[StaticPropsRenderer] Error: No valid map BSP data found!")
        return
    end
    
    -- Load settings
    self:LoadSettings()
    
    -- Add render hook
    hook.Add("PostDrawOpaqueRenderables", "StaticPropsRenderer_Render", function()
        self:RenderProps()
    end)
    
    -- Add console commands
    concommand.Add("staticprops_toggle", function()
        self:ToggleEnabled()
    end)
    
    concommand.Add("staticprops_ui", function()
        self:OpenUI()
    end)
    
    concommand.Add("staticprops_debug", function()
        self.Debug = not self.Debug
        print("[StaticPropsRenderer] Debug mode: " .. (self.Debug and "Enabled" or "Disabled"))
    end)
    
    -- Add chat command handler
    hook.Add("OnPlayerChat", "StaticPropsRenderer_ChatCommand", function(ply, text)
        if ply ~= LocalPlayer() then return end
        
        if text == "!staticprops" or text == "/staticprops" then
            self:OpenUI()
            return true
        end
    end)
    
    -- Scan static props
    self:ScanMapProps()

    -- Disable engine-level static props // Might re-enable this later as having both on can help with visual coherency 
    RunConsoleCommand("r_drawstaticprops", "0")
    
    print("[StaticPropsRenderer] Initialized successfully!")
end

function StaticPropsRenderer:ScanMapProps()
    local staticProps = NikNaks.CurrentMap:GetStaticProps()
    
    print("[StaticPropsRenderer] Scanning static props...")
    
    -- Store model data
    self.Props = {}
    self.Models = {}
    local count = 0
    local modelCount = 0
    
    for _, prop in pairs(staticProps) do
        local modelPath = prop:GetModel()
        
        -- Skip invalid models
        if not modelPath or modelPath == "" then
            continue
        end
        
        local pos = prop:GetPos()
        local ang = prop:GetAngles()
        
        -- Skip props at origin (likely invalid)
        if pos.x == 0 and pos.y == 0 and pos.z == 0 then
            continue
        end
        
        -- Track model
        if not self.Models[modelPath] then
            -- Precache model
            util.PrecacheModel(modelPath)
            
            self.Models[modelPath] = {
                path = modelPath,
                instances = 0
            }
            modelCount = modelCount + 1
        end
        
        -- Create prop render data
        local propData = {
            pos = pos,
            ang = ang,
            model = modelPath,
            skin = prop:GetSkin() or 0,
            bodygroups = 0, -- Default
            color = Color(255, 255, 255),
            scale = prop:GetScale() or 1
        }
        
        table.insert(self.Props, propData)
        self.Models[modelPath].instances = self.Models[modelPath].instances + 1
        count = count + 1
    end
    
    print("[StaticPropsRenderer] Cached " .. count .. " static props with " .. modelCount .. " unique models")
    
    -- Sort props by model to minimize model switching during render
    table.sort(self.Props, function(a, b) 
        return a.model < b.model
    end)
end

function StaticPropsRenderer:RenderProps()
    if not self.Enabled then return end
    
    -- Get player position for distance culling
    local playerPos = LocalPlayer():GetPos()
    
    -- Track current model to avoid redundant switches
    local currentModel = nil
    local renderedCount = 0
    local visibleCount = 0
    
    -- Render props
    for i, prop in ipairs(self.Props) do
        -- Skip if too far
        local distance = prop.pos:DistToSqr(playerPos)
        if distance > (self.RenderDistance * self.RenderDistance) then
            continue
        end
        
        visibleCount = visibleCount + 1
        
        -- Enforce max render count for performance
        if visibleCount > self.MaxRenderPerFrame then
            break
        end
        
        -- Draw the model directly
        if self.Debug then
            -- Draw a debug box for positioning visualization
            render.DrawWireframeBox(prop.pos, prop.ang, Vector(-5, -5, -5), Vector(5, 5, 5), Color(255, 0, 0), true)
            
            -- Draw a line from prop to ground for position reference
            local groundPos = Vector(prop.pos.x, prop.pos.y, prop.pos.z - 1000)
            render.DrawLine(prop.pos, groundPos, Color(0, 255, 0), true)
        end
        
        render.Model({
            model = prop.model,
            pos = prop.pos,
            angle = prop.ang,
            skin = prop.skin or 0,
            bodygroup = prop.bodygroups or 0
        })
        
        renderedCount = renderedCount + 1
    end
    
    -- Store render stats
    self.RenderCount = renderedCount
    
    -- Debug information
    if self.Debug then
        -- Draw current location
        local pos = LocalPlayer():GetPos()
        local text = "Player Position: " .. math.floor(pos.x) .. ", " .. math.floor(pos.y) .. ", " .. math.floor(pos.z)
        draw.SimpleText(text, "DermaDefault", ScrW() / 2, ScrH() - 40, Color(255, 255, 255), TEXT_ALIGN_CENTER)
        
        -- Draw render stats
        local statsText = "Rendered: " .. renderedCount .. " / Visible: " .. visibleCount .. " / Total: " .. #self.Props
        draw.SimpleText(statsText, "DermaDefault", ScrW() / 2, ScrH() - 20, Color(255, 255, 255), TEXT_ALIGN_CENTER)
    end
end

function StaticPropsRenderer:ToggleEnabled()
    self.Enabled = not self.Enabled
    print("[StaticPropsRenderer] " .. (self.Enabled and "Enabled" or "Disabled"))
    
    -- Save settings
    self:SaveSettings()
end

--------------------------------------------------
-- Settings
--------------------------------------------------

function StaticPropsRenderer:SaveSettings()
    local data = {
        enabled = self.Enabled,
        renderDistance = self.RenderDistance,
        maxRenderPerFrame = self.MaxRenderPerFrame
    }
    
    file.CreateDir("staticpropsrenderer")
    file.Write("staticpropsrenderer/" .. game.GetMap() .. ".json", util.TableToJSON(data))
    
    print("[StaticPropsRenderer] Settings saved for " .. game.GetMap())
end

function StaticPropsRenderer:LoadSettings()
    if not file.Exists("staticpropsrenderer/" .. game.GetMap() .. ".json", "DATA") then
        print("[StaticPropsRenderer] No saved settings found for " .. game.GetMap())
        self.Enabled = true
        return
    end
    
    local data = util.JSONToTable(file.Read("staticpropsrenderer/" .. game.GetMap() .. ".json", "DATA"))
    
    if not data then
        print("[StaticPropsRenderer] Error reading settings file")
        self.Enabled = true
        return
    end
    
    self.Enabled = data.enabled
    if data.renderDistance then
        self.RenderDistance = data.renderDistance
    end
    if data.maxRenderPerFrame then
        self.MaxRenderPerFrame = data.maxRenderPerFrame
    end
    
    print("[StaticPropsRenderer] Settings loaded for " .. game.GetMap())
end

--------------------------------------------------
-- Basic UI
--------------------------------------------------

function StaticPropsRenderer:OpenUI()
    if IsValid(self.UI.Frame) then
        self.UI.Frame:Remove()
    end
    
    -- Create the main frame
    local frame = vgui.Create("DFrame")
    frame:SetTitle("Static Props Renderer")
    frame:SetSize(400, 280)
    frame:Center()
    frame:MakePopup()
    self.UI.Frame = frame
    
    -- Add header
    local headerLabel = vgui.Create("DLabel", frame)
    headerLabel:SetText("Static Props Custom Renderer")
    headerLabel:SetFont("DermaLarge")
    headerLabel:SetPos(20, 30)
    headerLabel:SizeToContents()
    
    -- Status label
    local statusLabel = vgui.Create("DLabel", frame)
    statusLabel:SetText("Status: " .. (self.Enabled and "Enabled" or "Disabled"))
    statusLabel:SetPos(20, 70)
    statusLabel:SetSize(360, 20)
    
    -- Stats label
    local statsLabel = vgui.Create("DLabel", frame)
    statsLabel:SetText("Props Rendered: " .. self.RenderCount .. " / " .. #self.Props)
    statsLabel:SetPos(20, 90)
    statsLabel:SetSize(360, 20)
    
    -- Render distance label and slider
    local distLabel = vgui.Create("DLabel", frame)
    distLabel:SetText("Render Distance: " .. self.RenderDistance)
    distLabel:SetPos(20, 120)
    distLabel:SetSize(360, 20)
    
    local distSlider = vgui.Create("DNumSlider", frame)
    distSlider:SetPos(20, 140)
    distSlider:SetSize(360, 30)
    distSlider:SetMin(500)
    distSlider:SetMax(50000)
    distSlider:SetDecimals(0)
    distSlider:SetValue(self.RenderDistance)
    distSlider.OnValueChanged = function(_, value)
        value = math.Round(value)
        self.RenderDistance = value
        distLabel:SetText("Render Distance: " .. value)
    end
    
    -- Update stats periodically
    frame.Think = function()
        if not IsValid(frame) then return end
        statsLabel:SetText("Props Rendered: " .. self.RenderCount .. " / " .. #self.Props)
    end
    
    -- Toggle button
    local toggleBtn = vgui.Create("DButton", frame)
    toggleBtn:SetText(self.Enabled and "Disable Renderer" or "Enable Renderer")
    toggleBtn:SetPos(20, frame:GetTall() - 80)
    toggleBtn:SetSize(150, 30)
    toggleBtn.DoClick = function()
        self:ToggleEnabled()
        toggleBtn:SetText(self.Enabled and "Disable Renderer" or "Enable Renderer")
        statusLabel:SetText("Status: " .. (self.Enabled and "Enabled" or "Disabled"))
    end
    
    -- Max rendered props slider
    local maxPropsLabel = vgui.Create("DLabel", frame)
    maxPropsLabel:SetText("Max Props: " .. self.MaxRenderPerFrame)
    maxPropsLabel:SetPos(200, frame:GetTall() - 100)
    maxPropsLabel:SetSize(180, 20)
    
    local maxPropsSlider = vgui.Create("DNumSlider", frame)
    maxPropsSlider:SetPos(200, frame:GetTall() - 80)
    maxPropsSlider:SetSize(180, 30)
    maxPropsSlider:SetMin(1000)
    maxPropsSlider:SetMax(20000)
    maxPropsSlider:SetDecimals(0)
    maxPropsSlider:SetValue(self.MaxRenderPerFrame)
    maxPropsSlider.OnValueChanged = function(_, value)
        value = math.Round(value)
        self.MaxRenderPerFrame = value
        maxPropsLabel:SetText("Max Props: " .. value)
    end
    
    -- Debug mode checkbox
    local debugCheck = vgui.Create("DCheckBoxLabel", frame)
    debugCheck:SetPos(20, frame:GetTall() - 50)
    debugCheck:SetText("Debug Mode")
    debugCheck:SetValue(self.Debug)
    debugCheck:SizeToContents()
    debugCheck.OnChange = function(_, val)
        self.Debug = val
    end
    
    -- Save button
    local saveBtn = vgui.Create("DButton", frame)
    saveBtn:SetText("Save Settings")
    saveBtn:SetPos(frame:GetWide() - 110, frame:GetTall() - 50)
    saveBtn:SetSize(90, 30)
    saveBtn.DoClick = function()
        self:SaveSettings()
        frame:Close()
    end
end

-- Command to open the UI from console
concommand.Add("staticprops_ui", function()
    StaticPropsRenderer:OpenUI()
end)

-- Print help message when addon loads
hook.Add("InitPostEntity", "StaticPropsRenderer_HelpMessage", function()
    timer.Simple(5, function()
        print("[StaticPropsRenderer] Addon loaded! Type '!staticprops' in chat or 'staticprops_ui' in console to open the UI")
        print("[StaticPropsRenderer] Debug mode available with 'staticprops_debug' console command")
    end)
end)