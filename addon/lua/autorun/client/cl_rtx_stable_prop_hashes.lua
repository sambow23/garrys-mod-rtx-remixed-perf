if not CLIENT then return end
CreateClientConVar(	"rtx_disablevertexlighting", 0,  true, false) 


local function FixupModelMaterial(mat)
    -- Check if material is valid
    if not mat or not type(mat) == "IMaterial" then
        print("[RTX Fixes] Skipping invalid material")
        return
    end

    -- Safe way to get flags2
    local success, flags2 = pcall(function()
        return mat:GetInt("$flags2")
    end)

    if not success or not flags2 then
        print("[RTX Fixes] Could not get flags2 for material:", mat:GetName())
        return
    end

    -- Safe way to set flags2
    local newFlags = bit.band(flags2, bit.bnot(512))
    success = pcall(function()
        mat:SetInt("$flags2", newFlags)
    end)

    if not success then
        print("[RTX Fixes] Failed to set flags2 for material:", mat:GetName())
    end
end

local function DrawFix( self, flags )
    if (GetConVar( "mat_fullbright" ):GetBool()) then return end
    render.SuppressEngineLighting( GetConVar( "rtx_disablevertexlighting" ):GetBool() )

	if (self:GetMaterial() != "") then -- Fixes material tool and lua SetMaterial
		render.MaterialOverride(Material(self:GetMaterial()))
	end

	for k, v in pairs(self:GetMaterials()) do -- Fixes submaterial tool and lua SetSubMaterial
		if (self:GetSubMaterial( k-1 ) != "") then
			render.MaterialOverrideByIndex(k-1, Material(self:GetSubMaterial( k-1 )))
		end
	end
 
	self:DrawModel(bit.bor(flags, STUDIO_STATIC_LIGHTING)) -- Fix hash instability
	render.MaterialOverride(nil)
    render.SuppressEngineLighting( false )

end

local function ApplyRenderOverride(ent)
	ent.RenderOverride = DrawFix 
end
local function FixupEntity(ent) 
	if (ent:GetClass() != "procedural_shard") then ApplyRenderOverride(ent) end
	for k, v in pairs(ent:GetMaterials()) do -- Fixes model materials	
		FixupModelMaterial(Material(v))
	end
end
local function FixupEntities() 

	hook.Add( "OnEntityCreated", "RTXEntityFixups", FixupEntity)
	for k, v in pairs(ents.GetAll()) do
		FixupEntity(v)
	end

end

local function RTXLoadPropHashFixer()
    FixupEntities()
end
hook.Add( "InitPostEntity", "RTXReady_PropHashFixer", RTXLoadPropHashFixer)  