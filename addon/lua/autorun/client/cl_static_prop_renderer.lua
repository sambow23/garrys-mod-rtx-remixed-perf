-- Custom Static Prop Renderer
-- Re-Renders all static props to bypass engine culling 
-- Author: CR

-- Notes:
-- 1. This is replacing FVF, but that being said, we most likely need to set render bounds for specific entities that are not static props. As I believe there is no way to make them not cull otherwise, hopefully I'm wrong.

if not (BRANCH == "x86-64" or BRANCH == "chromium") then return end
if not CLIENT then return end

-- Create our global table
StaticPropsRenderer = StaticPropsRenderer or {}
StaticPropsRenderer.UI = StaticPropsRenderer.UI or {}
StaticPropsRenderer.Enabled = true
StaticPropsRenderer.RenderDistance = 1500 -- Default render distance if no map preset is found. // This is kept at a relatively low value as rendering all props on the map at once is expensive.
StaticPropsRenderer.Props = {}
StaticPropsRenderer.Models = {}
StaticPropsRenderer.RenderCount = 0
StaticPropsRenderer.MaxRenderPerFrame = 5000
StaticPropsRenderer.Debug = false
StaticPropsRenderer.PropGrid = {}
StaticPropsRenderer.GridSize = 512
StaticPropsRenderer.DrawingSkybox = false

-- Wait for NikNaks to be loaded
timer.Simple(1, function()
    if not NikNaks then
        print("[StaticPropsRenderer] Error: NikNaks library not found!")
        return
    end
    
    -- Initialize the system once NikNaks is available
    StaticPropsRenderer:Initialize()
end)

-- Fix skybox rendering bug
hook.Add("PreDrawSkyBox", "StaticPropsRenderer_SkyboxDetection", function()
    StaticPropsRenderer.DrawingSkybox = true
end)

hook.Add("PostDrawSkyBox", "StaticPropsRenderer_SkyboxDetection", function()
    StaticPropsRenderer.DrawingSkybox = false
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
    
    hook.Add("PostDrawOpaqueRenderables", "StaticPropsRenderer_Render", function(bDrawingDepth, bDrawingSkybox)
        -- Skip rendering in skybox pass
        if self.DrawingSkybox or bDrawingSkybox then return end
        
        -- Skip in render targets (like mirrors)
        if render.GetRenderTarget() then return end
        
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

    RunConsoleCommand("r_drawstaticprops", "1")
    
    print("[StaticPropsRenderer] Initialized successfully!")
end

-- Helper function for creating a grid key from a position
function StaticPropsRenderer:GetGridKey(pos)
    local gx = math.floor(pos.x / self.GridSize)
    local gy = math.floor(pos.y / self.GridSize)
    local gz = math.floor(pos.z / self.GridSize)
    return gx .. "_" .. gy .. "_" .. gz
end

function StaticPropsRenderer:ScanMapProps()
    local staticProps = NikNaks.CurrentMap:GetStaticProps()
    
    print("[StaticPropsRenderer] Scanning static props...")
    
    -- Store model data
    self.Props = {}
    self.Models = {}
    self.PropGrid = {} -- Clear grid before populating it
    
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
        
        -- Add to spatial grid
        local key = self:GetGridKey(pos)
        if not self.PropGrid[key] then
            self.PropGrid[key] = {}
        end
        table.insert(self.PropGrid[key], propData)
    end
    
    print("[StaticPropsRenderer] Cached " .. count .. " static props with " .. modelCount .. " unique models")
    
    -- Sort props by model to minimize model switching during render
    table.sort(self.Props, function(a, b) 
        return a.model < b.model
    end)
    
    -- Sort props in each grid cell by model as well
    for _, props in pairs(self.PropGrid) do
        table.sort(props, function(a, b)
            return a.model < b.model
        end)
    end
    
    print("[StaticPropsRenderer] Created spatial grid with " .. table.Count(self.PropGrid) .. " cells")
end

function StaticPropsRenderer:RenderProps()
    if not self.Enabled then return end
    
    -- Skip if we're in the skybox pass
    if self.DrawingSkybox then return end
    
    -- Skip if we're rendering to a render target (like mirrors)
    if render.GetRenderTarget() then return end
    
    -- Get player position for distance culling
    local playerPos = LocalPlayer():GetPos()
    
    -- Pre-calculate the squared distance for optimization
    local renderDistSq = self.RenderDistance * self.RenderDistance
    
    -- Track current model to avoid redundant switches
    local currentModel = nil
    local renderedCount = 0
    local visibleCount = 0
    
    -- Prepare nearby props from the spatial grid
    local nearbyProps = {}
    local range = math.ceil(self.RenderDistance / self.GridSize)
    local playerGx = math.floor(playerPos.x / self.GridSize)
    local playerGy = math.floor(playerPos.y / self.GridSize)
    local playerGz = math.floor(playerPos.z / self.GridSize)
    
    -- Gather props from surrounding grid cells
    for dx = -range, range do
        for dy = -range, range do
            for dz = -range, range do
                local key = (playerGx + dx) .. "_" .. (playerGy + dy) .. "_" .. (playerGz + dz)
                if self.PropGrid[key] then
                    -- Check if this grid cell is potentially in range
                    local cellCenterX = (playerGx + dx + 0.5) * self.GridSize
                    local cellCenterY = (playerGy + dy + 0.5) * self.GridSize
                    local cellCenterZ = (playerGz + dz + 0.5) * self.GridSize
                    local cellCenter = Vector(cellCenterX, cellCenterY, cellCenterZ)
                    
                    -- Calculate diagonal (half-diagonal, really) of a grid cell 
                    local diagonalSq = (self.GridSize * 0.5) * (self.GridSize * 0.5) * 3 -- 3D diagonal squared
                    
                    -- If the cell is close enough to potentially contain visible props
                    if cellCenter:DistToSqr(playerPos) - diagonalSq <= renderDistSq then
                        for _, prop in ipairs(self.PropGrid[key]) do
                            table.insert(nearbyProps, prop)
                        end
                    end
                end
            end
        end
    end
    
    -- Use the render model table for performance
    local renderModel = {
        model = nil,
        pos = nil,
        angle = nil,
        skin = 0,
        bodygroup = 0
    }
    
    -- Render props from the gathered nearby props
    for i, prop in ipairs(nearbyProps) do
        -- Skip if too far
        local distanceSq = prop.pos:DistToSqr(playerPos)
        if distanceSq > renderDistSq then
            continue
        end
        
        visibleCount = visibleCount + 1
        
        -- Max render count check - do it before the expensive render call
        if renderedCount >= self.MaxRenderPerFrame then
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
        
        -- Update the reused table
        renderModel.model = prop.model
        renderModel.pos = prop.pos
        renderModel.angle = prop.ang
        renderModel.skin = prop.skin or 0
        renderModel.bodygroup = prop.bodygroups or 0
        
        render.Model(renderModel)
        
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
        local statsText = "Rendered: " .. renderedCount .. " / Visible: " .. visibleCount .. " / Total: " .. #self.Props .. " / Grid Cells: " .. table.Count(self.PropGrid) .. " / Skybox: " .. tostring(self.DrawingSkybox)
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
        maxRenderPerFrame = self.MaxRenderPerFrame,
        gridSize = self.GridSize -- Save grid size too
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
    if data.gridSize then
        self.GridSize = data.gridSize
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
    frame:SetSize(400, 320)
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
    
    -- Grid info label
    local gridLabel = vgui.Create("DLabel", frame)
    gridLabel:SetText("Grid Cells: " .. table.Count(self.PropGrid) .. " (Size: " .. self.GridSize .. ")")
    gridLabel:SetPos(20, 110)
    gridLabel:SetSize(360, 20)
    
    -- Render distance label and slider
    local distLabel = vgui.Create("DLabel", frame)
    distLabel:SetText("Render Distance: " .. self.RenderDistance)
    distLabel:SetPos(20, 130)
    distLabel:SetSize(360, 20)
    
    local distSlider = vgui.Create("DNumSlider", frame)
    distSlider:SetPos(20, 150)
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
    
    -- Grid size slider
    local gridSizeLabel = vgui.Create("DLabel", frame)
    gridSizeLabel:SetText("Grid Cell Size: " .. self.GridSize)
    gridSizeLabel:SetPos(20, 180)
    gridSizeLabel:SetSize(360, 20)
    
    local gridSizeSlider = vgui.Create("DNumSlider", frame)
    gridSizeSlider:SetPos(20, 200)
    gridSizeSlider:SetSize(360, 30)
    gridSizeSlider:SetMin(128)
    gridSizeSlider:SetMax(2048)
    gridSizeSlider:SetDecimals(0)
    gridSizeSlider:SetValue(self.GridSize)
    gridSizeSlider.OnValueChanged = function(_, value)
        value = math.Round(value)
        self.GridSize = value
        gridSizeLabel:SetText("Grid Cell Size: " .. value)
    end
    
    -- Update stats periodically
    frame.Think = function()
        if not IsValid(frame) then return end
        statsLabel:SetText("Props Rendered: " .. self.RenderCount .. " / " .. #self.Props)
        gridLabel:SetText("Grid Cells: " .. table.Count(self.PropGrid) .. " (Size: " .. self.GridSize .. ")")
    end
    
    -- Toggle button
    local toggleBtn = vgui.Create("DButton", frame)
    toggleBtn:SetText(self.Enabled and "Disable Renderer" or "Enable Renderer")
    toggleBtn:SetPos(20, frame:GetTall() - 90)
    toggleBtn:SetSize(150, 30)
    toggleBtn.DoClick = function()
        self:ToggleEnabled()
        toggleBtn:SetText(self.Enabled and "Disable Renderer" or "Enable Renderer")
        statusLabel:SetText("Status: " .. (self.Enabled and "Enabled" or "Disabled"))
    end
    
    -- Max rendered props slider
    local maxPropsLabel = vgui.Create("DLabel", frame)
    maxPropsLabel:SetText("Max Props: " .. self.MaxRenderPerFrame)
    maxPropsLabel:SetPos(200, frame:GetTall() - 110)
    maxPropsLabel:SetSize(180, 20)
    
    local maxPropsSlider = vgui.Create("DNumSlider", frame)
    maxPropsSlider:SetPos(200, frame:GetTall() - 90)
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
    
    -- Rebuild grid button
    local rebuildGridBtn = vgui.Create("DButton", frame)
    rebuildGridBtn:SetText("Rebuild Grid")
    rebuildGridBtn:SetPos(frame:GetWide() - 200, frame:GetTall() - 50)
    rebuildGridBtn:SetSize(90, 30)
    rebuildGridBtn.DoClick = function()
        self:ScanMapProps()
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