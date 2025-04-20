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
#include "mwr/mwr.hpp"
#include "remixapi/rtx_light_manager.h"
#include "remixapi/remixapi.h"
#include "math/math.hpp"
#include "entity_manager/entity_manager.hpp"
#endif // _WIN64

#include "shader_fixes/shader_hooks.h"
#include "prop_fixes.h" 
#include "HardwareSkinningHooks.h" 
#include <culling_fixes.h>
#include <modelload_fixes.h>
#include <globalconvars.h>

#ifdef GMOD_MAIN
extern IMaterialSystem* materials = NULL;
#endif

#ifdef _WIN64
// extern IShaderAPI* g_pShaderAPI = NULL;
remix::Interface* g_remix = nullptr;
#endif

using namespace GarrysMod::Lua;

// Define a proper LOG_GENERAL replacement function
void DummyLogGeneral(const char* prefix, const char* msg, ...) {
    // Basic implementation
    char buffer[1024];
    va_list args;
    va_start(args, msg);
    vsprintf_s(buffer, sizeof(buffer), msg, args);
    va_end(args);
    Msg("[LOG_GENERAL] %s: %s\n", prefix, buffer);
}

// In your delay load hook:
FARPROC WINAPI MyDelayLoadHook(unsigned dliNotify, PDelayLoadInfo pdli)
{
    if (dliNotify == dliFailGetProc) {
        if (strcmp(pdli->dlp.szProcName, "LOG_GENERAL") == 0) {
            // Return our function instead of a dummy variable
            return (FARPROC)DummyLogGeneral;
        }
    }
    return NULL;
}
// Define the hook variable
__declspec(selectany) PfnDliHook __pfnDliNotifyHook2 = MyDelayLoadHook;

#ifdef _WIN64
void* FindD3D9Device() {
    auto shaderapidx = GetModuleHandle("shaderapidx9.dll");
    if (!shaderapidx) {
        Error("[RTX Remix Fixes 2 - Binary Module] Failed to get shaderapidx9.dll module\n");
        return nullptr;
    }

    Msg("[RTX Remix Fixes 2 - Binary Module] shaderapidx9.dll module: %p\n", shaderapidx);

    static const char sign[] = "BA E1 0D 74 5E 48 89 1D ?? ?? ?? ??";
    auto ptr = ScanSign(shaderapidx, sign, sizeof(sign) - 1);
    if (!ptr) { 
        Error("[RTX Remix Fixes 2 - Binary Module] Failed to find D3D9Device signature\n");
        return nullptr;
    }

    auto offset = ((uint32_t*)ptr)[2];
    auto device = *(IDirect3DDevice9Ex**)((char*)ptr + offset + 12);
    if (!device) {
        Error("[RTX Remix Fixes 2 - Binary Module] D3D9Device pointer is null\n");
        return nullptr;
    }

    return device;
}
#endif // _WIN64

GMOD_MODULE_OPEN() { 
    try {
        Msg("[RTX Remix Fixes 2 - Binary Module] - Module loaded!\n"); 

        // Remix initialization is only available in 64-bit builds for now
#ifdef _WIN64
        // Find Source's D3D9 device
        auto sourceDevice = static_cast<IDirect3DDevice9Ex*>(FindD3D9Device());
        if (!sourceDevice) {
            LUA->ThrowError("[RTX Remix Fixes 2 - Binary Module] Failed to find D3D9 device");
            return 0;
        }

        // Initialize Remix
        if (auto interf = remix::lib::loadRemixDllAndInitialize(L"d3d9.dll")) {
            g_remix = new remix::Interface{ *interf };
        }
        else {
            LUA->ThrowError("[RTX Remix Fixes 2 - Binary Module] - remix::loadRemixDllAndInitialize() failed"); 
        }

        g_remix->dxvk_RegisterD3D9Device(sourceDevice);

        // Initialize RTX Light Manager
        RTXLightManager::Instance().Initialize(g_remix);

        // Force clean state on startup
        if (g_remix) {
            // Set minimum resource settings
            g_remix->SetConfigVariable("rtx.resourceLimits.maxCacheSize", "256");  // MB
            g_remix->SetConfigVariable("rtx.resourceLimits.maxVRAM", "1024");     // MB
            g_remix->SetConfigVariable("rtx.resourceLimits.forceCleanup", "1");
        }

        // Configure RTX settings
        if (g_remix) {
            g_remix->SetConfigVariable("rtx.enableAdvancedMode", "1");
            g_remix->SetConfigVariable("rtx.fallbackLightMode", "0");
            Msg("[RTX Remix Fixes 2 - Binary Module] Remix configuration set\n");
        }
#endif //_WIN64

#ifdef HWSKIN_PATCHES
        //HardwareSkinningHooks::Instance().Initialize();
#endif //HWSKIN_PATCHES`

        ModelRenderHooks::Instance().Initialize();
        ModelLoadHooks::Instance().Initialize();

        // Register Lua functions
        LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB); 

        // Only register Remix-related Lua functions in 64-bit builds
        #ifdef _WIN64
            RemixAPI::Initialize(LUA);
            RTXLightManager::InitializeLuaBindings(LUA);
        #endif // _WIN64    

        LUA->Pop();

        return 0;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in module initialization\n");
        return 0;
    }
}

GMOD_MODULE_CLOSE() {
    try {
        Msg("[RTX Remix Fixes 2 - Binary Module] Shutting down module...\n");

#ifdef _WIN64
        RTXLightManager::Instance().Shutdown();
#endif // _WIN64

#ifdef HWSKIN_PATCHES
        //HardwareSkinningHooks::Instance().Shutdown();
#endif //HWSKIN_PATCHES

       ModelRenderHooks::Instance().Shutdown();
       ModelLoadHooks::Instance().Shutdown();

#ifdef _WIN64
        if (g_remix) {
            delete g_remix;
            g_remix = nullptr;
        }
#endif

        Msg("[RTX Remix Fixes 2 - Binary Module] Module shutdown complete\n");
        return 0;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in module shutdown\n");
        return 0;
    }
}