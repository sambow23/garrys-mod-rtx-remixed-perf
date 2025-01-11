if not CLIENT then return end
CreateClientConVar(	"rtx_disablevertexlighting", 0,  true, false) 


local function FixupModelMaterial(mat)
	--print("[RTX Fixes] - Found and fixing model material in " .. filepath)
	-- print(mat:GetInt("$flags"))
	-- mat:SetShader("VertexLitGeneric")
	-- -- Remove all other parameters
	-- local paramsToRemove = {
	-- 	"$bumpmap", "$normalmap", "$envmap", "$reflectivity", 
	-- 	"$refracttexture", "$refracttint", "$refractamount",
	-- 	"$fresnelreflection", "$bottommaterial", "$underwateroverlay",
	-- 	"$dudvmap", "$fogcolor", "$fogstart", "$fogend",
	-- 	"$phong", "$envmap", "$normalmapalphaenvmapmask"
	-- }
	
	-- for _, param in ipairs(paramsToRemove) do
	-- 	mat:SetUndefined(param)
	-- end 

	-- mat:SetInt( "$flags", 0 ) 
	--mat:SetInt( "$flags2", bit.bor(mat:GetInt("$flags2"), 2048))
	mat:SetInt( "$flags2", bit.band(mat:GetInt("$flags2"), bit.bnot(512))) 
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