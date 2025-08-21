//#define HWSKIN_PATCHES

#define DELAYIMP_INSECURE_WRITABLE_HOOKS
#ifdef _WIN32
#pragma comment(linker, "/DELAYLOAD:\"tier0.dll\"")
#include <Windows.h>
#include <DelayImp.h>
#endif

#include "GarrysMod/Lua/Interface.h"
#include "cdll_client_int.h"
#include "materialsystem/imaterialsystem.h"
#include <shaderapi/ishaderapi.h>
#include "e_utils.h"
#include <Windows.h>
#include <d3d9.h>

// Only include Remix API headers in 64-bit builds
#ifdef _WIN64
#include <remix/remix.h>
#include <remix/remix_c.h>
#include "remixapi/remixapi.h"
#endif // _WIN64

#ifdef GMOD_MAIN
extern IMaterialSystem* materials = NULL;
#endif

#ifdef _WIN64
// extern IShaderAPI* g_pShaderAPI = NULL;
remix::Interface* g_remix = nullptr;
IDirect3DDevice9Ex* g_d3dDevice = nullptr;
#endif

using namespace GarrysMod::Lua;


GMOD_MODULE_OPEN() { 
    try {
        Msg("[gmRTX - Binary Module] - Module loaded!\n"); 

        // Remix initialization is only available in 64-bit builds for now
#ifdef _WIN64
        // Find Source's D3D9 device
        auto sourceDevice = static_cast<IDirect3DDevice9Ex*>(FindD3D9Device());
        if (!sourceDevice) {
            LUA->ThrowError("[gmRTX - Binary Module] Failed to find D3D9 device");
            return 0;
        }
        
        // Store the device globally for RemixAPI use
        g_d3dDevice = sourceDevice;

        // Initialize Remix
        if (auto interf = remix::lib::loadRemixDllAndInitialize(L"d3d9.dll")) {
            g_remix = new remix::Interface{ *interf };
        }
        else {
            LUA->ThrowError("[gmRTX - Binary Module] - remix::loadRemixDllAndInitialize() failed"); 
        }

        g_remix->dxvk_RegisterD3D9Device(sourceDevice);

        // Initialize the new comprehensive RemixAPI
        if (!RemixAPI::RemixAPI::Instance().Initialize(g_remix, LUA)) {
            LUA->ThrowError("[gmRTX - Binary Module] Failed to initialize RemixAPI");
            return 0;
        }

        // Configure RTX settings through the new API
        auto& configManager = RemixAPI::RemixAPI::Instance().GetConfigManager();
        configManager.SetConfigVariable("rtx.enableAdvancedMode", "1");
        configManager.SetConfigVariable("rtx.fallbackLightMode", "0");

        #endif // _WIN64

        // Register Lua functions
        LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB); 

        LUA->Pop();

        Msg("[gmRTX - Binary Module] Module initialization completed successfully!\n");
        return 0;
    }
    catch (...) {
        Error("[gmRTX - Binary Module] Exception in module initialization\n");
        return 0;
    }
}

GMOD_MODULE_CLOSE() {
    try {
        Msg("[gmRTX - Binary Module] Shutting down module...\n");

#ifdef _WIN64
        RemixAPI::RemixAPI::Instance().Shutdown();
        g_d3dDevice = nullptr;

        if (g_remix) {
            delete g_remix;
            g_remix = nullptr;
        }
#endif

        Msg("[gmRTX - Binary Module] Module shutdown complete\n");
        return 0;
    }
    catch (...) {
        Error("[gmRTX - Binary Module] Exception in module shutdown\n");
        return 0;
    }
}