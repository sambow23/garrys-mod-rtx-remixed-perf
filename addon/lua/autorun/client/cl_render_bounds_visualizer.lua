-- -- Render Bounds Visualizer
-- -- Visualizes render bounds for all entities and static props in a map

-- -- Configuration
-- local ENABLED = CreateClientConVar("render_bounds_enabled", "0", true, false, "Enable render bounds visualization")
-- local ALPHA = CreateClientConVar("render_bounds_alpha", "50", true, false, "Alpha value for the render bounds (0-255)")
-- local SHOW_DYNAMIC = CreateClientConVar("render_bounds_dynamic", "1", true, false, "Show dynamic entities")
-- local SHOW_STATIC = CreateClientConVar("render_bounds_static", "1", true, false, "Show static props")

-- -- Colors for different entity types
-- local COLORS = {
--     ["prop_physics"] = Color(255, 0, 0),     -- Red for physics props
--     ["prop_static"] = Color(0, 255, 0),      -- Green for static props
--     ["prop_dynamic"] = Color(0, 0, 255),     -- Blue for dynamic props
--     ["player"] = Color(0, 0, 0),         -- Yellow for players
--     ["npc"] = Color(255, 0, 255),            -- Purple for NPCs
--     ["weapon"] = Color(0, 0, 0),         -- Cyan for weapons
--     ["default"] = Color(0, 0, 0)       -- White for everything else
-- }

-- -- Edge colors for different faces
-- local EDGE_COLORS = {
--     Color(255, 0, 0),     -- Red (Bottom face)
--     Color(0, 255, 0),     -- Green (Top face)
--     Color(0, 0, 255),     -- Blue (Front face)
--     Color(255, 255, 0),   -- Yellow (Right face)
--     Color(0, 255, 255),   -- Cyan (Back face)
--     Color(255, 0, 255)    -- Magenta (Left face)
-- }

-- -- Function to get the color for an entity
-- local function GetEntityColor(ent)
--     if not IsValid(ent) then return COLORS["default"] end
    
--     local class = ent:GetClass()
--     return COLORS[class] or COLORS["default"]
-- end

-- -- Function to draw a bounding box with corners in world space
-- local function DrawBoundingBox(corners, color, alpha)
--     -- Define faces with their corner indices
--     local faces = {
--         {1, 2, 3, 4}, -- Bottom face
--         {5, 6, 7, 8}, -- Top face
--         {1, 2, 6, 5}, -- Front face
--         {2, 3, 7, 6}, -- Right face
--         {3, 4, 8, 7}, -- Back face
--         {4, 1, 5, 8}  -- Left face
--     }
    
--     -- Set the render material to a simple color material
--     render.SetColorMaterial()
    
--     -- Draw the transparent quads for each face
--     for i, face in ipairs(faces) do
--         render.DrawQuad(
--             corners[face[1]],
--             corners[face[2]],
--             corners[face[3]],
--             corners[face[4]],
--             Color(color.r, color.g, color.b, alpha)
--         )
        
--         -- Draw the 4 edges of this face with its color
--         local edgeColor = EDGE_COLORS[i]
        
--         render.DrawLine(corners[face[1]], corners[face[2]], edgeColor, false)
--         render.DrawLine(corners[face[2]], corners[face[3]], edgeColor, false)
--         render.DrawLine(corners[face[3]], corners[face[4]], edgeColor, false)
--         render.DrawLine(corners[face[4]], corners[face[1]], edgeColor, false)
--     end
-- end

-- -- Function to draw the render bounds of an entity
-- local function DrawEntityRenderBounds(ent)
--     if not IsValid(ent) then return end
    
--     local min, max = ent:GetRenderBounds()
    
--     -- Create vectors for each corner of the bounding box in local space
--     local corners = {
--         ent:LocalToWorld(Vector(min.x, min.y, min.z)),
--         ent:LocalToWorld(Vector(max.x, min.y, min.z)),
--         ent:LocalToWorld(Vector(max.x, max.y, min.z)),
--         ent:LocalToWorld(Vector(min.x, max.y, min.z)),
--         ent:LocalToWorld(Vector(min.x, min.y, max.z)),
--         ent:LocalToWorld(Vector(max.x, min.y, max.z)),
--         ent:LocalToWorld(Vector(max.x, max.y, max.z)),
--         ent:LocalToWorld(Vector(min.x, max.y, max.z))
--     }
    
--     local color = GetEntityColor(ent)
--     local alpha = ALPHA:GetInt()
    
--     DrawBoundingBox(corners, color, alpha)
-- end

-- -- Function to draw the render bounds of a static prop
-- local function DrawStaticPropRenderBounds(prop)
--     -- Get model bounds
--     local min, max = prop:GetModelBounds()
    
--     -- Get prop's position and angles
--     local origin = prop:GetPos()
--     local angles = prop:GetAngles()
    
--     -- Create corners in local space
--     local corners = {
--         Vector(min.x, min.y, min.z),
--         Vector(max.x, min.y, min.z),
--         Vector(max.x, max.y, min.z),
--         Vector(min.x, max.y, min.z),
--         Vector(min.x, min.y, max.z),
--         Vector(max.x, min.y, max.z),
--         Vector(max.x, max.y, max.z),
--         Vector(min.x, max.y, max.z)
--     }
    
--     -- Transform corners to world space
--     for i, corner in ipairs(corners) do
--         corners[i] = LocalToWorld(corner, Angle(0,0,0), origin, angles)
--     end
    
--     -- Draw the bounding box
--     local alpha = ALPHA:GetInt()
--     DrawBoundingBox(corners, COLORS["prop_static"], alpha)
-- end

-- -- Hook into the rendering system
-- hook.Add("PostDrawTranslucentRenderables", "VisualizeRenderBounds", function()
--     if not ENABLED:GetBool() then return end
    
--     -- Draw bounds for dynamic entities
--     if SHOW_DYNAMIC:GetBool() then
--         for _, ent in ipairs(ents.GetAll()) do
--             if ent:IsValid() and not ent:IsWorld() then
--                 DrawEntityRenderBounds(ent)
--             end
--         end
--     end
    
--     -- Draw bounds for static props from the map using NikNaks
--     if SHOW_STATIC:GetBool() and NikNaks and NikNaks.CurrentMap then
--         local staticProps = NikNaks.CurrentMap:GetStaticProps()
--         for _, prop in pairs(staticProps) do
--             DrawStaticPropRenderBounds(prop)
--         end
--     end
-- end)

-- -- Add a console command to toggle the visualization
-- concommand.Add("toggle_render_bounds", function()
--     RunConsoleCommand("render_bounds_enabled", ENABLED:GetBool() and "0" or "1")
-- end)

-- -- Print a message when the script is loaded
-- print("Render Bounds Visualizer loaded. Use 'toggle_render_bounds' to toggle visualization.")
-- print("Additional commands:")
-- print("  render_bounds_enabled <0/1> - Enable or disable the visualizer")
-- print("  render_bounds_alpha <0-255> - Set the alpha value for the faces")
-- print("  render_bounds_dynamic <0/1> - Show/hide dynamic entities")
-- print("  render_bounds_static <0/1> - Show/hide static props")