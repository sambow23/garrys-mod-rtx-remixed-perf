-- -- Minimal client-side example: spawn a Remix API sphere light bound to the local player

-- local function vec_to_table(v)
--   return { x = v.x, y = v.y, z = v.z }
-- end

-- local function ang_to_dir(a)
--   local fwd = a:Forward()
--   return { x = fwd.x, y = fwd.y, z = fwd.z }
-- end

-- -- Optional queue include to throttle RemixLight operations
-- if file.Exists("remixlua/cl/remixapi/cl_remix_light_queue.lua", "LUA") then
--   include("remixlua/cl/remixapi/cl_remix_light_queue.lua")
-- end

-- -- Spawns a sphere light attached to an entity. Returns the lightId.
-- local function SpawnSphereLightForEntity(ent, radius, rgbIntensity)
--   if not IsValid(ent) or not RemixLight then return nil end

--   local pos = ent:GetPos() + Vector(0, 0, 64)
--   local dir = ang_to_dir(ent:EyeAngles() or ent:GetAngles())

--   -- Base info: make a stable hash using the entity index
--   local base = {
--     -- util.CRC returns a decimal string; convert directly to number to avoid nil, ensuring unique stable hash
--     hash = tonumber(util.CRC(string.format("sphere_light_%d", ent:EntIndex()))) or 1,
--     radiance = { x = rgbIntensity.x, y = rgbIntensity.y, z = rgbIntensity.z },
--   }

--   local sphere = {
--     position = vec_to_table(pos),
--     radius = radius,
--     shaping = {
--       direction = dir,
--       coneAngleDegrees = 35.0,
--       coneSoftness = 0.2,
--       focusExponent = 1.0,
--     },
--     volumetricRadianceScale = 1.0,
--   }

--   if RemixLightQueue and RemixLightQueue.CreateSphere then
--     return RemixLightQueue.CreateSphere(base, sphere, ent:EntIndex())
--   end
--   return RemixLight.CreateSphere and RemixLight.CreateSphere(base, sphere, ent:EntIndex()) or nil
-- end

-- local function RemoveEntityLights(ent)
--   if not IsValid(ent) or not RemixLight then return end
--   if RemixLightQueue and RemixLightQueue.DestroyLight and RemixLight.GetLightsForEntity then
--     local ids = RemixLight.GetLightsForEntity(ent:EntIndex()) or {}
--     for _, id in ipairs(ids) do
--       RemixLightQueue.DestroyLight(id)
--     end
--   else
--     if RemixLight.DestroyLightsForEntity then
--       RemixLight.DestroyLightsForEntity(ent:EntIndex())
--     end
--   end
-- end

-- -- Example usage: spawn a warm light for the local player on map start
-- hook.Add("InitPostEntity", "RemixLightExample_Spawn", function()
--   if not RemixLight then return end
--   local ply = LocalPlayer()
--   if not IsValid(ply) then return end
--   -- Warm-ish tint; values are radiance, so use higher numbers than [0..1]
--   SpawnSphereLightForEntity(ply, 40, Vector(20, 16, 12))
-- end)

-- -- Optional cleanup on shutdown
-- hook.Add("ShutDown", "RemixLightExample_Cleanup", function()
--   local ply = LocalPlayer()
--   if IsValid(ply) then
--     RemoveEntityLights(ply)
--   end
-- end)


