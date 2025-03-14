-- Note to anyone reading: Try to do things on the client if you can!!!
if (SERVER) then
	function RTXLoadServer( ply )  
		print("[RTX Remix Fixes 2] - Initalising Server") 
		
	end 
	hook.Add( "PlayerInitialSpawn", "RTXReadyServer", RTXLoadServer)  

end