#include "GarrysMod/Lua/Interface.h" 
#include "e_utils.h"  
#include "iclientrenderable.h"
#include "materialsystem/imaterialsystem.h"
#include "materialsystem/materialsystem_config.h"
#include "interfaces/interfaces.h"  
#include "prop_fixes.h"  
#include <memory_patcher.h>

using namespace GarrysMod::Lua;

Define_method_Hook(IMaterial*, R_StudioSetupSkinAndLighting, void*, IMatRenderContext* pRenderContext, int index, IMaterial** ppMaterials, int materialFlags,
	IClientRenderable* pClientRenderable, void* pColorMeshes, void* lighting)
{ 
	//IMaterial* pMaterial = ppMaterials[index];
	IMaterial* pMaterial = R_StudioSetupSkinAndLighting_trampoline()(_this, pRenderContext, index, ppMaterials, materialFlags, pClientRenderable, pColorMeshes, lighting);
	lighting = 0; // LIGHTING_HARDWARE 
	pColorMeshes = new ColorMeshInfo_t();
	return pMaterial;
}

static StudioRenderConfig_t s_StudioRenderConfig;
 
void ModelRenderHooks::Initialize() {
	try { 
		Msg("[RTX Remix Fixes 2 - Binary Module] - Loading studiorender\n");
		if (!Sys_LoadInterface("studiorender", STUDIO_RENDER_INTERFACE_VERSION, NULL, (void**)&g_pStudioRender))
			Warning("[RTX Remix Fixes 2] - Could not load studiorender interface");


		auto studiorenderdll = GetModuleHandle("studiorender.dll");
		if (!studiorenderdll) { Msg("studiorender.dll == NULL\n"); }

		static const char R_StudioSetupSkinAndLighting_sign[] = "48 89 54 24 10 48 89 4C 24 08 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 50 48 8B 41 08 45 32 F6 49 63 F0 4D 8B E1 4C 8B EA 4C 8B F9 0F B6 A8 58 02 00 00 48 8B B8 50 02 00 00 40 88 AC 24 A0 00 00 00 83 FE 1F 77 20 4C 8B 84 F0 60 02 00 00 4D 85 C0 74 13 0F B6";
		auto R_StudioSetupSkinAndLighting = ScanSign(studiorenderdll, R_StudioSetupSkinAndLighting_sign, sizeof(R_StudioSetupSkinAndLighting_sign) - 1);

		if (!R_StudioSetupSkinAndLighting) { Msg("R_StudioSetupSkinAndLighting == NULL\n"); return; }

		Setup_Hook(R_StudioSetupSkinAndLighting, R_StudioSetupSkinAndLighting)

		//MaterialSystem_Config_t cfg = materials->GetCurrentConfigForVideoCard();
		//cfg.bSoftwareLighting = false;
		//materials->OverrideConfig(cfg, true);

		g_pStudioRender->GetCurrentConfig(s_StudioRenderConfig);
		s_StudioRenderConfig.bSoftwareSkin = false;
		s_StudioRenderConfig.bSoftwareLighting = false;
		
		s_StudioRenderConfig.bDrawNormals = false;
		s_StudioRenderConfig.bDrawTangentFrame = false;
		s_StudioRenderConfig.bFlex = false;
		g_pStudioRender->UpdateConfig(s_StudioRenderConfig);  

		HMODULE studiorenderModule = GetModuleHandleEx("studiorender.dll");

		// hardware skin patch 1, override pColorMeshes 
		// can fatally crash, disabled
		
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceHardwareSkinning1",
		//	studiorenderModule,
		//	"75 ?? 48 8B 41 ?? F6 40",
		//	"90",
		//	"Force models to use Hardware Skinning (1/2)"
		//);

		// hardware skin patch 2, overrides the first jnz to jump after pColorMeshes is checked
		g_MemoryPatcher.FindAndPatch(
			"ForceHardwareSkinning2",
			studiorenderModule,
			"75 ?? F6 40 ?? ?? 75",
			"EB",
			"Force models to use Hardware Skinning (2/2)"
		);

		g_MemoryPatcher.FindAndPatch(
			"ForceStaticModel1",
			studiorenderModule,
			"75 ?? 84 C0 75",
			"90",
			"Force models to use static meshes (1/2)"
		);

		//g_MemoryPatcher.FindAndPatch(
		//	"ForceStaticModel2",
		//	studiorenderModule,
		//	"75 ?? 8B 85 ?? ?? ?? ?? 33 F6",
		//	"90",
		//	"Force models to use static meshes (2/2)"
		//);

	}
	catch (...) {
		Msg("[Prop Fixes] Exception in ModelRenderHooks::Initialize\n");
	}
}

void ModelRenderHooks::Shutdown() { 
	// Existing shutdown code  
	R_StudioSetupSkinAndLighting_hook.Disable();
	g_MemoryPatcher.DisablePatch("ForceHardwareSkinning2");
	g_MemoryPatcher.DisablePatch("ForceStaticModel1");

	// Log shutdown completion
	Msg("[Prop Fixes] Shutdown complete\n");
}
