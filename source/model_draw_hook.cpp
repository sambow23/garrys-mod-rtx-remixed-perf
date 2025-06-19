#include "model_draw_hook.h"
#include "memory_patcher.h"
#include <Windows.h>
#include "GarrysMod/Lua/Interface.h"
#include "icvar.h"
#include "globalconvars.h"

// Global control variable (kept for backwards compatibility, but ConVar takes precedence)
static bool g_forceStaticLighting = true;
static bool g_hookEnabled = false; // Temporarily disable hook to prevent crashes

// Function to toggle the static lighting from external code
void SetForceStaticLighting(bool enable) {
    g_forceStaticLighting = enable;
    
    // Also update the ConVar if available
    if (GlobalConvars::rtx_force_static_lighting) {
        GlobalConvars::rtx_force_static_lighting->SetValue(enable);
    }
    
    Msg("[RTXF2 - ModelDrawHook] Force static lighting %s\n", enable ? "enabled" : "disabled");
}

bool GetForceStaticLighting() {
    // Check ConVar first, fall back to global variable
    if (GlobalConvars::rtx_force_static_lighting) {
        return GlobalConvars::rtx_force_static_lighting->GetBool();
    }
    return g_forceStaticLighting;
}

// Function to enable/disable the hook (for debugging)
void SetModelDrawHookEnabled(bool enable) {
    g_hookEnabled = enable;
    Msg("[RTXF2 - ModelDrawHook] Hook %s\n", enable ? "enabled" : "disabled");
}

// Based on Source SDK and IDA analysis
// This is the actual DrawModelInfo_t structure used by the engine
struct DrawModelInfo_t {
    void* m_pStudioHdr;         // studiohdr_t*
    void* m_pHardwareData;      // studiohwdata_t*
    void* m_pStudioMeshes;      // void*
    void* m_pClientEntity;      // IClientRenderable*
    void* m_Decals;             // void*
    int m_Skin;
    int m_Body;
    int m_HitboxSet;
    void* m_pClientRenderable;  // IClientRenderable*
    int m_LOD;
    void* m_pColorMeshes;       // ColorMeshInfo_t*
    bool m_bStaticLighting;
    int m_DrawFlags;            // This is where the STUDIO_* flags are stored
    // ... potentially more fields, but these are the main ones
};

// Alternative approach: Since we're hooking at the vtable level, 
// we might not need the exact structure - just match the calling convention
// The function signature from IDA analysis appears to be:
// int DrawModel(DrawModelInfo_t& info, matrix3x4_t* pBoneToWorld, float* pFlexWeights, float* pFlexDelayedWeights, Vector& modelOrigin, int flags)

// But based on the disassembly, it looks like it's actually:
// int DrawModel(void* pRenderContext, DrawModelInfo_t* pInfo, int flags)
// where pInfo is the structure pointer passed in rdx

// Hook for the main DrawModel function
// Based on IDA analysis: vtable offset 0x88 (index 17)
// The actual calling convention from the disassembly:
// this->DrawModel(DrawModelInfo_t* pInfo)
Define_method_Hook(int, StudioRender_DrawModel, void*,
    DrawModelInfo_t* pInfo)     // The DrawModelInfo structure (rdx in calling convention)
{
    // Log the call for debugging
    static int callCount = 0;
    callCount++;
    
    if (callCount <= 5) { // Only log first 5 calls to avoid spam
        Msg("[RTXF2] DrawModel hook called #%d: _this=0x%p, pInfo=0x%p\n", callCount, _this, pInfo);
    }

    // If hook is disabled, just call original
    if (!g_hookEnabled) {
        return StudioRender_DrawModel_trampoline()(_this, pInfo);
    }

    // Safety check: validate the pointer before accessing it
    if (!pInfo || IsBadReadPtr(pInfo, sizeof(DrawModelInfo_t))) {
        Warning("[RTXF2] Invalid pInfo pointer: 0x%p, calling original function\n", pInfo);
        return StudioRender_DrawModel_trampoline()(_this, pInfo);
    }

    // Additional safety check: ensure we're not getting garbage values
    if ((uintptr_t)pInfo < 0x1000 || (uintptr_t)pInfo > 0x7FFFFFFFFFFF) {
        Warning("[RTXF2] Suspicious pInfo pointer value: 0x%p, calling original function\n", pInfo);
        return StudioRender_DrawModel_trampoline()(_this, pInfo);
    }

    // Use the ConVar-aware function to check if static lighting should be forced
    if (GetForceStaticLighting()) {
        // Try to safely access the structure
        __try {
            int originalFlags = pInfo->m_DrawFlags;
            pInfo->m_DrawFlags |= 0x10; // STUDIO_STATIC_LIGHTING
            
            // Call original function
            int result = StudioRender_DrawModel_trampoline()(_this, pInfo);
            
            // Restore original flags (good practice)
            pInfo->m_DrawFlags = originalFlags;
            
            if (callCount <= 5) {
                Msg("[RTXF2] Successfully modified flags: 0x%X -> 0x%X\n", originalFlags, originalFlags | 0x10);
            }
            
            return result;
        }
        __except(EXCEPTION_EXECUTE_HANDLER) {
            Warning("[RTXF2] Exception accessing pInfo structure, calling original function\n");
            return StudioRender_DrawModel_trampoline()(_this, pInfo);
        }
    }

    // Call original function if not forcing static lighting
    return StudioRender_DrawModel_trampoline()(_this, pInfo);
}

ModelDrawHook& ModelDrawHook::Instance() {
    static ModelDrawHook instance;
    return instance;
}

void ModelDrawHook::Initialize() {
    if (m_bInitialized) {
        Msg("[RTXF2 - ModelDrawHook] Already initialized, skipping\n");
        return;
    }

    try {
        Msg("[RTXF2 - ModelDrawHook] Initializing model draw hooks...\n");

        // Sync with ConVar if available, otherwise enable by default
        if (GlobalConvars::rtx_force_static_lighting) {
            g_forceStaticLighting = GlobalConvars::rtx_force_static_lighting->GetBool();
            Msg("[RTXF2 - ModelDrawHook] Static lighting synced with ConVar: %s\n", g_forceStaticLighting ? "enabled" : "disabled");
        } else {
            g_forceStaticLighting = true;
            Msg("[RTXF2 - ModelDrawHook] Static lighting enabled by default (ConVar not available yet)\n");
        }

        // Find the studio render interface
        // Based on IDA analysis, this is stored at qword_180DBB608
        HMODULE engineModule = GetModuleHandleA("engine.dll");
        if (!engineModule) {
            Warning("[RTXF2 - ModelDrawHook] Failed to get engine.dll handle\n");
            return;
        }
        Msg("[RTXF2 - ModelDrawHook] Found engine.dll at 0x%p\n", engineModule);

        // Pattern to find the studio render interface pointer
        // This pattern looks for: mov rcx, cs:qword_180DBB608
        Msg("[RTXF2 - ModelDrawHook] Searching for studio render interface pattern...\n");
        void* studioRenderPtrPattern = g_MemoryPatcher.FindPatternWildcard(
            engineModule, 
            "48 8B 0D ? ? ? ? 48 8B 01 FF 90 F8 00 00 00"
        );

        if (!studioRenderPtrPattern) {
            Warning("[RTXF2 - ModelDrawHook] Failed to find studio render interface pattern\n");
            // Try alternative approach - for now just mark as initialized so Lua functions work
            m_bInitialized = true;
            Msg("[RTXF2 - ModelDrawHook] Marked as initialized (pattern search failed, but Lua functions will work)\n");
            return;
        }
        Msg("[RTXF2 - ModelDrawHook] Found pattern at 0x%p\n", studioRenderPtrPattern);

        // Extract the actual pointer address from the instruction
        // The pattern is: 48 8B 0D [4 byte offset] - we need to calculate the actual address
        uint8_t* instruction = (uint8_t*)studioRenderPtrPattern;
        int32_t offset = *(int32_t*)(instruction + 3); // Get the 4-byte offset
        void** studioRenderPtr = (void**)(instruction + 7 + offset); // Calculate final address

        Msg("[RTXF2 - ModelDrawHook] Studio render pointer calculated as 0x%p\n", studioRenderPtr);

        if (!studioRenderPtr || !*studioRenderPtr) {
            Warning("[RTXF2 - ModelDrawHook] Studio render interface pointer is null\n");
            // Still mark as initialized for Lua functions
            m_bInitialized = true;
            Msg("[RTXF2 - ModelDrawHook] Marked as initialized (null pointer, but Lua functions will work)\n");
            return;
        }

        // Get the vtable
        void* studioRender = *studioRenderPtr;
        void** vtable = *(void***)studioRender;

        Msg("[RTXF2 - ModelDrawHook] Studio render instance: 0x%p, vtable: 0x%p\n", studioRender, vtable);

        if (!vtable) {
            Warning("[RTXF2 - ModelDrawHook] Studio render vtable is null\n");
            // Still mark as initialized for Lua functions
            m_bInitialized = true;
            Msg("[RTXF2 - ModelDrawHook] Marked as initialized (null vtable, but Lua functions will work)\n");
            return;
        }

        // Hook the DrawModel function at vtable index 18 (0x90 / 8)
        void* drawModelFunc = vtable[18];
        if (!drawModelFunc) {
            Warning("[RTXF2 - ModelDrawHook] DrawModel function pointer is null\n");
            // Still mark as initialized for Lua functions
            m_bInitialized = true;
            Msg("[RTXF2 - ModelDrawHook] Marked as initialized (null function, but Lua functions will work)\n");
            return;
        }

        Msg("[RTXF2 - ModelDrawHook] Found DrawModel function at 0x%p\n", drawModelFunc);

        // Set up the hook using your existing system
        Setup_Hook(StudioRender_DrawModel, drawModelFunc);

        m_bInitialized = true;
        Msg("[RTXF2 - ModelDrawHook] Model draw hooks initialized successfully with vtable hook\n");
    }
    catch (const std::exception& e) {
        Warning("[RTXF2 - ModelDrawHook] Exception during initialization: %s\n", e.what());
        // Still mark as initialized for Lua functions
        m_bInitialized = true;
        Msg("[RTXF2 - ModelDrawHook] Marked as initialized despite exception (Lua functions will work)\n");
    }
    catch (...) {
        Warning("[RTXF2 - ModelDrawHook] Unknown exception during initialization\n");
        // Still mark as initialized for Lua functions
        m_bInitialized = true;
        Msg("[RTXF2 - ModelDrawHook] Marked as initialized despite unknown exception (Lua functions will work)\n");
    }
}

void ModelDrawHook::Shutdown() {
    if (!m_bInitialized) {
        return;
    }

    try {
        Msg("[RTXF2 - ModelDrawHook] Shutting down model draw hooks...\n");
        
        // Disable the hook
        StudioRender_DrawModel_hook.Disable();
        
        m_bInitialized = false;
        Msg("[RTXF2 - ModelDrawHook] Model draw hooks shutdown complete\n");
    }
    catch (...) {
        Warning("[RTXF2 - ModelDrawHook] Exception during shutdown\n");
    }
} 