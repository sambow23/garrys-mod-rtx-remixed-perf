-- Note to anyone reading: Try to do things on the client if you can!!!
if (SERVER) then
	-- Initialize NikNaks
	require("niknaks")

	-- Create debug ConVar for server-side debugging
	local cv_debug = CreateConVar("rtx_rt_debug_sv", "0", FCVAR_ARCHIVE, "Enable debug messages for RT States on server")

	-- Helper function for debug printing
	local function DebugPrint(message)
		if cv_debug:GetBool() then
			print("[gmRTX-SV] " .. message)
		end
	end

	local function LoadServerSubAddons()
		-- First, send ALL necessary files to clients (shared AND client files)
		local allowCSLua = GetConVar("sv_allowcslua")
		if allowCSLua and allowCSLua:GetBool() then
			DebugPrint("sv_allowcslua is enabled, sending shared and client files to clients")
			
			-- Send shared files to clients (CRITICAL for multiplayer)
			local sharedFiles, _ = file.Find("remixlua/sh/*.lua", "LUA")
			if sharedFiles then
				DebugPrint("Sending " .. #sharedFiles .. " shared files to clients")
				for _, fileName in ipairs(sharedFiles) do
					local filePath = "remixlua/sh/" .. fileName
					AddCSLuaFile(filePath)
					DebugPrint("Sent shared file: " .. filePath)
				end
			end
			
			-- Send client files to clients
			local clientFolders = {"remixlua/cl/", "remixlua/cl/remixapi/"}
			for _, folder in ipairs(clientFolders) do
				local files, _ = file.Find(folder .. "*.lua", "LUA")
				if files then
					DebugPrint("Sending " .. #files .. " client files from " .. folder)
					for _, fileName in ipairs(files) do
						local filePath = folder .. fileName
						AddCSLuaFile(filePath)
						DebugPrint("Sent client file: " .. filePath)
					end
				end
			end
		else
			DebugPrint("sv_allowcslua is disabled, not sending files to clients")
		end

		-- Load server-side files on the server
		local foldersToLoad = {}
		
		-- Always load shared files on server
		table.insert(foldersToLoad, "remixlua/sh/")
		
		-- Always load server files 
		table.insert(foldersToLoad, "remixlua/sv/")
		
		for _, folder in ipairs(foldersToLoad) do
			local files, _ = file.Find(folder .. "*.lua", "LUA")
			
			if files then
				DebugPrint("Found " .. #files .. " files in " .. folder)
				
				for _, fileName in ipairs(files) do
					local filePath = folder .. fileName
					local success, err = pcall(include, filePath)
					
					if not success then
						DebugPrint("Warning: Failed to load sub-addon: " .. filePath .. " - Error: " .. tostring(err))
					else
						DebugPrint("Successfully loaded sub-addon: " .. filePath)
					end
				end
			else
				DebugPrint("No files found in " .. folder)
			end
		end
	end

	-- Load sub-addons immediately when server starts
	print("[gmRTX] - Initialising Server") 
	LoadServerSubAddons()

	function RTXLoadServer( ply )  
		-- This still runs when players spawn for any per-player initialization
		DebugPrint("Player " .. tostring(ply) .. " spawned")
	end 
	hook.Add( "PlayerInitialSpawn", "RTXReadyServer", RTXLoadServer)  

end

if SERVER then
    util.AddNetworkString("remix_spawn_rt_light")
    net.Receive("remix_spawn_rt_light", function(len, ply)
        if not IsValid(ply) then return end
        local pos = net.ReadVector()
        local ent = ents.Create("remix_rt_light")
        if not IsValid(ent) then return end
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        ent:Spawn()
        ent:Activate()
    end)
end