#include "GarrysMod/Lua/Interface.h" 
#include "e_utils.h"  
#include "iclientrenderable.h"
#include "materialsystem/imaterialsystem.h"
#include "materialsystem/materialsystem_config.h"
#include "interfaces/interfaces.h"  
#include "prop_fixes.h"
#include <memory_patcher.h>
#include <globalconvars.h>
#include "icliententity.h" // Add this include to resolve the incomplete type error
#include <c_baseanimating.h>
#include "engine/ivmodelinfo.h"

using namespace GarrysMod::Lua;

IVModelInfo* pModelInfo = nullptr;
static StudioRenderConfig_t s_StudioRenderConfig;

Define_method_Hook(IMaterial*, R_StudioSetupSkinAndLighting, void*, IMatRenderContext* pRenderContext, int index, IMaterial** ppMaterials, int materialFlags,
	IClientRenderable* pClientRenderable, void* pColorMeshes, int &lighting)
{ 
	//IMaterial* pMaterial = ppMaterials[index];
	IMaterial* pMaterial = R_StudioSetupSkinAndLighting_trampoline()(_this, pRenderContext, index, ppMaterials, materialFlags, pClientRenderable, pColorMeshes, lighting);

#ifdef _WIN64
	if (GlobalConvars::r_forcehwlight && GlobalConvars::r_forcehwlight->GetBool()) {
		lighting = 0; // LIGHTING_HARDWARE 
	}
#endif
	// only force LIGHTING_HARDWARE to anything that isn't a ragdoll or has flexes
	auto mdl = pClientRenderable->GetModel();
	if(!mdl) mdl = pClientRenderable->GetIClientUnknown()->GetBaseEntity()->GetModel();
	auto pStudioHdr = pModelInfo->GetStudiomodel(mdl);
	//Msg("[Prop Fixes] numflexrules is %d\n", pStudioHdr->numflexrules);
	//Msg("[Prop Fixes] numflexdesc is %d\n", pStudioHdr->numflexdesc);
	//Msg("[Prop Fixes] numflexcontrollers is %d\n", pStudioHdr->numflexcontrollers);
	//Msg("[Prop Fixes] numbodyparts is %d\n", pStudioHdr->numbodyparts);
	//Msg("[Prop Fixes] numbones is %d\n", pStudioHdr->numbones);
	if (pStudioHdr && !(pStudioHdr->numbones > 1)) {
		lighting = 0; // LIGHTING_HARDWARE 
	}

	return pMaterial;
}

Define_method_Hook(int*, R_StudioDrawDynamicMesh, void*, IMatRenderContext* pRenderContext, mstudiomesh_t* pmesh,
	studiomeshgroup_t* pGroup, int lighting,
	float r_blend, IMaterial* pMaterial, int lod)
{ 
	//IMaterial* pMaterial = ppMaterials[index];
	//lighting = 0; // LIGHTING_HARDWARE 
	//pColorMeshes = new ColorMeshInfo_t();
	auto returncode = R_StudioDrawDynamicMesh_trampoline()(_this, pRenderContext, pmesh, pGroup, lighting, r_blend, pMaterial, lod);
	return returncode;
}
 
void ModelRenderHooks::Initialize() {
	try { 

		// config stuff
		//Sys_LoadInterface CRASHES for some reason on win32?????
#ifdef _WIN32
		Msg("[RTX Remix Fixes 2 - Binary Module] - Loading studiorender\n");

		HMODULE studiorenderLib = LoadLibraryA("studiorender.dll");
		if (!studiorenderLib) {
			Warning("[RTX Remix Fixes 2] - Failed to load studiorender.dll: error code %d\n", GetLastError());
			return;
		}

		using CreateInterfaceFn = void* (*)(const char* pName, int* pReturnCode);
		CreateInterfaceFn createInterface = (CreateInterfaceFn)GetProcAddress(studiorenderLib, "CreateInterface");
		if (!createInterface) {
			Warning("[RTX Remix Fixes 2] - Could not get CreateInterface from studiorender.dll\n");
			return;
		}
		g_pStudioRender = (IStudioRender*)createInterface(STUDIO_RENDER_INTERFACE_VERSION, nullptr);

		HMODULE engineLib = LoadLibraryA("engine.dll");
		if (!engineLib) {
			Warning("[RTX Remix Fixes 2] - Failed to load engine.dll: error code %d\n", GetLastError());
			return;
		}

		CreateInterfaceFn createEngineInterface = (CreateInterfaceFn)GetProcAddress(engineLib, "CreateInterface");
		if (!createEngineInterface) {
			Warning("[RTX Remix Fixes 2] - Could not get CreateInterface from engine.dll\n");
			return;
		}
		pModelInfo = (IVModelInfo*)createEngineInterface(VMODELINFO_CLIENT_INTERFACE_VERSION, nullptr);
		if (!pModelInfo) {
			Warning("[RTX Remix Fixes 2] - Could not get IVModelInfo interface\n");
			return;
		}
#else
		Msg("[RTX Remix Fixes 2 - Binary Module] - Loading studiorender\n");
		if (!Sys_LoadInterface("studiorender", STUDIO_RENDER_INTERFACE_VERSION, NULL, (void**)&g_pStudioRender))
			Warning("[RTX Remix Fixes 2] - Could not load studiorender interface");

		if (!Sys_LoadInterface("engine", VMODELINFO_CLIENT_INTERFACE_VERSION, NULL, (void**)&pModelInfo))
			Warning("[RTX Remix Fixes 2] - Could not load IVModelInfo interface");
#endif

#ifdef _WIN32
		// Use direct vtable call to avoid calling convention issues
		typedef void(__thiscall* GetConfigFn)(void*, StudioRenderConfig_t&);
		void** vtable = *reinterpret_cast<void***>(g_pStudioRender);
		GetConfigFn GetConfig = reinterpret_cast<GetConfigFn>(vtable[9]); // GetCurrentConfig at index 9
		GetConfig(g_pStudioRender, s_StudioRenderConfig);

		s_StudioRenderConfig.bSoftwareSkin = false;
		s_StudioRenderConfig.bSoftwareLighting = false;
		s_StudioRenderConfig.bDrawNormals = false;
		s_StudioRenderConfig.bDrawTangentFrame = false;
		//s_StudioRenderConfig.bFlex = false;

		// Similarly for UpdateConfig
		typedef void(__thiscall* UpdateConfigFn)(void*, const StudioRenderConfig_t&);
		UpdateConfigFn UpdateConfig = reinterpret_cast<UpdateConfigFn>(vtable[8]); // UpdateConfig at index 8
		UpdateConfig(g_pStudioRender, s_StudioRenderConfig);
#else
		// 64-bit code remains unchanged
		g_pStudioRender->GetCurrentConfig(s_StudioRenderConfig);
		s_StudioRenderConfig.bSoftwareSkin = false;
		s_StudioRenderConfig.bSoftwareLighting = false;
		s_StudioRenderConfig.bDrawNormals = false;
		s_StudioRenderConfig.bDrawTangentFrame = false;
		//s_StudioRenderConfig.bFlex = false;
		g_pStudioRender->UpdateConfig(s_StudioRenderConfig);
#endif

		// end config stuff


		auto studiorenderdll = GetModuleHandle("studiorender.dll");
		if (!studiorenderdll) { Msg("studiorender.dll == NULL\n"); }

#ifdef _WIN64
		static const char R_StudioSetupSkinAndLighting_sign[] = "48 89 54 24 10 48 89 4C 24 08 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 50 48 8B 41 08 45 32 F6 49 63 F0 4D 8B E1 4C 8B EA 4C 8B F9 0F B6 A8 58 02 00 00 48 8B B8 50 02 00 00 40 88 AC 24 A0 00 00 00 83 FE 1F 77 20 4C 8B 84 F0 60 02 00 00 4D 85 C0 74 13 0F B6";
#else
		static const char R_StudioSetupSkinAndLighting_sign[] = "55 8B EC 83 EC 18 8B C1";
#endif
#ifdef _WIN64
		static const char R_StudioDrawDynamicMesh_sign[] = "40 55 53 57 41 54 41 55 41 56 41 57";
#else
		static const char R_StudioDrawDynamicMesh_sign[] = "55 8B EC 81 EC F8 01 00 00";
#endif
#ifdef _WIN64
		static const char R_StudioDrawStaticMesh_sign[] = "40 55 53 56 57 41 54 41 55 41 56 41 57 48 8D AC 24";
#else
		static const char R_StudioDrawStaticMesh_sign[] = "55 8B EC 81 EC EC 01 00 00 83 7D";
#endif
		auto R_StudioSetupSkinAndLighting = ScanSign(studiorenderdll, R_StudioSetupSkinAndLighting_sign, sizeof(R_StudioSetupSkinAndLighting_sign) - 1);
		auto R_StudioDrawDynamicMesh = ScanSign(studiorenderdll, R_StudioDrawDynamicMesh_sign, sizeof(R_StudioDrawDynamicMesh_sign) - 1);

		if (!R_StudioSetupSkinAndLighting) { Msg("R_StudioSetupSkinAndLighting == NULL\n"); return; }
		if (!R_StudioDrawDynamicMesh) { Msg("R_StudioDrawDynamicMesh == NULL\n"); return; }

		Setup_Hook(R_StudioSetupSkinAndLighting, R_StudioSetupSkinAndLighting)
		Setup_Hook(R_StudioDrawDynamicMesh, R_StudioDrawDynamicMesh)

		//MaterialSystem_Config_t cfg = materials->GetCurrentConfigForVideoCard();
		//cfg.bSoftwareLighting = false;
		//materials->OverrideConfig(cfg, true);

		HMODULE studiorenderModule = GetModuleHandleEx("studiorender.dll");

		// hardware skin patch 1, override pColorMeshes 
		// can fatally crash, disabled

#ifdef _WIN64
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceHardwareSkinning1",
		//	studiorenderModule,
		//	"75 ?? 48 8B 41 ?? F6 40",
		//	"90",
		//	"Force models to use Hardware Skinning (1/2)"
		//);
#else
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceHardwareSkinning1",
		//	studiorenderModule,
		//	"75 ?? 8B 46 ?? F6 40",
		//	"90",
		//	"Force models to use Hardware Skinning (1/2)"
		//);
#endif


#ifdef _WIN64
		// hardware skin patch 2, overrides the first jnz to jump after pColorMeshes is checked
		g_MemoryPatcher.FindAndPatch(
			"ForceHardwareSkinning2",
			studiorenderModule,
			"75 ?? F6 40 ?? ?? 75",
			"EB",
			"Force models to use Hardware Skinning (2/2)"
		);
#endif

#ifdef _WIN64
		g_MemoryPatcher.FindAndPatch(
			"ForceStaticModel1",
			studiorenderModule,
			"75 ?? 84 C0 75",
			"90",
			"Force models to use static meshes (1/2)"
		);
#else
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceStaticModel1",
		//	studiorenderModule,
		//	"75 ?? 84 C9 75 ?? D9 45",
		//	"90",
		//	"Force models to use static meshes (1/2)"
		//);
#endif

#ifdef _WIN64
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceStaticModel2",
		//	studiorenderModule,
		//	"75 ?? 8B 85 ?? ?? ?? ?? 33 F6",
		//	"90",
		//	"Force models to use static meshes (2/2)"
		//);
#else
		//g_MemoryPatcher.FindAndPatch(
		//	"ForceStaticModel2",
		//	studiorenderModule,
		//	"75 ?? D9 45 ?? 6A 00",
		//	"90",
		//	"Force models to use static meshes (2/2)"
		//);
#endif

	}
	catch (...) {
		Msg("[Prop Fixes] Exception in ModelRenderHooks::Initialize\n");
	}
}

void ModelRenderHooks::Shutdown() { 
	// Existing shutdown code  
	R_StudioSetupSkinAndLighting_hook.Disable();
	R_StudioDrawDynamicMesh_hook.Disable();
#ifdef _WIN64
	g_MemoryPatcher.DisablePatch("ForceHardwareSkinning2");
	g_MemoryPatcher.DisablePatch("ForceStaticModel1");
#endif

	// Log shutdown completion
	Msg("[Prop Fixes] Shutdown complete\n");
}
