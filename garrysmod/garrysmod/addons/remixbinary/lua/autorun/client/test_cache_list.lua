if not CLIENT then return end

print("\n[Texture Cache List] Loading...")

concommand.Add("rtx_list_cached_materials", function(ply, cmd, args)
    if not RemixMaterial or not RemixMaterial.GetCachedMaterials then
        print("[Cache List] ERROR: RemixMaterial.GetCachedMaterials not available!")
        return
    end
    
    local filter = args[1] -- Optional filter string
    
    local materials = RemixMaterial.GetCachedMaterials()
    local count = #materials
    
    print(string.format("\n[Cache List] Found %d cached materials:", count))
    print(string.rep("-", 60))
    
    local shownCount = 0
    for _, matName in ipairs(materials) do
        if not filter or string.find(matName:lower(), filter:lower(), 1, true) then
            -- Get hash for this material
            local hash, hashStr = RemixMaterial.GetTextureHash(matName)
            local displayHash = hashStr or (hash and string.format("0x%X", hash) or "N/A")
            
            print(string.format("%-40s | %s", matName, displayHash))
            shownCount = shownCount + 1
        end
    end
    
    print(string.rep("-", 60))
    if filter then
        print(string.format("Shown: %d (filtered by '%s')", shownCount, filter))
    else
        print(string.format("Total: %d", count))
    end
end)

print("[Texture Cache List] Command loaded: rtx_list_cached_materials [filter]")

