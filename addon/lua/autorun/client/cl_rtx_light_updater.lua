if not CLIENT then return end
require("niknaks")

local lights
local light_positions -- Cache calculated positions
local light_models = {} -- Track individual models for each light
local known_lights = {} -- Track all lights we've encountered
local stash
local model
local current_map_name
local last_scan_time = 0
local scan_interval = 1 -- Scan for new lights every 1 second
local showlights = CreateConVar( "rtx_lightupdater_show", 0,  FCVAR_ARCHIVE )
local updatelights = CreateConVar( "rtx_lightupdater", 1,  FCVAR_ARCHIVE )
local debugtext = CreateConVar( "rtx_lightupdater_debug", 0,  FCVAR_ARCHIVE )
local debugmoved = CreateConVar( "rtx_lightupdater_debug_moved", 0,  FCVAR_ARCHIVE )

local function shuffle(tbl)
	for i = #tbl, 2, -1 do
	  local j = math.random(i)
	  tbl[i], tbl[j] = tbl[j], tbl[i]
	end
	return tbl
end

local function TableConcat(t1,t2)
	for i=1,#t2 do
		t1[#t1+1] = t2[i]
	end
	return t1
end

-- Clean up existing model and reset data
local function CleanupModel()
	if IsValid(model) then
		model:Remove()
	end
	model = nil
	
	-- Clean up individual light models
	for id, light_model in pairs(light_models) do
		if IsValid(light_model) then
			light_model:Remove()
		end
	end
	light_models = {}
	known_lights = {}
	lights = nil
	light_positions = nil
end

-- Generate unique ID for a light based on its position and type
local function GetLightID(light)
	if not light.origin then return nil end
	return string.format("%s_%.2f_%.2f_%.2f", light.classname or "unknown", 
		light.origin.x, light.origin.y, light.origin.z)
end

-- Check if a position is inside a wall or out of bounds
local function IsPositionBlocked(pos)
	-- Check if position is inside solid geometry
	local trace = util.TraceHull({
		start = pos,
		endpos = pos,
		mins = Vector(-2, -2, -2),
		maxs = Vector(2, 2, 2),
		mask = MASK_SOLID_BRUSHONLY
	})
	
	return trace.Hit or trace.StartSolid
end

-- Find a clear position near the original light position
local function FindClearPosition(original_pos, light_data)
	-- Try the original position first
	if not IsPositionBlocked(original_pos) then
		return original_pos, false
	end
	
	-- Define search directions (outward from light)
	local search_directions = {
		Vector(1, 0, 0), Vector(-1, 0, 0),
		Vector(0, 1, 0), Vector(0, -1, 0),
		Vector(0, 0, 1), Vector(0, 0, -1),
		Vector(1, 1, 0), Vector(-1, -1, 0),
		Vector(1, -1, 0), Vector(-1, 1, 0),
		Vector(1, 0, 1), Vector(-1, 0, -1),
		Vector(0, 1, 1), Vector(0, -1, -1)
	}
	
	-- Try different distances
	local search_distances = {4, 8, 16, 32, 64}
	
	for _, distance in ipairs(search_distances) do
		for _, direction in ipairs(search_directions) do
			local test_pos = original_pos + (direction * distance)
			
			if not IsPositionBlocked(test_pos) then
				-- Make sure we can trace from the new position back toward the light
				local trace = util.TraceLine({
					start = test_pos,
					endpos = light_data.light.origin or original_pos,
					mask = MASK_SOLID_BRUSHONLY
				})
				
				-- If we have a mostly clear line of sight, use this position
				if trace.Fraction > 0.3 then
					return test_pos, true
				end
			end
		end
	end
	
	-- If all else fails, try moving up from original position
	for i = 1, 10 do
		local test_pos = original_pos + Vector(0, 0, i * 8)
		if not IsPositionBlocked(test_pos) then
			return test_pos, true
		end
	end
	
	-- Last resort: return original position
	return original_pos, false
end

-- Create a model for a specific light
local function CreateLightModel(light_id, pos)
	local light_model = ClientsideModel("models/hunter/plates/plate.mdl")
	if not IsValid(light_model) then
		return nil
	end
	
	light_model:Spawn()
	light_model:SetRenderMode(2) -- Always invisible
	light_model:SetColor(Color(255,255,255,1))
	
	light_models[light_id] = light_model
	return light_model
end

-- Add a new light to our tracking system
local function AddLight(light)
	local light_id = GetLightID(light)
	if not light_id or known_lights[light_id] then return false end
	
	if light.origin and light.angles then
		local original_pos = light.origin - (light.angles:Forward() * 8)
		local adjusted_pos, was_moved = FindClearPosition(original_pos, {light = light})
		
		known_lights[light_id] = {
			light = light,
			original_pos = original_pos,
			pos = adjusted_pos,
			was_moved = was_moved,
			classname = light.classname
		}
		
		-- Add to legacy arrays for compatibility
		if not lights then lights = {} end
		if not light_positions then light_positions = {} end
		
		table.insert(lights, light)
		light_positions[#lights] = adjusted_pos
		
		return true
	end
	return false
end

-- Scan for new dynamic lights
local function ScanForNewLights()
	local current_time = CurTime()
	if current_time - last_scan_time < scan_interval then return end
	last_scan_time = current_time
	
	-- Get all currently active light entities
	local dynamic_lights = ents.FindByClass("light*")
	
	for _, light in pairs(dynamic_lights) do
		if IsValid(light) then
			AddLight(light)
		end
	end
end

-- Initialize or reinitialize lights data
local function InitializeLights()
	if not NikNaks or not NikNaks.CurrentMap then
		return false
	end
	
	local new_map_name = game.GetMap()
	if current_map_name ~= new_map_name then
		CleanupModel()
		current_map_name = new_map_name
	end
	
	if lights == nil then
		lights = NikNaks.CurrentMap:FindByClass( "light" ) or {}
		
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_spot" ) or {})
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_environment" ) or {})
		lights = TableConcat(lights, NikNaks.CurrentMap:FindByClass( "light_dynamic" ) or {})
		
		-- Pre-calculate all positions and add to known lights
		light_positions = {}
		for i, light in pairs(lights) do
			if light.origin and light.angles then
				local original_pos = light.origin - (light.angles:Forward() * 8)
				local adjusted_pos, was_moved = FindClearPosition(original_pos, {light = light})
				light_positions[i] = adjusted_pos
				
				-- Add to known lights tracking
				local light_id = GetLightID(light)
				if light_id then
					known_lights[light_id] = {
						light = light,
						original_pos = original_pos,
						pos = adjusted_pos,
						was_moved = was_moved,
						classname = light.classname
					}
				end
			end
		end
	end
	
	return true
end

-- Create the model if needed
local function InitializeModel()
	if not IsValid(model) then
		model = ClientsideModel("models/hunter/plates/plate.mdl")
		if not IsValid(model) then
			return false
		end
		
		model:Spawn()
		model:SetRenderMode(2) -- Always invisible
		model:SetColor(Color(255,255,255,1))
	end
	
	return true
end

local function MovetoPositions()
	if not updatelights:GetBool() then return end
	
	-- Initialize lights if needed
	if not InitializeLights() then return end
	
	-- Scan for new dynamic lights
	ScanForNewLights()
	
	-- Initialize model if needed
	if not InitializeModel() then return end
	
	-- Render at all cached positions using individual models
	for light_id, light_data in pairs(known_lights) do
		local light_model = light_models[light_id]
		if not IsValid(light_model) then
			light_model = CreateLightModel(light_id, light_data.pos)
		end
		
		if IsValid(light_model) then
			render.Model({model = "models/hunter/plates/plate.mdl", pos = light_data.pos}, light_model)
		end
	end
end

-- Draw visual indicators when show lights is enabled
local function DrawLightIndicators()
	if not showlights:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		local screen_pos = light_data.pos:ToScreen()
		
		if screen_pos.visible then
			-- Use different colors for moved vs original positions
			local outer_color = light_data.was_moved and {255, 100, 0, 200} or {0, 255, 255, 200} -- Orange if moved, cyan if original
			local inner_color = light_data.was_moved and {255, 200, 0, 200} or {255, 255, 0, 200} -- Brighter orange if moved, yellow if original
			
			-- Draw outer circle
			surface.SetDrawColor(outer_color[1], outer_color[2], outer_color[3], outer_color[4])
			for i = 0, 360, 10 do
				local x1 = screen_pos.x + math.cos(math.rad(i)) * 8
				local y1 = screen_pos.y + math.sin(math.rad(i)) * 8
				local x2 = screen_pos.x + math.cos(math.rad(i + 10)) * 8
				local y2 = screen_pos.y + math.sin(math.rad(i + 10)) * 8
				surface.DrawLine(x1, y1, x2, y2)
			end
			
			-- Draw inner circle
			surface.SetDrawColor(inner_color[1], inner_color[2], inner_color[3], inner_color[4])
			for i = 0, 360, 15 do
				local x1 = screen_pos.x + math.cos(math.rad(i)) * 3
				local y1 = screen_pos.y + math.sin(math.rad(i)) * 3
				local x2 = screen_pos.x + math.cos(math.rad(i + 15)) * 3
				local y2 = screen_pos.y + math.sin(math.rad(i + 15)) * 3
				surface.DrawLine(x1, y1, x2, y2)
			end
			
			-- Draw crosshair
			surface.SetDrawColor(255, 255, 255, 255) -- White crosshair
			surface.DrawLine(screen_pos.x - 12, screen_pos.y, screen_pos.x + 12, screen_pos.y)
			surface.DrawLine(screen_pos.x, screen_pos.y - 12, screen_pos.x, screen_pos.y + 12)
		end
	end
end

-- Draw debug indicators for moved positions
local function DrawMovedPositionDebug()
	if not debugmoved:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		if light_data.was_moved then
			local original_screen = light_data.original_pos:ToScreen()
			local adjusted_screen = light_data.pos:ToScreen()
			
			-- Draw line connecting original to adjusted position
			if original_screen.visible and adjusted_screen.visible then
				surface.SetDrawColor(255, 0, 0, 150) -- Red line
				surface.DrawLine(original_screen.x, original_screen.y, adjusted_screen.x, adjusted_screen.y)
			end
			
			-- Draw X marker at original position
			if original_screen.visible then
				surface.SetDrawColor(255, 0, 0, 200) -- Red X
				surface.DrawLine(original_screen.x - 6, original_screen.y - 6, original_screen.x + 6, original_screen.y + 6)
				surface.DrawLine(original_screen.x - 6, original_screen.y + 6, original_screen.x + 6, original_screen.y - 6)
			end
		end
	end
end

-- Draw debug text in proper HUD hook
local function DrawDebugText()
	if not debugtext:GetBool() or not known_lights then return end
	
	for light_id, light_data in pairs(known_lights) do
		local text_pos = light_data.pos + Vector(0, 0, 16)
		local screen_pos = text_pos:ToScreen()
		
		if screen_pos.visible then
			local class_text = light_data.classname or "light"
			if light_data.was_moved then
				class_text = class_text .. " (MOVED)"
			end
			
			draw.SimpleText(
				class_text,
				"DermaDefault",
				screen_pos.x,
				screen_pos.y - 10,
				light_data.was_moved and Color(255, 150, 0, 255) or Color(255, 255, 0, 255),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER
			)
			
			draw.SimpleText(
				string.format("%.0f %.0f %.0f", 
					light_data.pos.x, light_data.pos.y, light_data.pos.z
				),
				"DermaDefault",
				screen_pos.x,
				screen_pos.y + 10,
				Color(255, 255, 255, 255),
				TEXT_ALIGN_CENTER,
				TEXT_ALIGN_CENTER
			)
		end
	end
end

local function RTXLightUpdater()
	MovetoPositions()
end

-- Cleanup on disconnect/shutdown
local function Cleanup()
	CleanupModel()
end

hook.Add( "Think", "RTXReady_PropHashFixer", RTXLightUpdater)
hook.Add( "HUDPaint", "RTXReady_LightIndicators", DrawLightIndicators)
hook.Add( "HUDPaint", "RTXReady_MovedDebug", DrawMovedPositionDebug)
hook.Add( "HUDPaint", "RTXReady_DebugText", DrawDebugText)
hook.Add( "ShutDown", "RTXReady_Cleanup", Cleanup)
hook.Add( "OnEntityCreated", "RTXReady_MapCheck", function(ent)
	-- Reset when worldspawn is created (new map)
	if ent:GetClass() == "worldspawn" then
		CleanupModel()
	end
end)  