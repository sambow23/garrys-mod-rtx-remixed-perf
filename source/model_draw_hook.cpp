#include "model_draw_hook.h"
#include "memory_patcher.h"
#include <Windows.h>
#include "GarrysMod/Lua/Interface.h"
#include "icvar.h"
#include "globalconvars.h"

// Global control variable (kept for backwards compatibility, but ConVar takes precedence)
static bool g_forceStaticLighting = true;
static bool g_hookEnabled = true; // Temporarily disable hook modifications to test basic hooking

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

// Hook for the main DrawModel function (static props)
// Based on IDA analysis: vtable offset 0x90 (index 18)
// The actual calling convention from the disassembly:
// this->DrawModel(DrawModelInfo_Internal_t* pInfo)
Define_method_Hook(int, StudioRender_DrawModel, void*,
    DrawModelInfo_Internal_t* pInfo)     // The DrawModelInfo structure (rdx in calling convention)
{
    // Log the call for debugging
    static int callCount = 0;
    callCount++;
    
    if (callCount <= 5) { // Only log first 5 calls to avoid spam
        Msg("[RTXF2] Static DrawModel hook called #%d: _this=0x%p, pInfo=0x%p\n", callCount, _this, pInfo);
    }

    // If hook is disabled, just call original
    if (!g_hookEnabled) {
        return StudioRender_DrawModel_trampoline()(_this, pInfo);
    }

    // Safety check: validate the pointer before accessing it
    if (!pInfo || IsBadReadPtr(pInfo, sizeof(DrawModelInfo_Internal_t))) {
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
            // First, let's validate that we can read the flags field safely
            if (IsBadReadPtr(&pInfo->m_DrawFlags, sizeof(int))) {
                Warning("[RTXF2] Cannot read flags field at offset 0x40, calling original function\n");
                return StudioRender_DrawModel_trampoline()(_this, pInfo);
            }
            
            // Check if we can write to the flags field
            if (IsBadWritePtr(&pInfo->m_DrawFlags, sizeof(int))) {
                Warning("[RTXF2] Cannot write to flags field at offset 0x40, calling original function\n");
                return StudioRender_DrawModel_trampoline()(_this, pInfo);
            }
            
            // Instead of copying the structure, temporarily modify the flags directly
            int originalFlags = pInfo->m_DrawFlags;
            pInfo->m_DrawFlags |= 0x10; // STUDIO_STATIC_LIGHTING
            
            if (callCount <= 5) {
                Msg("[RTXF2] Static Modified flags: 0x%X -> 0x%X (at offset 0x40)\n", originalFlags, pInfo->m_DrawFlags);
                Msg("[RTXF2] Static Structure base: 0x%p, flags address: 0x%p\n", pInfo, &pInfo->m_DrawFlags);
            }
            
            // Call original function with modified flags
            int result = StudioRender_DrawModel_trampoline()(_this, pInfo);
            
            // Restore original flags immediately after the call
            pInfo->m_DrawFlags = originalFlags;
            
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

// Hook for the main IStudioRender::DrawModel function (dynamic entities)
// This uses the Source SDK DrawModelInfo_t structure from istudiorender.h
Define_method_Hook(void, IStudioRender_DrawModel, void*,
    DrawModelResults_t* pResults, const DrawModelInfo_t& info, matrix3x4_t* pBoneToWorld, float* pFlexWeights, float* pFlexDelayedWeights, const Vector& modelOrigin, int flags)
{
    static int callCount = 0;
    callCount++;
    
    if (callCount <= 5) { // Only log first 5 calls to avoid spam
        // Safely access m_bStaticLighting with validation
        bool staticLighting = false;
        __try {
            staticLighting = info.m_bStaticLighting;
        }
        __except(EXCEPTION_EXECUTE_HANDLER) {
            staticLighting = false; // Default value if access fails
        }
        Msg("[RTXF2] Dynamic DrawModel hook called #%d: _this=0x%p, info=0x%p, flags=0x%X, m_bStaticLighting=%d\n", callCount, _this, &info, flags, staticLighting);
    }

    // If hook is disabled, just call original
    if (!g_hookEnabled) {
        return IStudioRender_DrawModel_trampoline()(_this, pResults, info, pBoneToWorld, pFlexWeights, pFlexDelayedWeights, modelOrigin, flags);
    }

    // Use the ConVar-aware function to check if static lighting should be forced
    if (GetForceStaticLighting()) {
        // Validate the info parameter before accessing it
        __try {
            // First, safely check if we can read the m_bStaticLighting field
            bool testRead = info.m_bStaticLighting;
            (void)testRead; // Suppress unused variable warning
            
            // Create a modifiable copy of the info structure
            DrawModelInfo_t modifiedInfo = info;
            
            // Force static lighting on in the structure
            bool originalStaticLighting = modifiedInfo.m_bStaticLighting;
            modifiedInfo.m_bStaticLighting = true;
            
            // Also add the static lighting flag to the flags parameter for good measure
            int modifiedFlags = flags | STUDIORENDER_DRAW_STATIC_LIGHTING;
        
            if (callCount <= 5) {
                Msg("[RTXF2] Dynamic Modified: m_bStaticLighting %d->%d, flags 0x%X->0x%X\n", 
                    originalStaticLighting, modifiedInfo.m_bStaticLighting, flags, modifiedFlags);
            }
            
            // Call original function with modified info and flags
            return IStudioRender_DrawModel_trampoline()(_this, pResults, modifiedInfo, pBoneToWorld, pFlexWeights, pFlexDelayedWeights, modelOrigin, modifiedFlags);
        }
        __except(EXCEPTION_EXECUTE_HANDLER) {
            Warning("[RTXF2] Exception accessing DrawModelInfo_t structure (info=0x%p), calling original function\n", &info);
            // Fall through to call original function without modifications
        }
    }

    // Call original function if not forcing static lighting
    return IStudioRender_DrawModel_trampoline()(_this, pResults, info, pBoneToWorld, pFlexWeights, pFlexDelayedWeights, modelOrigin, flags);
}

// Hook for IVModelRender::DrawModelExecute - this catches dynamic entities like ragdolls, NPCs, etc.
Define_method_Hook(void, IVModelRender_DrawModelExecute, void*, const DrawModelState_t& state, const ModelRenderInfo_t& pInfo, matrix3x4_t* pCustomBoneToWorld)
{
    static int callCount = 0;
    callCount++;
    
    if (callCount <= 5) { // Only log first 5 calls to avoid spam
        Msg("[RTXF2] DrawModelExecute hook called #%d: _this=0x%p, state=0x%p, m_drawFlags=0x%X\n", callCount, _this, &state, state.m_drawFlags);
    }

    // If hook is disabled, just call original
    if (!g_hookEnabled) {
        return IVModelRender_DrawModelExecute_trampoline()(_this, state, pInfo, pCustomBoneToWorld);
    }

    // Use the ConVar-aware function to check if static lighting should be forced
    if (GetForceStaticLighting()) {
        // Create a modifiable copy of the state structure
        DrawModelState_t modifiedState = state;
        
        // Force static lighting flag in the draw flags
        // Looking at the Source SDK, STUDIO_STATIC_LIGHTING is 0x10
        int originalFlags = modifiedState.m_drawFlags;
        modifiedState.m_drawFlags |= 0x10; // STUDIO_STATIC_LIGHTING
        
        if (callCount <= 5) {
            Msg("[RTXF2] DrawModelExecute Modified: m_drawFlags 0x%X->0x%X\n", 
                originalFlags, modifiedState.m_drawFlags);
        }
        
        // Call original function with modified state
        return IVModelRender_DrawModelExecute_trampoline()(_this, modifiedState, pInfo, pCustomBoneToWorld);
    }

    // Call original function if not forcing static lighting
    return IVModelRender_DrawModelExecute_trampoline()(_this, state, pInfo, pCustomBoneToWorld);
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
        // This pattern looks for the sequence in CStaticProp::DrawModel that calls the interface
        // 48 8B 0D ? ? ? ? = mov rcx, cs:off_1804B5D18
        // 48 8D 54 24 ?    = lea rdx, [rsp+var_68] 
        // 48 8B 01         = mov rax, [rcx]
        // FF 90 90 00 00 00 = call qword ptr [rax+90h]
        Msg("[RTXF2 - ModelDrawHook] Searching for CStaticProp::DrawModel interface pattern...\n");
        void* studioRenderPtrPattern = g_MemoryPatcher.FindPatternWildcard(
            engineModule, 
            "48 8B 0D ? ? ? ? 48 8D 54 24 ? 48 8B 01 FF 90 90 00 00 00"
        );

        if (!studioRenderPtrPattern) {
            Warning("[RTXF2 - ModelDrawHook] Failed to find CStaticProp::DrawModel interface pattern\n");
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

        Msg("[RTXF2 - ModelDrawHook] Found static props DrawModel function at 0x%p\n", drawModelFunc);

        // Set up the hook for static props using your existing system
        Setup_Hook(StudioRender_DrawModel, drawModelFunc);

        // Now find and hook the main IStudioRender interface for dynamic entities
        Msg("[RTXF2 - ModelDrawHook] Searching for main IStudioRender interface...\n");
        void* mainStudioRenderPattern = g_MemoryPatcher.FindPatternWildcard(
            engineModule, 
            "48 8B 0D ? ? ? ? 48 8B 01 FF 90 F8 00 00 00"
        );

        if (mainStudioRenderPattern) {
            Msg("[RTXF2 - ModelDrawHook] Found main IStudioRender pattern at 0x%p\n", mainStudioRenderPattern);
            
            // Extract the actual pointer address from the instruction
            uint8_t* instruction = (uint8_t*)mainStudioRenderPattern;
            int32_t offset = *(int32_t*)(instruction + 3); // Get the 4-byte offset
            void** mainStudioRenderPtr = (void**)(instruction + 7 + offset); // Calculate final address

            if (mainStudioRenderPtr && *mainStudioRenderPtr) {
                void* mainStudioRender = *mainStudioRenderPtr;
                void** mainVtable = *(void***)mainStudioRender;
                
                if (mainVtable) {
                    // Hook the main DrawModel function at vtable index 31 (0xF8 / 8)
                    void* mainDrawModelFunc = mainVtable[31];
                    if (mainDrawModelFunc) {
                        Msg("[RTXF2 - ModelDrawHook] Found dynamic entities DrawModel function at 0x%p\n", mainDrawModelFunc);
                        Setup_Hook(IStudioRender_DrawModel, mainDrawModelFunc);
                    } else {
                        Warning("[RTXF2 - ModelDrawHook] Main DrawModel function pointer is null\n");
                    }
                } else {
                    Warning("[RTXF2 - ModelDrawHook] Main studio render vtable is null\n");
                }
            } else {
                Warning("[RTXF2 - ModelDrawHook] Main studio render interface pointer is null\n");
            }
        } else {
            Warning("[RTXF2 - ModelDrawHook] Failed to find main IStudioRender interface pattern\n");
        }

        // Now find and hook the IVModelRender interface for DrawModelExecute (dynamic entities)
        Msg("[RTXF2 - ModelDrawHook] Loading IVModelRender interface...\n");
        
        // Load the IVModelRender interface directly from engine.dll
        HMODULE engineModule2 = GetModuleHandleA("engine.dll");
        if (engineModule2) {
            using CreateInterfaceFn = void* (*)(const char* pName, int* pReturnCode);
            CreateInterfaceFn createEngineInterface = (CreateInterfaceFn)GetProcAddress(engineModule2, "CreateInterface");
            
            if (createEngineInterface) {
                // Try to get the IVModelRender interface
                IVModelRender* pModelRender = (IVModelRender*)createEngineInterface(VENGINE_HUDMODEL_INTERFACE_VERSION, nullptr);
                
                if (pModelRender) {
                    Msg("[RTXF2 - ModelDrawHook] Successfully loaded IVModelRender interface at 0x%p\n", pModelRender);
                    
                    // Get the vtable
                    void** modelRenderVtable = *(void***)pModelRender;
                    
                    if (modelRenderVtable) {
                        // DrawModelExecute is at index 20 in the IVModelRender vtable
                        void* drawModelExecuteFunc = modelRenderVtable[20];
                        if (drawModelExecuteFunc) {
                            Msg("[RTXF2 - ModelDrawHook] Found DrawModelExecute function at 0x%p\n", drawModelExecuteFunc);
                            Setup_Hook(IVModelRender_DrawModelExecute, drawModelExecuteFunc);
                        } else {
                            Warning("[RTXF2 - ModelDrawHook] DrawModelExecute function pointer is null\n");
                        }
                    } else {
                        Warning("[RTXF2 - ModelDrawHook] IVModelRender vtable is null\n");
                    }
                } else {
                    Warning("[RTXF2 - ModelDrawHook] Failed to load IVModelRender interface\n");
                }
            } else {
                Warning("[RTXF2 - ModelDrawHook] Failed to get CreateInterface from engine.dll\n");
            }
        } else {
            Warning("[RTXF2 - ModelDrawHook] Failed to get engine.dll handle\n");
        }

        m_bInitialized = true;
        Msg("[RTXF2 - ModelDrawHook] Model draw hooks initialized successfully with static, dynamic, and execute hooks\n");
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
        
        // Disable all hooks
        StudioRender_DrawModel_hook.Disable();
        IStudioRender_DrawModel_hook.Disable();
        IVModelRender_DrawModelExecute_hook.Disable();
        
        m_bInitialized = false;
        Msg("[RTXF2 - ModelDrawHook] Model draw hooks shutdown complete\n");
    }
    catch (...) {
        Warning("[RTXF2 - ModelDrawHook] Exception during shutdown\n");
    }
} 