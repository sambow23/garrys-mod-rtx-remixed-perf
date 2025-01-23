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

Define_method_Hook(bool, MathLibR_CullBoxSkipNear_ENGINE, void*, const Vector& mins, const Vector& maxs, const Frustum_t& frustum)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return MathLibR_CullBoxSkipNear_ENGINE_trampoline()(_this, mins, maxs, frustum);
	}
	return false;
}

Define_method_Hook(bool, MathLibR_CullBox_ENGINE, void*, const Vector& mins, const Vector& maxs, const Frustum_t& frustum)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return MathLibR_CullBox_ENGINE_trampoline()(_this, mins, maxs, frustum);
	}
	return false; 
}

Define_method_Hook(bool, MathLibR_CullBox_CLIENT, void*, const Vector& mins, const Vector& maxs, const Frustum_t& frustum)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return MathLibR_CullBox_CLIENT_trampoline()(_this, mins, maxs, frustum);
	}
	return false;
}



//Define_method_Hook(bool, EngineR_BuildWorldLists, void*, void* pRenderListIn, WorldListInfo_t* pInfo, int iForceViewLeaf, const VisOverrideData_t* pVisData, bool bShadowDepth /* = false */, float* pWaterReflectionHeight)
//{
//	return EngineR_BuildWorldLists_trampoline()(_this, pRenderListIn, pInfo, iForceViewLeaf, pVisData, true, pWaterReflectionHeight);
//}

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

		static const char R_CullBox_sign[] = "48 83 EC 48 0F 10 22 33 C0";

		//R_CullBoxSkipNear doesn't exist on chromium/x86-64, see https://commits.facepunch.com/202379
		//static const char R_CullBoxSkipNear_sign[] = "48 83 EC 48 0F 10 22 33 C0"; 

		auto CLIENT_R_CullBox = ScanSign(client, R_CullBox_sign, sizeof(R_CullBox_sign) - 1);
		auto ENGINE_R_CullBox = ScanSign(engine, R_CullBox_sign, sizeof(R_CullBox_sign) - 1);
		if (!CLIENT_R_CullBox) { Msg("[Culling Fixes] MathLib (CLIENT) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (CLIENT) R_CullBox\n"); Setup_Hook(MathLibR_CullBox_CLIENT, CLIENT_R_CullBox) }

		if (!ENGINE_R_CullBox) { Msg("[Culling Fixes] MathLib (ENGINE) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (ENGINE) R_CullBox\n"); Setup_Hook(MathLibR_CullBox_ENGINE, ENGINE_R_CullBox) }

		//static const char sign_RBuildWorldLists[] = "40 53 55 56 57 41 54 41 57 48 83 EC 78";
		//static const char sign_RRecursiveWorldNodeNoCull[] = "48 89 5C 24 ? 55 48 83 EC 40 48 8B DA 48 8B E9 8B 12";
		//static const char sign_RRecursiveWorldNode[] = "48 8B C4 56 41 55";

		//auto pointer_RBuildWorldLists = ScanSign(engine, sign_RBuildWorldLists, sizeof(sign_RBuildWorldLists) - 1);
		//auto pointer_RRecursiveWorldNodeNoCull = ScanSign(engine, sign_RRecursiveWorldNodeNoCull, sizeof(sign_RRecursiveWorldNodeNoCull) - 1);
		//auto pointer_RRecursiveWorldNode = ScanSign(engine, sign_RRecursiveWorldNode, sizeof(sign_RRecursiveWorldNode) - 1);


		//if (!pointer_RBuildWorldLists) { Msg("[Culling Fixes] MathLib engine R_BuildWorldLists == NULL\n"); }
		//else { Msg("[Culling Fixes] Hooked engine R_BuildWorldLists\n"); Setup_Hook(EngineR_BuildWorldLists, pointer_RBuildWorldLists) }

	}
	catch (...) {
		Msg("[Culling Fixes] Exception in CullingHooks::Initialize\n");
	}
}

void CullingHooks::Shutdown() {
	// Existing shutdown code  
	//CViewRenderRender_hook.Disable();
	CViewRenderShouldForceNoVis_hook.Disable();
	MathLibR_CullBox_ENGINE_hook.Disable();
	MathLibR_CullBox_CLIENT_hook.Disable();
	//EngineR_BuildWorldLists_hook.Disable();

	// Log shutdown completion
	Msg("[Culling Fixes] Shutdown complete\n");
}
