#ifdef _WIN64
#include "remixapi.h"
#include <tier0/dbg.h>

// External global variables
extern remix::Interface* g_remix;
extern IDirect3DDevice9Ex* g_d3dDevice;
IDirect3DDevice9Ex* g_d3dDevice = nullptr;

using namespace GarrysMod::Lua;

void RemixAPI::ClearRemixResources() {
#ifdef _WIN64
    if (!g_remix) return;

    // Force a new present cycle
    remixapi_PresentInfo presentInfo = {};
    g_remix->Present(&presentInfo);
    
    // Wait for GPU to finish
    if (g_d3dDevice) {
        g_d3dDevice->EvictManagedResources();
    }
#endif
}

// Lua function implementations
LUA_FUNCTION(ClearRTXResources_Native) {
    try {
        Msg("[RTX Remix Fixes 2 - Binary Module] Clearing RTX resources...\n");

#ifdef _WIN64
        if (g_remix) {
            // Force cleanup through config
            g_remix->SetConfigVariable("rtx.resourceLimits.forceCleanup", "1");
            
            // Force a new present cycle
            remixapi_PresentInfo presentInfo = {};
            g_remix->Present(&presentInfo);
            
            // Reset to normal cleanup behavior
            g_remix->SetConfigVariable("rtx.resourceLimits.forceCleanup", "0");
        }
#endif

        if (g_d3dDevice) {
            g_d3dDevice->EvictManagedResources();
        }

        LUA->PushBool(true);
        return 1;
    } catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in ClearRTXResources\n");
        LUA->PushBool(false);
        return 1;
    }
}

LUA_FUNCTION(GetRemixUIState) {
    try {
#ifdef _WIN64
        if (!g_remix) {
            LUA->PushNumber(0); // None (UI not visible)
            return 1;
        }

        auto result = g_remix->GetUIState();
        if (!result) {
            LUA->PushNumber(0); // None (UI not visible)
            return 1;
        }

        // Convert to a Lua number (matching the enum values)
        int state = static_cast<int>(result.value());
        LUA->PushNumber(state);
#else 
		LUA->PushNumber(0);
#endif
        return 1;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in GetRemixUIState\n");
        LUA->PushNumber(0);
        return 1;
    }
}

LUA_FUNCTION(SetRemixUIState) {
    try {
#ifdef _WIN64
        if (!g_remix) {
            LUA->PushBool(false);
            return 1;
        }

        if (!LUA->IsType(1, Type::NUMBER)) {
            LUA->ThrowError("Expected number argument for UI state");
            return 0;
        }

        int stateNum = static_cast<int>(LUA->GetNumber(1));
        remix::UIState state = static_cast<remix::UIState>(stateNum);
        
        auto result = g_remix->SetUIState(state);
        LUA->PushBool(result);
#else
        LUA->PushBool(false);
#endif
        return 1;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in SetRemixUIState\n");
        LUA->PushBool(false);
        return 1;
    }
}

LUA_FUNCTION(PrintRemixUIState) {
    try {
#ifdef _WIN64
        Msg("[RTX Remix Fixes 2 - Binary Module] Checking Remix UI state...\n");
        
        if (!g_remix) {
            Msg("[RTX Remix Fixes 2 - Binary Module] Error: g_remix is NULL (Remix API not initialized)\n");
            return 0;
        }
        
        Msg("[RTX Remix Fixes 2 - Binary Module] g_remix is valid, checking GetUIState function...\n");
        
        // Check if the function exists in the interface
        if (!g_remix->m_CInterface.GetUIState) {
            Msg("[RTX Remix Fixes 2 - Binary Module] Error: GetUIState function is not available in the Remix API\n");
            Msg("[RTX Remix Fixes 2 - Binary Module] This may indicate you're using an older version of Remix that doesn't support this feature\n");
            return 0;
        }
        
        Msg("[RTX Remix Fixes 2 - Binary Module] GetUIState function exists, calling it...\n");
        
        // Try to call the function directly
        remixapi_UIState rawState = g_remix->m_CInterface.GetUIState();
        Msg("[RTX Remix Fixes 2 - Binary Module] Raw UI state value: %d\n", rawState);
        
        // Now try to get it through the wrapper
        auto result = g_remix->GetUIState();
        if (!result) {
            Msg("[RTX Remix Fixes 2 - Binary Module] Error: GetUIState wrapper returned failure\n");
            Msg("[RTX Remix Fixes 2 - Binary Module] Error code: %d\n", result.status());
            return 0;
        }

        int state = static_cast<int>(result.value());
        const char* stateStr = "Unknown";
        
        switch (state) {
            case 0:
                stateStr = "None (UI not visible)";
                break;
            case 1:
                stateStr = "Basic UI";
                break;
            case 2:
                stateStr = "Advanced UI";
                break;
        }
        
        Msg("[RTX Remix Fixes 2 - Binary Module] Current UI state: %d (%s)\n", state, stateStr);
#endif
        return 0;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in PrintRemixUIState\n");
        return 0;
    }
}

LUA_FUNCTION(SetIgnoreGameDirectionalLights) {
    try {
        #ifdef _WIN64
        if (!g_remix) {
            LUA->PushBool(false);
            return 1;
        }

        if (!LUA->IsType(1, Type::BOOL)) {
            LUA->ThrowError("Expected boolean argument for IgnoreGameDirectionalLights state");
            return 0;
        }

        bool shouldIgnore = LUA->GetBool(1);
        const char* value = shouldIgnore ? "1" : "0";
        
        bool result = g_remix->SetConfigVariable("rtx.ignoreGameDirectionalLights", value);
        
        Msg("[RTX Remix Fixes 2 - Binary Module] Setting rtx.ignoreGameDirectionalLights to %s\n", value);
        
        LUA->PushBool(result);
        #endif
        return 1;
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Binary Module] Exception in SetIgnoreGameDirectionalLights\n");
        LUA->PushBool(false);
        return 1;
    }
}

void RemixAPI::Initialize(GarrysMod::Lua::ILuaBase* LUA) {
    LUA->PushCFunction(GetRemixUIState);
    LUA->SetField(-2, "GetRemixUIState");

    LUA->PushCFunction(SetRemixUIState);
    LUA->SetField(-2, "SetRemixUIState");

    LUA->PushCFunction(PrintRemixUIState);
    LUA->SetField(-2, "PrintRemixUIState");

    LUA->PushCFunction(ClearRTXResources_Native);
    LUA->SetField(-2, "ClearRTXResources");

    LUA->PushCFunction(SetIgnoreGameDirectionalLights);
    LUA->SetField(-2, "SetIgnoreGameDirectionalLights");
}
#endif