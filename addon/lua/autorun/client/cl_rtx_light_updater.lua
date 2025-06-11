if not CLIENT then return end
require("niknaks")

local lights
local light_positions -- Cache calculated positions
local light_models = {} -- Track individual models for each light
local known_lights = {} -- Track all lights we've encountered
local all_discovered_lights = {} -- Track ALL lights found from NikNaks and dynamic scanning
local stash
local model
local current_map_name
local last_scan_time = 0
local scan_interval = 1 -- Scan for new lights every 1 second
local showlights = CreateConVar( "rtx_lightupdater_show", 0,  FCVAR_ARCHIVE )
local updatelights = CreateConVar( "rtx_lightupdater", 1,  FCVAR_ARCHIVE )
local debugtext = CreateConVar( "rtx_lightupdater_debug", 0,  FCVAR_ARCHIVE )
local debugmoved = CreateConVar( "rtx_lightupdater_debug_moved", 0,  FCVAR_ARCHIVE )
local debugconsole = CreateConVar( "rtx_lightupdater_debug_console", 1,  FCVAR_ARCHIVE )
local debugmissing = CreateConVar( "rtx_lightupdater_debug_missing", 0,  FCVAR_ARCHIVE )
local emergencymode = CreateConVar( "rtx_lightupdater_emergency_mode", 0,  FCVAR_ARCHIVE )
local forcemove = CreateConVar( "rtx_lightupdater_force_move", 0, FCVAR_NONE )

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
	all_discovered_lights = {}
	lights = nil
	light_positions = nil
end

-- Generate unique ID for a light based on its position and type
local function GetLightID(light)
	if not light.origin then return nil end
	return string.format("%s_%.2f_%.2f_%.2f", light.classname or "unknown", 
		light.origin.x, light.origin.y, light.origin.z)
end

-- Proper world bounds check using NikNaks BSP data
local function IsInWorld(pos)
	-- First, strict coordinate check to catch extreme values
	local max_coord = 8192 -- More conservative than 16384
	if math.abs(pos.x) > max_coord or math.abs(pos.y) > max_coord or math.abs(pos.z) > max_coord then
		return false
	end
	
	if not NikNaks or not NikNaks.CurrentMap then
		-- More conservative fallback if NikNaks unavailable
		local fallback_max = 4096
		return not (math.abs(pos.x) > fallback_max or math.abs(pos.y) > fallback_max or math.abs(pos.z) > fallback_max)
	end
	
	-- Get actual world bounds from BSP
	local worldMin, worldMax = NikNaks.CurrentMap:GetBrushBounds()
	
	-- Validate that we got valid bounds
	if not worldMin or not worldMax then
		-- Fallback to conservative bounds if BSP data is invalid
		local fallback_max = 4096
		return not (math.abs(pos.x) > fallback_max or math.abs(pos.y) > fallback_max or math.abs(pos.z) > fallback_max)
	end
	
	-- Add a safety margin to the world bounds (more conservative)
	local margin = 256 -- Stay well within bounds
	local safe_min = worldMin + Vector(margin, margin, margin)
	local safe_max = worldMax - Vector(margin, margin, margin)
	
	-- Check if position is within conservative bounds
	if pos.x < safe_min.x or pos.x > safe_max.x or
	   pos.y < safe_min.y or pos.y > safe_max.y or
	   pos.z < safe_min.z or pos.z > safe_max.z then
		return false
	end
	
	-- Use BSP leaf system to check if position is outside map
	local small_offset = 2 -- Small AABB around the point
	local test_min = pos - Vector(small_offset, small_offset, small_offset)
	local test_max = pos + Vector(small_offset, small_offset, small_offset)
	
	-- Protect against BSP function failures
	local success, result = pcall(function()
		return NikNaks.CurrentMap:IsAABBOutsideMap(test_min, test_max)
	end)
	
	if not success then
		-- If BSP check fails, be conservative and reject extreme positions
		return false
	end
	
	-- Check if any part of this small AABB is outside the map
	if result then
		return false
	end
	
	return true
end

-- Check if a position conflicts with static props
local function IsPositionInStaticProp(pos)
	if not NikNaks or not NikNaks.CurrentMap then
		return false
	end
	
	-- Check against static props in a small area around the position
	local check_radius = 8 -- Increased radius to catch more props
	local nearby_props = NikNaks.CurrentMap:FindStaticInSphere(pos, check_radius)
	
	for _, prop in ipairs(nearby_props) do
		-- Check ALL static props, not just ones with collision
		-- Many decorative props have no collision but still occupy visual space
		local prop_pos = prop:GetPos()
		local prop_mins, prop_maxs = prop:GetModelBounds()
		
		-- Add small padding to prop bounds to avoid placing too close
		local padding = Vector(2, 2, 2)
		
		-- Transform bounds to world space with padding
		local world_mins = prop_pos + prop_mins - padding
		local world_maxs = prop_pos + prop_maxs + padding
		
		-- Check if position is within the prop's bounds (with padding)
		if pos.x >= world_mins.x and pos.x <= world_maxs.x and
		   pos.y >= world_mins.y and pos.y <= world_maxs.y and
		   pos.z >= world_mins.z and pos.z <= world_maxs.z then
			return true
		end
	end
	
	return false
end

-- Enhanced position blocking check that includes static props
local function IsPositionBlocked(pos)
	-- Check if position is inside solid geometry (including props/models)
	local trace = util.TraceHull({
		start = pos,
		endpos = pos,
		mins = Vector(-2, -2, -2),
		maxs = Vector(2, 2, 2),
		mask = MASK_SOLID -- Includes both brushes and props/models
	})
	
	-- Also check static prop bounds directly (more accurate for complex props)
	local in_static_prop = IsPositionInStaticProp(pos)
	
	return trace.Hit or trace.StartSolid or in_static_prop
end

-- Additional validation for reasonable positioning
local function IsPositionReasonable(pos, light_origin)
	-- First check: Is it actually in the world?
	if not IsInWorld(pos) then
		return false
	end
	
	-- Don't allow positions too far from the original light (more conservative)
	local max_distance = 128 -- Reduced from 256 for more conservative positioning
	if light_origin and pos:Distance(light_origin) > max_distance then
		return false
	end
	
	-- Additional strict coordinate check
	local strict_max = 6144 -- Even stricter limit for reasonable positions
	if math.abs(pos.x) > strict_max or math.abs(pos.y) > strict_max or math.abs(pos.z) > strict_max then
		return false
	end
	
	-- Check if position is significantly below reasonable ground level
	-- Use BSP world bounds for more accurate ground estimation
	if NikNaks and NikNaks.CurrentMap then
		local worldMin, worldMax = NikNaks.CurrentMap:GetBrushBounds()
		if worldMin and worldMax then
			local reasonable_min_z = worldMin.z - 256 -- Reduced from 512
			local reasonable_max_z = worldMax.z + 256 -- Also check ceiling
			if pos.z < reasonable_min_z or pos.z > reasonable_max_z then
				return false
			end
		end
	else
		-- Stricter fallback ground check
		if pos.z < -1024 or pos.z > 1024 then
			return false
		end
	end
	
	return true
end

-- Check if a position is within a light's influence area
local function IsPositionInLightInfluence(pos, light)
	if not light.origin then return false end
	
	local distance = pos:Distance(light.origin)
	local light_range = tonumber(light.range) or tonumber(light._light) or 200 -- Default range if not specified
	
	-- Check basic distance first
	if distance > light_range then
		return false
	end
	
	-- For spot lights, be VERY lenient with extremely close positions
	if light.classname == "light_spot" then
		-- If extremely close (under 8 units), just accept it - assume it's in the cone
		if distance < 8 then
			return true
		end
		
		-- For farther positions, do cone checking but be more lenient
		local light_dir = light.angles:Forward()
		local to_pos = (pos - light.origin):GetNormalized()
		local cone_angle = tonumber(light.cone) or tonumber(light._cone) or 45 -- Default cone angle
		
		-- Calculate angle between light direction and position
		local dot_product = light_dir:Dot(to_pos)
		
		-- Ensure dot product is valid (prevent math errors)
		dot_product = math.Clamp(dot_product, -1, 1)
		
		local angle = math.deg(math.acos(dot_product))
		
		-- Be more lenient - use 90% of cone angle instead of 80%
		local cone_half_angle = cone_angle / 2
		local max_allowed_angle = cone_half_angle * 0.9 -- More lenient than before
		
		-- Check if within lenient cone bounds
		if angle > max_allowed_angle then
			return false
		end
	end
	
	return true
end

-- Adjust position to be within light's influence area
local function AdjustPositionForLightInfluence(pos, light)
	if not light.origin then return pos end
	
	-- If it's a spot light, position it EXTREMELY close and DIRECTLY in front
	if light.classname == "light_spot" then
		local light_dir = light.angles:Forward()
		
		-- Try EXTREMELY close distances - almost touching the light
		local ultra_close_distances = {2, 3, 4} -- Extremely close
		
		for _, distance in ipairs(ultra_close_distances) do
			-- Place EXACTLY on the cone axis
			local test_pos = light.origin + (light_dir * distance)
			
			-- Much more lenient validation for spot lights - just check if in world
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) then
				return test_pos
			end
		end
		
		-- Emergency: place at 1 unit if everything else fails
		local emergency_pos = light.origin + (light_dir * 1)
		if IsInWorld(emergency_pos) then
			return emergency_pos
		end
		
	else
		-- Keep existing logic for other lights
		local light_range = tonumber(light.range) or tonumber(light._light) or 200
		light_range = math.min(light_range, 64)
		
		local ideal_distance = math.min(light_range * 0.2, 12)
		local direction = (pos - light.origin):GetNormalized()
		
		if direction:Length() < 0.1 then
			direction = Vector(math.random(-100, 100), math.random(-100, 100), math.random(-50, 50))
			direction = direction:GetNormalized()
		end
		
		local test_distances = {ideal_distance * 0.5, ideal_distance, ideal_distance * 1.5}
		
		for _, distance in ipairs(test_distances) do
			local new_pos = light.origin + (direction * distance)
			if IsInWorld(new_pos) and IsPositionReasonable(new_pos, light.origin) and not IsPositionBlocked(new_pos) then
				return new_pos
			end
		end
	end
	
	-- If all adjustments failed, return original position
	return pos
end

-- Enhanced direction finding that accounts for static props
local function FindBestDirection(light_origin, max_distance, sample_directions)
	max_distance = max_distance or 32
	
	local best_direction = Vector(1, 0, 0)
	local best_distance = 0
	
	-- Get nearby static props to account for in space calculations
	local nearby_props = {}
	if NikNaks and NikNaks.CurrentMap then
		nearby_props = NikNaks.CurrentMap:FindStaticInSphere(light_origin, max_distance * 1.5)
	end
	
	-- Test each direction to find available space
	for _, direction in ipairs(sample_directions) do
		local trace = util.TraceLine({
			start = light_origin,
			endpos = light_origin + (direction * max_distance),
			mask = MASK_SOLID
		})
		
		local available_distance = trace.Fraction * max_distance
		
		-- Additional check: reduce available distance if ANY static props are in the way
		-- Check all props, not just ones with collision (decorative props matter too)
		for _, prop in ipairs(nearby_props) do
			local prop_pos = prop:GetPos()
			local prop_mins, prop_maxs = prop:GetModelBounds()
			
			-- Simple check: if prop center is roughly in this direction, reduce available space
			local to_prop = prop_pos - light_origin
			local dot = to_prop:GetNormalized():Dot(direction)
			
			if dot > 0.7 then -- Prop is roughly in this direction
				local prop_distance = to_prop:Length()
				local prop_radius = math.max(prop_maxs:Length(), 8) -- Rough prop size
				local blocked_distance = math.max(0, prop_distance - prop_radius - 4) -- Extra padding
				
				available_distance = math.min(available_distance, blocked_distance)
			end
		end
		
		-- Prefer directions with more available space
		if available_distance > best_distance then
			best_distance = available_distance
			best_direction = direction
		end
	end
	
	return best_direction, best_distance
end

-- Find a clear position using smart direction finding
local function FindClearPositionSmart(original_pos, light_data)
	local light_origin = light_data.light.origin or original_pos
	
	-- Immediately reject if the light itself is in an extreme location
	if not IsInWorld(light_origin) or not IsPositionReasonable(light_origin, light_origin) then
		-- Don't create updaters for lights that are themselves out of bounds
		if debugconsole:GetBool() then
			print("[RTX Light Updater] Rejected light at extreme location: " .. tostring(light_origin))
		end
		return nil, false
	end
	
	-- Try the original position first (must be clear, in influence, in world, and reasonable)
	if IsInWorld(original_pos) and not IsPositionBlocked(original_pos) and IsPositionInLightInfluence(original_pos, light_data.light) and IsPositionReasonable(original_pos, light_origin) then
		return original_pos, false
	end
	
	-- Try adjusting for light influence first
	local influenced_pos = AdjustPositionForLightInfluence(original_pos, light_data.light)
	if influenced_pos and IsInWorld(influenced_pos) and not IsPositionBlocked(influenced_pos) and IsPositionInLightInfluence(influenced_pos, light_data.light) and IsPositionReasonable(influenced_pos, light_origin) then
		return influenced_pos, true
	end
	
	-- Create comprehensive set of directions to sample
	local sample_directions = {}
	
	-- Horizontal ring (good for most lights)
	for i = 0, 7 do
		local angle = i * 45
		local x = math.cos(math.rad(angle))
		local y = math.sin(math.rad(angle))
		table.insert(sample_directions, Vector(x, y, 0):GetNormalized())
	end
	
	-- Upper hemisphere (for lights near ground)
	for i = 0, 7 do
		local angle = i * 45
		local x = math.cos(math.rad(angle)) * 0.7 -- Slightly angled up
		local y = math.sin(math.rad(angle)) * 0.7
		local z = 0.5
		table.insert(sample_directions, Vector(x, y, z):GetNormalized())
	end
	
	-- Lower hemisphere (for ceiling lights)
	for i = 0, 7 do
		local angle = i * 45
		local x = math.cos(math.rad(angle)) * 0.7 -- Slightly angled down
		local y = math.sin(math.rad(angle)) * 0.7
		local z = -0.5
		table.insert(sample_directions, Vector(x, y, z):GetNormalized())
	end
	
	-- Find the direction with the most empty space
	local best_direction, available_distance = FindBestDirection(light_origin, 32, sample_directions) -- Reduced from 64
	
	-- Try positions along the best direction at various distances
	local test_distances = {}
	
	-- Create a range of distances to test, prioritizing shorter distances
	-- but ensuring we stay within the available space
	local max_test_distance = math.min(available_distance * 0.6, 16) -- Reduced from 0.8 and 24
	
	if max_test_distance > 2 then
		for i = 2, max_test_distance, 2 do
			table.insert(test_distances, i)
		end
	else
		-- If very little space, try tiny distances
		test_distances = {1, 2, 3}
	end
	
	-- Test positions along the best direction
	for _, distance in ipairs(test_distances) do
		local test_pos = light_origin + (best_direction * distance)
		
		-- All conditions must be met, including strict bounds checking
		if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionInLightInfluence(test_pos, light_data.light) and IsPositionReasonable(test_pos, light_origin) then
			-- Verify line of sight back to light
			local trace = util.TraceLine({
				start = test_pos,
				endpos = light_origin,
				mask = MASK_SOLID
			})
			
			if trace.Fraction > 0.8 then -- Higher standard for smart positioning
				return test_pos, true
			end
		end
	end
	
	-- If best direction doesn't work, try the top 3 directions (with stricter limits)
	local direction_scores = {}
	for _, direction in ipairs(sample_directions) do
		local trace = util.TraceLine({
			start = light_origin,
			endpos = light_origin + (direction * 16), -- Reduced from 32
			mask = MASK_SOLID
		})
		table.insert(direction_scores, {direction = direction, score = trace.Fraction})
	end
	
	-- Sort by available space (descending)
	table.sort(direction_scores, function(a, b) return a.score > b.score end)
	
	-- Try the top 3 directions
	for i = 1, math.min(3, #direction_scores) do
		local direction = direction_scores[i].direction
		local max_dist = direction_scores[i].score * 16 * 0.6 -- Reduced distances
		
		for dist = 2, math.min(max_dist, 8), 2 do -- Much more conservative
			local test_pos = light_origin + (direction * dist)
			
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionReasonable(test_pos, light_origin) then
				-- Even if not in light influence, accept it as emergency positioning
				return test_pos, true
			end
		end
	end
	
	-- Last resort: try very close to light origin in the best direction
	for dist = 1, 4 do
		local test_pos = light_origin + (best_direction * dist)
		if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) and IsPositionReasonable(test_pos, light_origin) then
			return test_pos, true
		end
	end
	
	-- Fallback: if all strict validation fails, try more lenient approach
	-- This ensures we don't lose lights that were previously working
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Using lenient fallback for light at: " .. tostring(light_origin))
	end
	
	-- Try very simple positioning with minimal validation
	for _, distance in ipairs({2, 4, 6, 8}) do
		for _, direction in ipairs(sample_directions) do
			local test_pos = light_origin + (direction * distance)
			
			-- Only check basic world bounds and collision - skip reasonable position check
			if IsInWorld(test_pos) and not IsPositionBlocked(test_pos) then
				return test_pos, true
			end
		end
	end
	
	-- Final emergency: place at light origin if it's in world (even if not ideal)
	if IsInWorld(light_origin) then
		if debugconsole:GetBool() then
			print("[RTX Light Updater] Emergency fallback: placing at light origin")
		end
		return light_origin, true
	end
	
	-- Complete failure: don't create an updater for this light
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Failed to find any valid position for light at: " .. tostring(light_origin))
	end
	return nil, false
end

-- Use the smart positioning system
local function FindClearPosition(original_pos, light_data)
	return FindClearPositionSmart(original_pos, light_data)
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

-- Emergency positioning for lights that fail normal validation
local function FindEmergencyPosition(light)
	if not light.origin then return nil end
	
	local light_origin = light.origin
	
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Emergency positioning for light at: " .. tostring(light_origin))
	end
	
	-- Try extremely simple positions with minimal validation
	local emergency_directions = {
		Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0),
		Vector(0, 0, 1), Vector(0, 0, -1), -- Up/down
		Vector(1, 1, 0):GetNormalized(), Vector(-1, -1, 0):GetNormalized(),
		Vector(1, -1, 0):GetNormalized(), Vector(-1, 1, 0):GetNormalized()
	}
	
	-- Try very close distances first
	local emergency_distances = {1, 2, 3, 4, 6, 8, 12, 16}
	
	for _, distance in ipairs(emergency_distances) do
		for _, direction in ipairs(emergency_directions) do
			local test_pos = light_origin + (direction * distance)
			
			-- VERY minimal validation - just check it's not in solid geometry and somewhat reasonable
			local basic_max = 10000 -- Much more lenient coordinate check
			local coords_ok = math.abs(test_pos.x) < basic_max and math.abs(test_pos.y) < basic_max and math.abs(test_pos.z) < basic_max
			
			if coords_ok then
				-- Simple collision check only
				local trace = util.TraceHull({
					start = test_pos,
					endpos = test_pos,
					mins = Vector(-1, -1, -1), -- Smaller hull
					maxs = Vector(1, 1, 1),
					mask = MASK_SOLID
				})
				
				if not (trace.Hit or trace.StartSolid) then
					if debugconsole:GetBool() then
						print("[RTX Light Updater] Emergency position found at distance " .. distance .. ": " .. tostring(test_pos))
					end
					return test_pos
				end
			end
		end
	end
	
	-- Last resort: try positions directly at light origin with small offsets
	local tiny_offsets = {
		Vector(0.5, 0, 0), Vector(-0.5, 0, 0), Vector(0, 0.5, 0), Vector(0, -0.5, 0),
		Vector(0, 0, 0.5), Vector(0, 0, -0.5), Vector(0, 0, 0) -- Even try exactly at origin
	}
	
	for _, offset in ipairs(tiny_offsets) do
		local test_pos = light_origin + offset
		
		-- Absolute minimal check - just make sure coordinates aren't completely insane
		if math.abs(test_pos.x) < 20000 and math.abs(test_pos.y) < 20000 and math.abs(test_pos.z) < 20000 then
			-- Don't even check collision for these emergency positions
			if debugconsole:GetBool() then
				print("[RTX Light Updater] Ultra-emergency position (minimal validation): " .. tostring(test_pos))
			end
			return test_pos
		end
	end
	
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Emergency positioning completely failed for: " .. tostring(light_origin))
	end
	return nil
end

-- Add a new light to our tracking system
local function AddLight(light)
	local light_id = GetLightID(light)
	if not light_id then return false end
	
	-- Always add to discovered lights (even if we already have it or it fails)
	all_discovered_lights[light_id] = light
	
	-- Skip if we already have this light
	if known_lights[light_id] then return false end
	
	if light.origin and light.angles then
		local original_pos
		
		-- For spot lights, position EXTREMELY close directly in front
		if light.classname == "light_spot" then
			local light_dir = light.angles:Forward()
			original_pos = light.origin + (light_dir * 2) -- EXTREMELY close - 2 units
		else
			-- For other lights, position slightly offset (original logic)
			original_pos = light.origin - (light.angles:Forward() * 8)
		end
		
		local adjusted_pos, was_moved = FindClearPosition(original_pos, {light = light})
		
		-- Only create light updater if we found a valid position
		if adjusted_pos then
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
		else
			-- If emergency mode is enabled, try emergency positioning
			if emergencymode:GetBool() then
				local emergency_pos = FindEmergencyPosition(light)
				if emergency_pos then
					known_lights[light_id] = {
						light = light,
						original_pos = original_pos,
						pos = emergency_pos,
						was_moved = true, -- Mark as moved since it's emergency positioning
						classname = light.classname,
						emergency = true -- Mark as emergency positioned
					}
					
					-- Add to legacy arrays for compatibility
					if not lights then lights = {} end
					if not light_positions then light_positions = {} end
					
					table.insert(lights, light)
					light_positions[#lights] = emergency_pos
					
					if debugconsole:GetBool() then
						print("[RTX Light Updater] Emergency updater created for " .. (light.classname or "light") .. " at: " .. tostring(emergency_pos))
					end
					
					return true
				end
			end
		end
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
		
		local total_lights_found = #lights
		local lights_processed = 0
		
		-- Pre-calculate all positions and add to known lights
		light_positions = {}
		for i, light in pairs(lights) do
			-- Add to all discovered lights first
			local light_id = GetLightID(light)
			if light_id then
				all_discovered_lights[light_id] = light
			end
			
			if light.origin and light.angles then
				local original_pos
				
				-- For spot lights, position EXTREMELY close directly in front
				if light.classname == "light_spot" then
					local light_dir = light.angles:Forward()
					original_pos = light.origin + (light_dir * 2) -- EXTREMELY close - 2 units
				else
					-- For other lights, position slightly offset (original logic)
					original_pos = light.origin - (light.angles:Forward() * 8)
				end
				
				local adjusted_pos, was_moved = FindClearPosition(original_pos, {light = light})
				
				-- Only create light updater if we found a valid position
				if adjusted_pos then
					light_positions[i] = adjusted_pos
					lights_processed = lights_processed + 1
					
					-- Add to known lights tracking
					if light_id then
						known_lights[light_id] = {
							light = light,
							original_pos = original_pos,
							pos = adjusted_pos,
							was_moved = was_moved,
							classname = light.classname
						}
					end
				else
					-- If emergency mode is enabled, try emergency positioning
					if emergencymode:GetBool() then
						local emergency_pos = FindEmergencyPosition(light)
						if emergency_pos then
							light_positions[i] = emergency_pos
							lights_processed = lights_processed + 1
							
							-- Add to known lights tracking with emergency flag
							if light_id then
								known_lights[light_id] = {
									light = light,
									original_pos = original_pos,
									pos = emergency_pos,
									was_moved = true, -- Mark as moved since it's emergency positioning
									classname = light.classname,
									emergency = true -- Mark as emergency positioned
								}
							end
							
							if debugconsole:GetBool() then
								print("[RTX Light Updater] Emergency updater created for " .. (light.classname or "light") .. " at: " .. tostring(emergency_pos))
							end
						end
					end
				end
				-- If adjusted_pos is nil, we skip this light (don't create an updater)
			end
		end
		
		-- Report processing results
		if debugconsole:GetBool() or lights_processed < total_lights_found then
			if debugconsole:GetBool() then
				print("[RTX Light Updater] Processed " .. lights_processed .. " / " .. total_lights_found .. " lights")
			end
			if lights_processed < total_lights_found and debugconsole:GetBool() then
				print("[RTX Light Updater] " .. (total_lights_found - lights_processed) .. " lights were skipped (couldn't find valid positions)")
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

-- Force recalculate all light positions
local function ForceRecalculateAllLights()
	-- Clean up all existing light models
	for id, light_model in pairs(light_models) do
		if IsValid(light_model) then
			light_model:Remove()
		end
	end
	light_models = {}
	
	-- Clear the known lights cache to force recalculation
	local old_known_lights = known_lights
	local old_count = table.Count(old_known_lights)
	known_lights = {}
	all_discovered_lights = {}
	lights = nil
	light_positions = nil
	
	-- Force re-initialization of lights with new positions
	if InitializeLights() then
		-- Re-scan for dynamic lights too
		ScanForNewLights()
		
		local new_count = table.Count(known_lights)
		if debugconsole:GetBool() then
			print("[RTX Light Updater] Force moved all lights - " .. new_count .. " lights repositioned (was " .. old_count .. ")")
			
			if new_count < old_count then
				print("[RTX Light Updater] WARNING: Lost " .. (old_count - new_count) .. " light updaters during repositioning")
				print("[RTX Light Updater] Enable rtx_lightupdater_debug_console 1 for more details")
			end
		end
	else
		if debugconsole:GetBool() then
			print("[RTX Light Updater] Failed to force move lights - initialization failed")
		end
	end
end

local function MovetoPositions()
	if not updatelights:GetBool() then return end
	
	-- Check if force move is requested
	if forcemove:GetBool() then
		ForceRecalculateAllLights()
		forcemove:SetBool(false) -- Reset the cvar after force move
		return -- Skip normal processing this frame to allow recalculation
	end
	
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
			-- Use different colors for emergency, moved, vs original positions
			local outer_color, inner_color
			
			if light_data.emergency then
				-- Purple/magenta for emergency positioned lights
				outer_color = {255, 0, 255, 200} -- Magenta
				inner_color = {255, 100, 255, 200} -- Light magenta
			elseif light_data.was_moved then
				-- Orange for moved lights
				outer_color = {255, 100, 0, 200} -- Orange
				inner_color = {255, 200, 0, 200} -- Brighter orange
			else
				-- Cyan for original position lights
				outer_color = {0, 255, 255, 200} -- Cyan
				inner_color = {255, 255, 0, 200} -- Yellow
			end
			
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
			if light_data.emergency then
				class_text = class_text .. " (EMERGENCY)"
			elseif light_data.was_moved then
				class_text = class_text .. " (MOVED)"
			end
			
			-- Add out of bounds warning
			local is_in_world = IsInWorld(light_data.pos)
			local is_reasonable = IsPositionReasonable(light_data.pos, light_data.light.origin)
			
			if not is_in_world or not is_reasonable then
				class_text = class_text .. " (OUT OF BOUNDS)"
			end
			
			local text_color
			if light_data.emergency then
				text_color = Color(255, 0, 255, 255) -- Magenta for emergency
			elseif light_data.was_moved then
				text_color = Color(255, 150, 0, 255) -- Orange for moved
			else
				text_color = Color(255, 255, 0, 255) -- Yellow for normal
			end
			
			draw.SimpleText(
				class_text,
				"DermaDefault",
				screen_pos.x,
				screen_pos.y - 10,
				text_color,
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
			
			-- Additional debug info if out of bounds
			if not is_in_world or not is_reasonable then
				draw.SimpleText(
					"BOUNDS CHECK FAILED",
					"DermaDefault",
					screen_pos.x,
					screen_pos.y + 30,
					Color(255, 0, 0, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
			end
		end
	end
end

-- Draw debug info for lights that don't have updaters
local function DrawMissingLightsDebug()
	if not debugmissing:GetBool() or not all_discovered_lights then return end
	
	-- Find lights that were discovered but don't have updaters
	for light_id, light in pairs(all_discovered_lights) do
		if not known_lights[light_id] and light.origin then
			local text_pos = light.origin + Vector(0, 0, 20)
			local screen_pos = text_pos:ToScreen()
			
			if screen_pos.visible then
				-- Draw a red X marker
				surface.SetDrawColor(255, 0, 0, 200)
				local size = 8
				surface.DrawLine(screen_pos.x - size, screen_pos.y - size, screen_pos.x + size, screen_pos.y + size)
				surface.DrawLine(screen_pos.x - size, screen_pos.y + size, screen_pos.x + size, screen_pos.y - size)
				
				-- Draw a red circle around it
				for i = 0, 360, 20 do
					local x1 = screen_pos.x + math.cos(math.rad(i)) * 12
					local y1 = screen_pos.y + math.sin(math.rad(i)) * 12
					local x2 = screen_pos.x + math.cos(math.rad(i + 20)) * 12
					local y2 = screen_pos.y + math.sin(math.rad(i + 20)) * 12
					surface.DrawLine(x1, y1, x2, y2)
				end
				
				-- Text showing it's missing
				local class_text = (light.classname or "light") .. " (NO UPDATER)"
				draw.SimpleText(
					class_text,
					"DermaDefault",
					screen_pos.x,
					screen_pos.y - 15,
					Color(255, 0, 0, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
				
				-- Show coordinates
				draw.SimpleText(
					string.format("%.0f %.0f %.0f", 
						light.origin.x, light.origin.y, light.origin.z
					),
					"DermaDefault",
					screen_pos.x,
					screen_pos.y + 15,
					Color(255, 100, 100, 255),
					TEXT_ALIGN_CENTER,
					TEXT_ALIGN_CENTER
				)
			end
		end
	end
end

local function RTXLightUpdater()
	MovetoPositions()
end

-- Cleanup on disconnect/shutdown
local function Cleanup()
	CleanupModel()
	-- Reset force move cvar on cleanup
	forcemove:SetBool(false)
end

-- Console command for easier access to force move
local function ForceMoveLightsCommand()
	forcemove:SetBool(true)
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Force move requested - all light positions will be recalculated next frame")
	end
end

-- Console command to try adding updaters for missing lights
local function AddMissingLightsCommand()
	if not all_discovered_lights then
		if debugconsole:GetBool() then
			print("[RTX Light Updater] No lights discovered yet - wait for initialization or change maps")
		end
		return
	end
	
	local missing_count = 0
	local added_count = 0
	
	-- Find lights that don't have updaters
	for light_id, light in pairs(all_discovered_lights) do
		if not known_lights[light_id] then
			missing_count = missing_count + 1
			
			-- Try to add this light using emergency positioning
			local was_emergency_enabled = emergencymode:GetBool()
			emergencymode:SetBool(true) -- Temporarily enable emergency mode
			
			local success = AddLight(light)
			if success then
				added_count = added_count + 1
			end
			
			-- Restore original emergency mode setting
			emergencymode:SetBool(was_emergency_enabled)
		end
	end
	
	if debugconsole:GetBool() then
		print("[RTX Light Updater] Found " .. missing_count .. " lights without updaters")
		print("[RTX Light Updater] Successfully added " .. added_count .. " emergency updaters")
		if added_count < missing_count then
			print("[RTX Light Updater] " .. (missing_count - added_count) .. " lights still failed emergency positioning")
		end
	end
end

-- Register console command
concommand.Add("rtx_lightupdater_force_move_cmd", ForceMoveLightsCommand, nil, "Force recalculate all RTX light updater positions")
concommand.Add("rtx_lightupdater_add_missing_cmd", AddMissingLightsCommand, nil, "Try to add updaters for lights that don't have them using emergency positioning")

hook.Add( "Think", "RTXReady_PropHashFixer", RTXLightUpdater)
hook.Add( "HUDPaint", "RTXReady_LightIndicators", DrawLightIndicators)
hook.Add( "HUDPaint", "RTXReady_MovedDebug", DrawMovedPositionDebug)
hook.Add( "HUDPaint", "RTXReady_DebugText", DrawDebugText)
hook.Add( "HUDPaint", "RTXReady_MissingLightsDebug", DrawMissingLightsDebug)
hook.Add( "ShutDown", "RTXReady_Cleanup", Cleanup)
hook.Add( "OnEntityCreated", "RTXReady_MapCheck", function(ent)
	-- Reset when worldspawn is created (new map)
	if ent:GetClass() == "worldspawn" then
		CleanupModel()
	end
end)

-- Print help information on load
timer.Simple(1, function()
	if debugconsole:GetBool() then
		print("======================================")
		print("RTX Light Updater Loaded")
		print("======================================")
		print("Commands:")
		print("  rtx_lightupdater 0/1               - Enable/disable system")
		print("  rtx_lightupdater_show 0/1          - Show/hide visual indicators")
		print("  rtx_lightupdater_debug 0/1         - Show/hide debug text")
		print("  rtx_lightupdater_debug_moved 0/1   - Show moved position debug")
		print("  rtx_lightupdater_debug_missing 0/1 - Show lights without updaters")
		print("  rtx_lightupdater_emergency_mode 0/1 - Enable emergency positioning")
		print("  rtx_lightupdater_debug_console 0/1 - Enable/disable console output")
		print("  rtx_lightupdater_force_move 1      - Force recalculate all positions")
		print("  rtx_lightupdater_force_move_cmd    - Same as above (command)")
		print("  rtx_lightupdater_add_missing_cmd   - Add updaters for missing lights")
		print("======================================")
		print("Visual Legend:")
		print("  Cyan circles = Normal positioned lights")
		print("  Orange circles = Moved positioned lights") 
		print("  Magenta circles = Emergency positioned lights")
		print("  Red X = Lights without updaters")
		print("======================================")
	end
end)  