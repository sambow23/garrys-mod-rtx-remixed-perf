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

using namespace GarrysMod::Lua;

Define_method_Hook(void*, CViewRenderRender, void*, vrect_t* rect)
{
	view->DisableVis();
	CViewRender::GetMainView()->DisableVis();
	CViewRenderRender_trampoline()(_this, rect); 
	return nullptr;
}

static StudioRenderConfig_t s_StudioRenderConfig;
 
void CullingHooks::Initialize() {
	try {  
		auto enginedll = GetModuleHandle("engine.dll");
		if (!enginedll) { Msg("engine.dll == NULL\n"); }

		static const char sign[] = "4C 8B DC 55 49 8D AB ?? ?? ?? ?? 48 81 EC 40 02 00 00";
		auto CViewRenderRender = ScanSign(enginedll, sign, sizeof(sign) - 1);

		if (!CViewRenderRender) { Msg("CViewRender::Render == NULL\n"); return; }

		Setup_Hook(CViewRenderRender, CViewRenderRender)
			 
	}
	catch (...) {
		Msg("[Culling Fixes] Exception in CullingHooks::Initialize\n");
	}
}

void CullingHooks::Shutdown() {
	// Existing shutdown code  
	CViewRenderRender_hook.Disable();

	// Log shutdown completion
	Msg("[Culling Fixes] Shutdown complete\n");
}
