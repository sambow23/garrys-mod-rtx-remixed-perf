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

#include <Windows.h>
#include <vector>
#include <string>
#include <unordered_map>
#include <Psapi.h>

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

Define_method_Hook(bool, MathLibR_CullBoxSkipNear_CLIENT, void*, const Vector& mins, const Vector& maxs, const Frustum_t& frustum)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return MathLibR_CullBoxSkipNear_CLIENT_trampoline()(_this, mins, maxs, frustum);
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

Define_method_Hook(bool, CM_BoxVisible_ENGINE, void*, const Vector& mins, const Vector& maxs, const byte* visbits, int vissize)
{
	if (GlobalConvars::c_frustumcull && GlobalConvars::c_frustumcull->GetBool()) {
		return CM_BoxVisible_ENGINE_trampoline()(_this, mins, maxs, visbits, vissize);
	}
	return true;
}



//Define_method_Hook(bool, EngineR_BuildWorldLists, void*, void* pRenderListIn, WorldListInfo_t* pInfo, int iForceViewLeaf, const VisOverrideData_t* pVisData, bool bShadowDepth /* = false */, float* pWaterReflectionHeight)
//{
//	return EngineR_BuildWorldLists_trampoline()(_this, pRenderListIn, pInfo, iForceViewLeaf, pVisData, true, pWaterReflectionHeight);
//}


// Structure for a byte pattern and its patch
struct BytePatch {
    std::string pattern;           // Pattern to find (hex string)
    size_t offset;                 // Offset from pattern start
    std::string replacement;       // Bytes to write (hex string)
    bool applied;                  // Whether patch has been applied
    void* address;                 // Where the patch was applied
    std::vector<uint8_t> original; // Original bytes that were overwritten
};

// Convert hex string to bytes
std::vector<uint8_t> HexToBytes(const std::string& hex) {
	std::vector<uint8_t> bytes;
	for (size_t i = 0; i < hex.length(); i += 2) {
		std::string byteString = hex.substr(i, 2);
		uint8_t byte = (uint8_t)strtol(byteString.c_str(), NULL, 16);
		bytes.push_back(byte);
	}
	return bytes;
}

// Improved pattern matching function that handles wildcards like the Python script
bool FindPattern(const uint8_t* data, size_t dataSize, const std::string& hexPattern, size_t& outPosition) {
    // Handle wildcards by splitting the pattern at "??" markers
    std::vector<std::string> parts;
    size_t start = 0;
    size_t pos;

    // Split the pattern by "??" wildcards
    while ((pos = hexPattern.find("??", start)) != std::string::npos) {
        if (pos > start) {
            parts.push_back(hexPattern.substr(start, pos - start));
        }
        else {
            parts.push_back("");
        }
        start = pos + 2;
    }

    // Add the last part if any
    if (start < hexPattern.length()) {
        parts.push_back(hexPattern.substr(start));
    }

    // If no wildcards, do a simple search
    if (parts.size() == 1) {
        std::vector<uint8_t> patternBytes = HexToBytes(hexPattern);
        for (size_t i = 0; i <= dataSize - patternBytes.size(); i++) {
            bool match = true;
            for (size_t j = 0; j < patternBytes.size(); j++) {
                if (data[i + j] != patternBytes[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                outPosition = i;
                return true;
            }
        }
        return false;
    }

    // With wildcards, we need the more complex search
    size_t searchPos = 0;
    while (searchPos < dataSize) {
        // Find the first part
        std::vector<uint8_t> firstPart = HexToBytes(parts[0]);
        bool found = false;
        size_t firstPartPos = 0;

        for (size_t i = searchPos; i <= dataSize - firstPart.size(); i++) {
            bool match = true;
            for (size_t j = 0; j < firstPart.size(); j++) {
                if (data[i + j] != firstPart[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                found = true;
                firstPartPos = i;
                break;
            }
        }

        if (!found) {
            return false;
        }

        // Check if the rest of the parts match
        bool allMatch = true;
        size_t checkPos = firstPartPos;

        for (size_t i = 0; i < parts.size(); i++) {
            if (!parts[i].empty()) {
                std::vector<uint8_t> partBytes = HexToBytes(parts[i]);
                checkPos += (i > 0) ? 1 : 0; // Skip the wildcard byte

                if (checkPos + partBytes.size() > dataSize) {
                    allMatch = false;
                    break;
                }

                for (size_t j = 0; j < partBytes.size(); j++) {
                    if (data[checkPos + j] != partBytes[j]) {
                        allMatch = false;
                        break;
                    }
                }

                if (!allMatch) {
                    break;
                }

                checkPos += partBytes.size();
            }
            else {
                checkPos += 1; // Just skip the wildcard
            }
        }

        if (allMatch) {
            outPosition = firstPartPos;
            return true;
        }

        // Continue searching from the next byte
        searchPos = firstPartPos + 1;
    }

    return false;
}

// Apply a patch to memory with wildcard support
bool ApplyPatch(HMODULE moduleHandle, BytePatch& patch) {
    if (patch.applied) return true; // Already applied

    // Convert replacement to byte array
    std::vector<uint8_t> replacementBytes = HexToBytes(patch.replacement);

    // Get module info to determine its size
    MODULEINFO moduleInfo;
    if (!GetModuleInformation(GetCurrentProcess(), moduleHandle, &moduleInfo, sizeof(moduleInfo))) {
        Msg("[Culling Fixes] Failed to get module info\n");
        return false;
    }

    // Find the pattern in memory
    uint8_t* baseAddr = (uint8_t*)moduleHandle;
    size_t patternPos = 0;

    if (FindPattern(baseAddr, moduleInfo.SizeOfImage, patch.pattern, patternPos)) {
        // Found the pattern, apply the patch
        uint8_t* patchAddr = baseAddr + patternPos + patch.offset;

        DWORD oldProtect;
        if (VirtualProtect(patchAddr, replacementBytes.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
            // Store the original bytes for later restoration
            patch.original.resize(replacementBytes.size());
            memcpy(patch.original.data(), patchAddr, replacementBytes.size());

            // Log the original bytes for debug
            std::string originalHex;
            for (size_t i = 0; i < replacementBytes.size(); i++) {
                char hex[3];
                sprintf(hex, "%02x", patchAddr[i]);
                originalHex += hex;
            }

            Msg("[Culling Fixes] At %p: Changing `%s` to `%s`\n", patchAddr, originalHex.c_str(), patch.replacement.c_str());

            // Apply the patch
            memcpy(patchAddr, replacementBytes.data(), replacementBytes.size());
            VirtualProtect(patchAddr, replacementBytes.size(), oldProtect, &oldProtect);
            patch.applied = true;
            patch.address = patchAddr;
            return true;
        }
        else {
            Msg("[Culling Fixes] Failed to change memory protection\n");
            return false;
        }
    }

    // Debug code for when pattern isn't found (same as before)
    Msg("[Culling Fixes] Failed to find pattern '%s'\n", patch.pattern.c_str());
    return false;
}

// Restore original bytes
bool RestorePatch(BytePatch& patch) {
    if (!patch.applied || !patch.address || patch.original.empty()) {
        return false;
    }

    DWORD oldProtect;
    if (VirtualProtect(patch.address, patch.original.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
        // Restore original bytes
        memcpy(patch.address, patch.original.data(), patch.original.size());
        VirtualProtect(patch.address, patch.original.size(), oldProtect, &oldProtect);
        patch.applied = false;
        Msg("[Culling Fixes] Restored original bytes at %p\n", patch.address);
        return true;
    }
    else {
        Msg("[Culling Fixes] Failed to restore original bytes at %p\n", patch.address);
        return false;
    }
}

// Global storage for applied patches
std::vector<BytePatch> g_AppliedPatches;

// Enhanced function to apply patches that stores them for later restoration
void ApplyPatches(const char* dllName, const std::vector<BytePatch>& patches) {
    HMODULE moduleHandle = GetModuleHandleA(dllName);
    if (!moduleHandle) {
        Msg("[Culling Fixes] Failed to get handle for %s\n", dllName);
        return;
    }

    Msg("[Culling Fixes] Applying patches to %s\n", dllName);

    for (auto& patch : patches) {
        BytePatch patchCopy = patch; // Create a copy we can modify
        if (ApplyPatch(moduleHandle, patchCopy)) {
            Msg("[Culling Fixes] Successfully applied patch to %s\n", dllName);
            // Store the successfully applied patch for later restoration
            g_AppliedPatches.push_back(patchCopy);
        }
        else {
            Msg("[Culling Fixes] Failed to apply patch to %s\n", dllName);
        }
    }
}
// Command to check and reapply patches
void CheckAndReapplyPatches_f() {
    Msg("[Culling Fixes] Checking patch status...\n");

    // Check if patches are still applied
    bool anyMissing = false;
    for (auto& patch : g_AppliedPatches) {
        if (!patch.applied) continue; // Skip already-unapplied patches

        // Check if bytes match our patch
        std::vector<uint8_t> replacementBytes = HexToBytes(patch.replacement);
        bool intact = true;

        for (size_t i = 0; i < replacementBytes.size(); i++) {
            if (((uint8_t*)patch.address)[i] != replacementBytes[i]) {
                intact = false;
                break;
            }
        }

        if (!intact) {
            anyMissing = true;
            Msg("[Culling Fixes] Patch at %p has been overwritten, reapplying...\n", patch.address);

            // Reapply the patch
            DWORD oldProtect;
            if (VirtualProtect(patch.address, replacementBytes.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
                memcpy(patch.address, replacementBytes.data(), replacementBytes.size());
                VirtualProtect(patch.address, replacementBytes.size(), oldProtect, &oldProtect);
                Msg("[Culling Fixes] Successfully reapplied patch\n");
            }
            else {
                Msg("[Culling Fixes] Failed to reapply patch\n");
            }
        }
    }

    if (!anyMissing) {
        Msg("[Culling Fixes] All patches are intact\n");
    }
}


// At global scope (outside of any function or class)
static ConCommand rtx_check_patches("rtx_check_patches", CheckAndReapplyPatches_f, "Check and reapply memory patches if needed", 0);

#include "GarrysMod/InterfacePointers.hpp"

static StudioRenderConfig_t s_StudioRenderConfig;
 
void CullingHooks::Initialize() {
	try {
		auto client = GetModuleHandle("client.dll");
		auto engine = GetModuleHandle("engine.dll");
		auto server = GetModuleHandle("server.dll");
		if (!client) { Msg("client.dll == NULL\n"); }
		if (!engine) { Msg("engine.dll == NULL\n"); }
		if (!server) { Msg("server.dll == NULL\n"); }

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

		static const char sign2[] = "0F B6 81 54";
		auto CViewRenderShouldForceNoVis = ScanSign(client, sign2, sizeof(sign2) - 1);
		if (!CViewRenderShouldForceNoVis) { Msg("[Culling Fixes] CViewRender::ShouldForceNoVis == NULL\n"); }
		else {
			Msg("[Culling Fixes] Hooked CViewRender::ShouldForceNoVis\n");
			Setup_Hook(CViewRenderShouldForceNoVis, CViewRenderShouldForceNoVis)
		}

		static const char R_CullBox_sign[] = "48 83 EC 48 0F 10 22 33 C0";

		static const char CM_BoxVisible_sign[] = "48 89 5C 24 ?? 48 89 6C 24 ?? 56 57 41 56 48 81 EC ?? ?? ?? ?? 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 ?? ?? ?? ?? F3 0F 10 22";

		//R_CullBoxSkipNear doesn't exist on chromium/x86-64, see https://commits.facepunch.com/202379
		//static const char R_CullBoxSkipNear_sign[] = "48 83 EC 48 0F 10 22 33 C0"; 

		auto CLIENT_R_CullBox = ScanSign(client, R_CullBox_sign, sizeof(R_CullBox_sign) - 1);
		auto ENGINE_R_CullBox = ScanSign(engine, R_CullBox_sign, sizeof(R_CullBox_sign) - 1);

		auto ENGINE_CM_BoxVisible = ScanSign(engine, CM_BoxVisible_sign, sizeof(CM_BoxVisible_sign) - 1);

		if (!CLIENT_R_CullBox) { Msg("[Culling Fixes] MathLib (CLIENT) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (CLIENT) R_CullBox\n"); Setup_Hook(MathLibR_CullBox_CLIENT, CLIENT_R_CullBox) }

		if (!ENGINE_R_CullBox) { Msg("[Culling Fixes] MathLib (ENGINE) R_CullBox == NULL\n"); }
		else { Msg("[Culling Fixes] Hooked MathLib (ENGINE) R_CullBox\n"); Setup_Hook(MathLibR_CullBox_ENGINE, ENGINE_R_CullBox) }


        // Get the ICvar interface
        g_pCVar = (ICvar*)InterfacePointers::Cvar();
        if (g_pCVar) {
			g_pCVar->RegisterConCommand(&rtx_check_patches);
        }

		//if (!ENGINE_CM_BoxVisible) { Msg("[Culling Fixes] MathLib (ENGINE) CM_BoxVisible == NULL\n"); }
		//else { Msg("[Culling Fixes] Hooked MathLib (ENGINE) CM_BoxVisible\n"); Setup_Hook(CM_BoxVisible_ENGINE, ENGINE_CM_BoxVisible) }

		//if (!SERVER_R_CullBox) { Msg("[Culling Fixes] MathLib (ENGINE) R_CullBox == NULL\n"); }
		//else { Msg("[Culling Fixes] Hooked MathLib (SERVER) R_CullBox\n"); Setup_Hook(MathLibR_CullBox_SERVER, SERVER_R_CullBox) }

		//static const char sign_RBuildWorldLists[] = "40 53 55 56 57 41 54 41 57 48 83 EC 78";
		//static const char sign_RRecursiveWorldNodeNoCull[] = "48 89 5C 24 ? 55 48 83 EC 40 48 8B DA 48 8B E9 8B 12";
		//static const char sign_RRecursiveWorldNode[] = "48 8B C4 56 41 55";

		//auto pointer_RBuildWorldLists = ScanSign(engine, sign_RBuildWorldLists, sizeof(sign_RBuildWorldLists) - 1);
		//auto pointer_RRecursiveWorldNodeNoCull = ScanSign(engine, sign_RRecursiveWorldNodeNoCull, sizeof(sign_RRecursiveWorldNodeNoCull) - 1);
		//auto pointer_RRecursiveWorldNode = ScanSign(engine, sign_RRecursiveWorldNode, sizeof(sign_RRecursiveWorldNode) - 1);


		//if (!pointer_RBuildWorldLists) { Msg("[Culling Fixes] MathLib engine R_BuildWorldLists == NULL\n"); }
		//else { Msg("[Culling Fixes] Hooked engine R_BuildWorldLists\n"); Setup_Hook(EngineR_BuildWorldLists, pointer_RBuildWorldLists) }

		// Apply binary patches
        // credit: https://github.com/BlueAmulet/SourceRTXTweaks/blob/main/applypatch.py
		std::vector<BytePatch> enginePatches = {
			{"753cf30f10", 0, "eb", false, nullptr}, // brush entity backfaces
			{"7e5244", 0, "eb", false, nullptr},     // world backfaces
			{"753c498b4204", 0, "eb", false, nullptr} // world backfaces
		}; 
        //75 3c 49 8b 42 04
        //75 3C 49 8B 42 04 F3 0F 10 15 D9  81 55 00

		std::vector<BytePatch> clientPatches = {
			{"4883ec480f1022", 0, "31c0c3", false, nullptr}, // c_frustumcull
			{"0fb68154", 0, "b001c3", false, nullptr}        // r_forcenovis [getter]
		};

		std::vector<BytePatch> shaderPatches = {
			{"480f4ec1c7", 0, "90909090", false, nullptr},  // four hardware lights
			{"4833cce8????03004881c448", 0, "85c0750466b80400", false, nullptr}, // zero sized buffer
			{"4883ec084c", 0, "31c0c3", false, nullptr}     // shader constants
		};

		std::vector<BytePatch> materialPatches = {
			{"f77c24683bc10f4fc1488b8c24300100004833cce8??bb04004881c448010000", 0,
			 "448b4424684585c0740341f7f839c80f4fc14881c448010000c3", false, nullptr} // zero sized buffer protection
		};

        // Clear any previously applied patches
        g_AppliedPatches.clear();

		ApplyPatches("engine.dll", enginePatches);
		//ApplyPatches("client.dll", clientPatches); // we do these as hooks instead.
		//ApplyPatches("shaderapidx9.dll", shaderPatches); // these don't apply properly.
		//ApplyPatches("materialsystem.dll", materialPatches); // these also don't apply properly.

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
	MathLibR_CullBoxSkipNear_ENGINE_hook.Disable();
	MathLibR_CullBoxSkipNear_CLIENT_hook.Disable();

    // Restore original bytes for all applied patches
    Msg("[Culling Fixes] Restoring %d memory patches\n", g_AppliedPatches.size());

    for (auto& patch : g_AppliedPatches) {
        RestorePatch(patch);
    }

    // Clear the list
    g_AppliedPatches.clear();
	//CM_BoxVisible_ENGINE_hook.Disable();
	//EngineR_BuildWorldLists_hook.Disable();

	// Log shutdown completion
	Msg("[Culling Fixes] Shutdown complete\n");
}
