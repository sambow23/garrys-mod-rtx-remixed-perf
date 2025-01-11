 
#include "convar.h"
#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/Lua/LuaShared.h>
#include <GarrysMod/Lua/LuaConVars.h>
#include "globalconvars.h"

static SourceSDK::FactoryLoader loader_lua_shared("lua_shared");
static GarrysMod::Lua::ILuaShared* lua_shared = nullptr;
static GarrysMod::Lua::ILuaConVars* m_pLuaConVars;
 
ConVar* GlobalConvars::r_forcenovis;
ConVar* GlobalConvars::c_frustumcull;
void GlobalConvars::InitialiseConVars() {
	m_pLuaConVars = loader_lua_shared.GetInterface<GarrysMod::Lua::ILuaConVars>(GMOD_LUACONVARS_INTERFACE);
	if (!m_pLuaConVars) {
		Error("[RTX Fixes 2] Failed to get ILuaConVars interface\n");
		return;
	}

	r_forcenovis = m_pLuaConVars->CreateConVar("r_forcenovis", "1", "Force disable vis", FCVAR_ARCHIVE);
	if (!r_forcenovis) { r_forcenovis = cvar->FindVar("r_forcenovis"); }
	if (!r_forcenovis) { Error("[RTX Fixes 2] Failed to create r_forcenovis convar\n"); }
	else { Msg("[RTX Fixes 2] r_forcenovis convar created\n"); }


	c_frustumcull = m_pLuaConVars->CreateConVar("c_frustumcull", "0", "Force frustum culling", FCVAR_ARCHIVE);
	if (!c_frustumcull) { c_frustumcull = cvar->FindVar("c_frustumcull"); }
	if (!c_frustumcull) { Error("[RTX Fixes 2] Failed to create c_frustumcull convar\n"); }
	else { Msg("[RTX Fixes 2] c_frustumcull convar created\n"); }
}