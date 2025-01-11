#include "GarrysMod/Lua/Interface.h"
#include "e_utils.h"  
#include "iclientrenderable.h"
#include "materialsystem/imaterialsystem.h"
#include "materialsystem/materialsystem_config.h"
#include "interfaces/interfaces.h"  
#include "culling_fixes.h"  
#include "cdll_client_int.h"
#include "view.h"
#include "cbase.h"
#include "viewrender.h"
#include "globalconvars.h"

using namespace GarrysMod::Lua; 

Define_method_Hook(void, CViewRenderRender, CViewRender*, vrect_t* rect)
{
	// crashma
	//view->DisableVis();
	//CViewRender::GetMainView()->DisableVis();
	CViewRenderRender_trampoline()(_this, rect); 
	return;
}

Define_method_Hook(bool, CViewRenderShouldForceNoVis, void*)
{   
	bool original = CViewRenderShouldForceNoVis_trampoline()(_this);
	if (GlobalConvars::r_forcenovis && GlobalConvars::r_forcenovis->GetBool()) {
		//Msg("[Culling Fixes] Hi\n");
		return true;
	}
	return original;
}

Define_method_Hook(bool, MathLibR_CullBox, void*, const Vector& mins, const Vector& maxs, const Frustum_t& frustum)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return MathLibR_CullBox_trampoline()(_this, mins, maxs, frustum); 
	}
	return false; 
}

static StudioRenderConfig_t s_StudioRenderConfig;
 
void CullingHooks::Initialize() {
	try {
		auto client = GetModuleHandle("client.dll");
		auto engine = GetModuleHandle("engine.dll");
		if (!client) { Msg("client.dll == NULL\n"); }
		if (!engine) { Msg("engine.dll == NULL\n"); }

		//static const char sign1[] = "44 8B B1 ? ? ? ? 48 89 55";
		//auto CViewRenderRender = ScanSign(client, sign1, sizeof(sign1) - 1);
		//if (!CViewRenderRender) { Msg("[Culling Fixes] CViewRender::Render == NULL\n"); }
		//else {
		//	Msg("[Culling Fixes] Hooked CViewRender::Render\n");
		//	Setup_Hook(CViewRenderRender, CViewRenderRender)
		//}

		// I cant find the signature, here's some possibilities??????????
		// 8B 81 ?? ?? ?? ?? C3 CC CC CC CC CC CC CC CC CC 8B 81 ?? ?? ?? ?? C3 CC CC CC CC CC CC CC CC CC 85 D2 75
		// 0F B6 81 ?? ?? ?? ?? C3 CC CC CC CC CC CC CC CC 8B 81 ?? ?? ?? ?? C3 CC CC CC CC CC CC CC CC CC 48 8B 81
		// 48 8D 81 4C 03 00 00 C3
		// 0F B6 81 54 03 00 00 C3
		// EDIT: its the 2nd/4th one, 2nd doesn't work, 4th works but will change with updates :(

		static const char sign2[] = "0F B6 81 54 03 00 00 C3";
		auto CViewRenderShouldForceNoVis = ScanSign(client, sign2, sizeof(sign2) - 1);
		if (!CViewRenderShouldForceNoVis) { Msg("[Culling Fixes] CViewRender::ShouldForceNoVis == NULL\n"); }
		else {
			Msg("[Culling Fixes] Hooked CViewRender::ShouldForceNoVis\n");
			Setup_Hook(CViewRenderShouldForceNoVis, CViewRenderShouldForceNoVis)
		}

		static const char sign3[] = "48 83 EC 48 0F 10 22";
		auto CLIENT_R_CullBox = ScanSign(client, sign3, sizeof(sign3) - 1);
		auto ENGINE_R_CullBox = ScanSign(engine, sign3, sizeof(sign3) - 1);
		if (!CLIENT_R_CullBox) { Msg("[Culling Fixes] MathLib (CLIENT) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (CLIENT) R_CullBox\n"); Setup_Hook(MathLibR_CullBox, CLIENT_R_CullBox) }

		if (!ENGINE_R_CullBox) { Msg("[Culling Fixes] MathLib (ENGINE) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (ENGINE) R_CullBox\n"); Setup_Hook(MathLibR_CullBox, ENGINE_R_CullBox) }
	}
	catch (...) {
		Msg("[Culling Fixes] Exception in CullingHooks::Initialize\n");
	}
}

void CullingHooks::Shutdown() {
	// Existing shutdown code  
	//CViewRenderRender_hook.Disable();
	CViewRenderShouldForceNoVis_hook.Disable();
	MathLibR_CullBox_hook.Disable();

	// Log shutdown completion
	Msg("[Culling Fixes] Shutdown complete\n");
}
