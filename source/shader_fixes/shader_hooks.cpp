#include "shader_hooks.h"
#include <algorithm>
#include <psapi.h>
#pragma comment(lib, "psapi.lib")

// Define the global variables here
IShaderAPI* g_pShaderAPI = nullptr;
IDirect3DDevice9* g_pD3DDevice = nullptr;

// Initialize other static members
ShaderAPIHooks::ShaderState ShaderAPIHooks::s_state;
std::unordered_set<std::string> ShaderAPIHooks::s_knownProblematicShaders;
std::unordered_set<std::string> ShaderAPIHooks::s_problematicMaterials;
Detouring::Hook ShaderAPIHooks::s_ConMsg_hook;
ShaderAPIHooks::ConMsg_t ShaderAPIHooks::g_original_ConMsg = nullptr;
ShaderAPIHooks::DrawIndexedPrimitive_t ShaderAPIHooks::g_original_DrawIndexedPrimitive = nullptr;
ShaderAPIHooks::SetVertexShaderConstantF_t ShaderAPIHooks::g_original_SetVertexShaderConstantF = nullptr;
ShaderAPIHooks::SetStreamSource_t ShaderAPIHooks::g_original_SetStreamSource = nullptr;
ShaderAPIHooks::SetVertexShader_t ShaderAPIHooks::g_original_SetVertexShader = nullptr;
ShaderAPIHooks::DivisionFunction_t ShaderAPIHooks::g_original_DivisionFunction = nullptr;
ShaderAPIHooks::VertexBufferLock_t ShaderAPIHooks::g_original_VertexBufferLock = nullptr;
std::unordered_set<uintptr_t> ShaderAPIHooks::s_problematicAddresses;
ShaderAPIHooks::ParticleRender_t ShaderAPIHooks::g_original_ParticleRender = nullptr;
ShaderAPIHooks::InitParamsEyes_t ShaderAPIHooks::g_original_InitParamsEyes = nullptr;
ShaderAPIHooks::InitEyes_t ShaderAPIHooks::g_original_InitEyes = nullptr;
ShaderAPIHooks::DrawEyes_t ShaderAPIHooks::g_original_DrawEyes = nullptr;

namespace {
    bool IsValidPointer(const void* ptr, size_t size) {
        if (!ptr) return false;
        MEMORY_BASIC_INFORMATION mbi = { 0 };
        if (VirtualQuery(ptr, &mbi, sizeof(mbi)) == 0) return false;
        if (mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) return false;
        if (!(mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE))) return false;
        return true;
    }
}

void ShaderAPIHooks::Initialize() {
    try {
        m_vehHandle = nullptr;
        m_vehHandlerDivision = nullptr;

        // First install our exception handlers
        m_vehHandlerDivision = AddVectoredExceptionHandler(0, [](PEXCEPTION_POINTERS exceptionInfo) -> LONG {
            if (exceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_INT_DIVIDE_BY_ZERO) {
                void* crashAddress = exceptionInfo->ExceptionRecord->ExceptionAddress;
                
                // Get module information
                HMODULE hModule = NULL;
                if (GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                    (LPCTSTR)crashAddress, &hModule)) {
                    char moduleName[MAX_PATH];
                    GetModuleFileNameA(hModule, moduleName, sizeof(moduleName));
                    Warning("[Shader Fixes] Division by zero in module: %s\n", moduleName);
                }

                // Detailed crash context
                Warning("[Shader Fixes] Division crash details:\n");
                Warning("  Address: %p\n", crashAddress);
                Warning("  Thread ID: %u\n", GetCurrentThreadId());
                
                // Stack trace
                void* stack[64];
                WORD frames = CaptureStackBackTrace(0, 64, stack, NULL);
                Warning("  Stack trace (%d frames):\n", frames);
                for (WORD i = 0; i < frames; i++) {
                    Warning("    %d: %p\n", i, stack[i]);
                }

                // Set safe values and continue
                exceptionInfo->ContextRecord->Rax = 1;
                exceptionInfo->ContextRecord->Rip += 2;
                return EXCEPTION_CONTINUE_EXECUTION;
            }
            return EXCEPTION_CONTINUE_SEARCH;
        });

        if (!m_vehHandlerDivision) {
            Error("[Shader Fixes] Failed to install division-specific VEH\n");
            return;
        }

        Msg("[Shader Fixes] Installed division-specific VEH at %p\n", m_vehHandlerDivision);

        // General exception handler
        m_vehHandle = AddVectoredExceptionHandler(1, [](PEXCEPTION_POINTERS exceptionInfo) -> LONG {
            if (exceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_INT_DIVIDE_BY_ZERO) {
                void* crashAddress = exceptionInfo->ExceptionRecord->ExceptionAddress;
                Warning("[Shader Fixes] Caught division by zero at %p\n", crashAddress);
                
                Warning("[Shader Fixes] Register state:\n");
                Warning("  RAX: %016llX\n", exceptionInfo->ContextRecord->Rax);
                Warning("  RCX: %016llX\n", exceptionInfo->ContextRecord->Rcx);
                Warning("  RDX: %016llX\n", exceptionInfo->ContextRecord->Rdx);
                Warning("  R8:  %016llX\n", exceptionInfo->ContextRecord->R8);
                Warning("  R9:  %016llX\n", exceptionInfo->ContextRecord->R9);
                Warning("  RIP: %016llX\n", exceptionInfo->ContextRecord->Rip);

                exceptionInfo->ContextRecord->Rax = 1;
                exceptionInfo->ContextRecord->Rip += 2;
                return EXCEPTION_CONTINUE_EXECUTION;
            }
            return EXCEPTION_CONTINUE_SEARCH;
        });

        if (!m_vehHandle) {
            Error("[Shader Fixes] Failed to install general VEH\n");
            return;
        }

        Msg("[Shader Fixes] Installed general VEH at %p\n", m_vehHandle);

        // Get shaderapidx9.dll module
        HMODULE shaderapidx9 = GetModuleHandle("shaderapidx9.dll");
        if (!shaderapidx9) {
            Error("[Shader Fixes] Failed to get shaderapidx9.dll module\n");
            return;
        }

        // Get shaderapidx9.dll module
        auto shaderapidx = GetModuleHandle("shaderapidx9.dll");
        if (!shaderapidx) {
            Error("[Shader Fixes] Failed to get shaderapidx9.dll module\n");
            return;
        }

        // Add verification of function signatures
        auto VerifyFunction = [](void* addr, const char* name, const unsigned char* expectedBytes, size_t length) {
            if (!addr) return false;
            
            __try {
                unsigned char* bytes = reinterpret_cast<unsigned char*>(addr);
                bool matches = true;
                
                Msg("[Shader Fixes] Verifying %s at %p:\n", name, addr);
                Msg("Expected: ");
                for (size_t i = 0; i < length; i++) {
                    Msg("%02X ", expectedBytes[i]);
                    if (bytes[i] != expectedBytes[i]) {
                        matches = false;
                    }
                }
                Msg("\nActual:   ");
                for (size_t i = 0; i < length; i++) {
                    Msg("%02X ", bytes[i]);
                }
                Msg("\n");
                
                return matches;
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception while verifying %s\n", name);
                return false;
            }
        };

        // Expected signatures based on the memory dump
        const unsigned char InitParamsEyes_sig[] = { 0x8B, 0x74, 0x24, 0x60, 0x48, 0x8B, 0x7C, 0x24, 0x68 };
        const unsigned char InitEyes_sig[] = { 0x07, 0x48, 0x83, 0xC4, 0x20, 0x5B };
        const unsigned char DrawEyes_sig[] = { 0x48, 0x8B, 0x5C, 0x24, 0x30, 0x48, 0x8B, 0x74, 0x24, 0x38 };

        // Known addresses from memory dump
        void* InitParamsEyes = reinterpret_cast<void*>(0x9C75A4C5);
        void* InitEyes = reinterpret_cast<void*>(0x9C7557AE);
        void* DrawEyes = reinterpret_cast<void*>(0x9C75E69C);

        // Verify addresses are within the module
        MODULEINFO modInfo;
        if (GetModuleInformation(GetCurrentProcess(), shaderapidx, &modInfo, sizeof(MODULEINFO))) {
            uintptr_t moduleStart = reinterpret_cast<uintptr_t>(modInfo.lpBaseOfDll);
            uintptr_t moduleEnd = moduleStart + modInfo.SizeOfImage;

            // Adjust addresses relative to module base
            InitParamsEyes = reinterpret_cast<void*>(moduleStart + (reinterpret_cast<uintptr_t>(InitParamsEyes) - 0x9C750000));
            InitEyes = reinterpret_cast<void*>(moduleStart + (reinterpret_cast<uintptr_t>(InitEyes) - 0x9C750000));
            DrawEyes = reinterpret_cast<void*>(moduleStart + (reinterpret_cast<uintptr_t>(DrawEyes) - 0x9C750000));
        }

        // Verify and hook functions with signature checking
        if (VerifyFunction(InitParamsEyes, "InitParamsEyes", InitParamsEyes_sig, sizeof(InitParamsEyes_sig))) {
            Detouring::Hook::Target target(InitParamsEyes);
            m_InitParamsEyes_hook.Create(target, InitParamsEyes_detour);
            g_original_InitParamsEyes = m_InitParamsEyes_hook.GetTrampoline<InitParamsEyes_t>();
            m_InitParamsEyes_hook.Enable();
            Msg("[Shader Fixes] Successfully hooked InitParamsEyes\n");
        }

        if (VerifyFunction(InitEyes, "InitEyes", InitEyes_sig, sizeof(InitEyes_sig))) {
            Detouring::Hook::Target target(InitEyes);
            m_InitEyes_hook.Create(target, InitEyes_detour);
            g_original_InitEyes = m_InitEyes_hook.GetTrampoline<InitEyes_t>();
            m_InitEyes_hook.Enable();
            Msg("[Shader Fixes] Successfully hooked InitEyes\n");
        }

        if (VerifyFunction(DrawEyes, "DrawEyes", DrawEyes_sig, sizeof(DrawEyes_sig))) {
            Detouring::Hook::Target target(DrawEyes);
            m_DrawEyes_hook.Create(target, DrawEyes_detour);
            g_original_DrawEyes = m_DrawEyes_hook.GetTrampoline<DrawEyes_t>();
            m_DrawEyes_hook.Enable();
            Msg("[Shader Fixes] Successfully hooked DrawEyes\n");
        }

        // Find and hook problematic patterns
        static const std::pair<const char*, const char*> signatures[] = {
            {"48 63 C8 99 F7 F9", "Division instruction"},
            {"89 51 34 89 38 48 89 D9", "Function entry"},
            {"8B F2 44 0F B6 C0", "Parameter setup"},
            {"F7 F9 03 C1 0F AF C1", "Division and multiply"},
            {"42 89 44 24 20 44 89 44 24 28", "Pre-crash sequence"},
            {"48 8D 4C 24 20 E8", "Call sequence"}
        };

        for (const auto& sig : signatures) {
            void* found_ptr = ScanSign(shaderapidx9, sig.first, strlen(sig.first));
            if (found_ptr) {
                Msg("[Shader Fixes] Found %s at %p\n", sig.second, found_ptr);

                // Log surrounding bytes for verification
                unsigned char* bytes = reinterpret_cast<unsigned char*>(found_ptr);
                Msg("[Shader Fixes] Bytes at %s: ", sig.second);
                for (int i = -8; i <= 8; i++) {
                    Msg("%02X ", bytes[i]);
                }
                Msg("\n");

                // Hook division instructions
                if (strstr(sig.second, "Division")) {
                    Detouring::Hook::Target target(found_ptr);
                    m_DivisionFunction_hook.Create(target, DivisionFunction_detour);
                    g_original_DivisionFunction = m_DivisionFunction_hook.GetTrampoline<DivisionFunction_t>();
                    m_DivisionFunction_hook.Enable();
                    Msg("[Shader Fixes] Hooked division at %p\n", found_ptr);
                }
            }
        }

        // Find D3D9 device
        static const char device_sig[] = "BA E1 0D 74 5E 48 89 1D ?? ?? ?? ??";
        auto device_ptr = ScanSign(shaderapidx9, device_sig, sizeof(device_sig) - 1);
        if (device_ptr) {
            auto offset = ((uint32_t*)device_ptr)[2];
            g_pD3DDevice = *(IDirect3DDevice9**)((char*)device_ptr + offset + 12);
            if (!g_pD3DDevice) {
                Error("[Shader Fixes] Failed to get D3D9 device\n");
                return;
            }
        } else {
            Error("[Shader Fixes] Failed to find D3D9 device signature\n");
            return;
        }

        // Get D3D9 vtable
        void** vftable = *reinterpret_cast<void***>(g_pD3DDevice);
        if (!vftable) {
            Error("[Shader Fixes] Failed to get D3D9 vtable\n");
            return;
        }

        // Hook D3D9 functions
        try {
            // DrawIndexedPrimitive (index 82)
            Detouring::Hook::Target target_draw(&vftable[82]);
            m_DrawIndexedPrimitive_hook.Create(target_draw, DrawIndexedPrimitive_detour);
            g_original_DrawIndexedPrimitive = m_DrawIndexedPrimitive_hook.GetTrampoline<DrawIndexedPrimitive_t>();
            m_DrawIndexedPrimitive_hook.Enable();
            Msg("[Shader Fixes] Hooked DrawIndexedPrimitive\n");

            // SetStreamSource (index 100)
            Detouring::Hook::Target target_stream(&vftable[100]);
            m_SetStreamSource_hook.Create(target_stream, SetStreamSource_detour);
            g_original_SetStreamSource = m_SetStreamSource_hook.GetTrampoline<SetStreamSource_t>();
            m_SetStreamSource_hook.Enable();
            Msg("[Shader Fixes] Hooked SetStreamSource\n");

            // SetVertexShader (index 92)
            Detouring::Hook::Target target_shader(&vftable[92]);
            m_SetVertexShader_hook.Create(target_shader, SetVertexShader_detour);
            g_original_SetVertexShader = m_SetVertexShader_hook.GetTrampoline<SetVertexShader_t>();
            m_SetVertexShader_hook.Enable();
            Msg("[Shader Fixes] Hooked SetVertexShader\n");

            // SetVertexShaderConstantF (index 94)
            Detouring::Hook::Target target_const(&vftable[94]);
            m_SetVertexShaderConstantF_hook.Create(target_const, SetVertexShaderConstantF_detour);
            g_original_SetVertexShaderConstantF = m_SetVertexShaderConstantF_hook.GetTrampoline<SetVertexShaderConstantF_t>();
            m_SetVertexShaderConstantF_hook.Enable();
            Msg("[Shader Fixes] Hooked SetVertexShaderConstantF\n");
        }
        catch (...) {
            Error("[Shader Fixes] Failed to hook one or more D3D9 functions\n");
            return;
        }

        // Hook ConMsg for console message interception
        void* conMsg = GetProcAddress(GetModuleHandle("tier0.dll"), "ConMsg");
        if (conMsg) {
            Detouring::Hook::Target target(conMsg);
            s_ConMsg_hook.Create(target, ConMsg_detour);
            g_original_ConMsg = s_ConMsg_hook.GetTrampoline<ConMsg_t>();
            s_ConMsg_hook.Enable();
            Msg("[Shader Fixes] Hooked ConMsg\n");
        } else {
            Warning("[Shader Fixes] Failed to hook ConMsg - console interception disabled\n");
        }

        Msg("[Shader Fixes] Enhanced shader protection initialized successfully\n");
    }
    catch (const std::exception& e) {
        Error("[Shader Fixes] Exception during initialization: %s\n", e.what());
    }
    catch (...) {
        Error("[Shader Fixes] Unknown exception during initialization\n");
    }
}

void __fastcall ShaderAPIHooks::ParticleRender_detour(void* thisptr) {
    static float s_lastLogTime = 0.0f;
    float currentTime = GetTickCount64() / 1000.0f;

    __try {
        s_state.isProcessingParticle = true;
        
        // Log every second at most
        if (currentTime - s_lastLogTime > 1.0f) {
            Msg("[Shader Fixes] Particle render called from %p\n", _ReturnAddress());
            s_lastLogTime = currentTime;
        }

        // Add pre-render checks
        if (thisptr) {
            __try {
                // Verify the vtable pointer
                if (!IsValidPointer(thisptr, sizeof(void*))) {
                    Warning("[Shader Fixes] Invalid particle system pointer\n");
                    return;
                }

                void** vtable = *reinterpret_cast<void***>(thisptr);
                if (vtable && IsValidPointer(vtable, sizeof(void*) * 3)) {
                    // Try to get particle system info safely
                    if (vtable[2] && IsValidPointer(vtable[2], sizeof(void*))) {
                        const char* name = reinterpret_cast<const char*>(vtable[2]);
                        Msg("[Shader Fixes] Processing particle system at %p, vtable: %p\n", 
                            thisptr, vtable);
                    }
                }
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception while accessing particle info at %p\n", thisptr);
            }
        }

        // Call original with exception handling
        if (g_original_ParticleRender) {
            __try {
                g_original_ParticleRender(thisptr);
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception in original particle render at %p\n", 
                    _ReturnAddress());
            }
        }
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Top-level exception in particle rendering\n");
    }

    s_state.isProcessingParticle = false;
}

bool ShaderAPIHooks::IsDeviceReady() {
    if (!g_pD3DDevice) return false;
    
    __try {
        D3DDEVICE_CREATION_PARAMETERS params;
        HRESULT hr = g_pD3DDevice->GetCreationParameters(&params);
        return SUCCEEDED(hr);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception checking D3D9 device state\n");
        return false;
    }
    return false;
}

void __fastcall ShaderAPIHooks::InitParamsEyes_detour(void* thisptr) {
    __try {
        if (!thisptr) {
            Warning("[Shader Fixes] InitParamsEyes called with null thisptr\n");
            return;
        }

        // Verify D3D device state before proceeding
        if (!IsDeviceReady()) {
            Warning("[Shader Fixes] D3D9 device not ready in InitParamsEyes\n");
            return;
        }

        // Call original with device state protection
        if (g_original_InitParamsEyes) {
            __try {
                g_original_InitParamsEyes(thisptr);
                Warning("[Shader Fixes] InitParamsEyes completed successfully\n");
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception in original InitParamsEyes\n");
            }
        }
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in InitParamsEyes_detour\n");
    }
}

bool __fastcall ShaderAPIHooks::InitEyes_detour(void* thisptr) {
    __try {
        if (!thisptr) {
            Warning("[Shader Fixes] InitEyes called with null thisptr\n");
            return false;
        }

        // Verify D3D device state before proceeding
        if (!IsDeviceReady()) {
            Warning("[Shader Fixes] D3D9 device not ready in InitEyes\n");
            return false;
        }

        // Call original with device state protection
        if (g_original_InitEyes) {
            __try {
                bool result = g_original_InitEyes(thisptr);
                Warning("[Shader Fixes] InitEyes completed with result: %d\n", result);
                return result;
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception in original InitEyes\n");
            }
        }
        return false;
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in InitEyes_detour\n");
        return false;
    }
}

void __fastcall ShaderAPIHooks::DrawEyes_detour(void* thisptr) {
    __try {
        if (!thisptr) {
            Warning("[Shader Fixes] DrawEyes called with null thisptr\n");
            return;
        }

        // Verify D3D device state before proceeding
        if (!IsDeviceReady()) {
            Warning("[Shader Fixes] D3D9 device not ready in DrawEyes\n");
            return;
        }

        // Call original with device state protection
        if (g_original_DrawEyes) {
            __try {
                g_original_DrawEyes(thisptr);
                Warning("[Shader Fixes] DrawEyes completed successfully\n");
            }
            __except(EXCEPTION_EXECUTE_HANDLER) {
                Warning("[Shader Fixes] Exception in original DrawEyes\n");
            }
        }
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in DrawEyes_detour\n");
    }
}

int __fastcall ShaderAPIHooks::DivisionFunction_detour(int a1, int a2, int dividend, int divisor) {
    void* returnAddress = _ReturnAddress();
    
    // Get stack pointer using intrinsic
    void* stackPointer = _AddressOfReturnAddress();

    // Log before attempting division
    Msg("[Shader Fixes] Division operation:\n"
        "  Return Address: %p\n"
        "  Stack Pointer: %p\n"
        "  Parameters: a1=%d, a2=%d, dividend=%d, divisor=%d\n",
        returnAddress, stackPointer, a1, a2, dividend, divisor);

    // Capture stack trace
    void* stackTrace[10] = {};
    USHORT frames = CaptureStackBackTrace(0, 10, stackTrace, nullptr);
    Msg("[Shader Fixes] Stack trace:\n");
    for (USHORT i = 0; i < frames; i++) {
        Msg("  %d: %p\n", i, stackTrace[i]);
    }

    // Add module information
    HMODULE modules[10] = {};
    DWORD needed = 0;
    if (EnumProcessModules(GetCurrentProcess(), modules, sizeof(modules), &needed)) {
        for (DWORD i = 0; i < (needed / sizeof(HMODULE)); i++) {
            char modName[MAX_PATH];
            if (GetModuleFileNameA(modules[i], modName, sizeof(modName))) {
                MODULEINFO modInfo;
                if (GetModuleInformation(GetCurrentProcess(), modules[i], &modInfo, sizeof(modInfo))) {
                    if (returnAddress >= modInfo.lpBaseOfDll && 
                        returnAddress < (void*)((char*)modInfo.lpBaseOfDll + modInfo.SizeOfImage)) {
                        Msg("  Module: %s Base: %p Size: %u\n", 
                            modName, modInfo.lpBaseOfDll, modInfo.SizeOfImage);
                    }
                }
            }
        }
    }

    __try {
        if (divisor == 0) {
            Warning("[Shader Fixes] Prevented division by zero! Caller: %p\n", returnAddress);
            return 1;
        }

        // Validate input ranges
        if (abs(dividend) > 1000000 || abs(divisor) < 1) {
            Warning("[Shader Fixes] Suspicious division values at %p\n", returnAddress);
            return dividend < 0 ? -1 : 1;
        }

        // Log the operation
        int result = dividend / divisor;
        Msg("[Shader Fixes] Division result: %d = %d / %d\n", result, dividend, divisor);
        
        return result;
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in division at %p\n", returnAddress);
        return 1;
    }
}

HRESULT __stdcall ShaderAPIHooks::VertexBufferLock_detour(
    void* thisptr,
    UINT offsetToLock,
    UINT sizeToLock,
    void** ppbData,
    DWORD flags) {
    
    __try {
        // Log the attempt
        Msg("[Shader Fixes] CVertexBuffer::Lock - Offset: %u, Size: %u\n", offsetToLock, sizeToLock);

        // Validate parameters before calling original
        if (!thisptr) {
            Warning("[Shader Fixes] CVertexBuffer::Lock failed - null vertex buffer\n");
            return E_FAIL;
        }

        // Check for division-prone calculations
        if (sizeToLock > 0 && offsetToLock > 0) {
            UINT divCheck = offsetToLock / sizeToLock;
            if (divCheck == 0) {
                Warning("[Shader Fixes] CVertexBuffer::Lock - Potential division by zero prevented\n");
                return E_FAIL;
            }
        }

        return g_original_VertexBufferLock(thisptr, offsetToLock, sizeToLock, ppbData, flags);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in CVertexBuffer::Lock at %p\n", _ReturnAddress());
        return E_FAIL;
    }
}

void ShaderAPIHooks::Shutdown() {
    // Remove VEH handlers first
    if (m_vehHandlerDivision) {
        if (RemoveVectoredExceptionHandler(m_vehHandlerDivision)) {
            Msg("[Shader Fixes] Successfully removed division-specific VEH\n");
        } else {
            Warning("[Shader Fixes] Failed to remove division-specific VEH\n");
        }
        m_vehHandlerDivision = nullptr;
    }

    if (m_vehHandle) {
        if (RemoveVectoredExceptionHandler(m_vehHandle)) {
            Msg("[Shader Fixes] Successfully removed general VEH\n");
        } else {
            Warning("[Shader Fixes] Failed to remove general VEH\n");
        }
        m_vehHandle = nullptr;
    }

    // Existing shutdown code
    m_DrawIndexedPrimitive_hook.Disable();
    m_SetVertexShaderConstantF_hook.Disable();
    m_SetStreamSource_hook.Disable();
    m_SetVertexShader_hook.Disable();
    s_ConMsg_hook.Disable();
    m_InitParamsEyes_hook.Disable();
    m_InitEyes_hook.Disable();
    m_DrawEyes_hook.Disable();
    
    // Log shutdown completion
    Msg("[Shader Fixes] Shutdown complete\n");
}

void __cdecl ShaderAPIHooks::ConMsg_detour(const char* fmt, ...) {
    char buffer[2048];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);

    // Check for shader/particle error messages
    if (strstr(buffer, "C_OP_RenderSprites") ||
        strstr(buffer, "shader") ||
        strstr(buffer, "particle") ||
        strstr(buffer, "material")) {
        
        s_state.lastErrorMessage = buffer;
        s_state.lastErrorTime = GetTickCount64() / 1000.0f;
        s_state.isProcessingParticle = true;

        // Extract material name if present
        std::regex materialRegex("Material ([^\\s]+)");
        std::smatch matches;
        std::string bufferStr(buffer);
        if (std::regex_search(bufferStr, matches, materialRegex)) {
            std::string materialName = matches[1].str();
            s_problematicMaterials.insert(materialName);
            Warning("[Shader Fixes] Added problematic material: %s\n", materialName.c_str());
        }
    }

    if (g_original_ConMsg) {
        g_original_ConMsg("%s", buffer);
    }
}

HRESULT __stdcall ShaderAPIHooks::DrawIndexedPrimitive_detour(
    IDirect3DDevice9* device,
    D3DPRIMITIVETYPE PrimitiveType,
    INT BaseVertexIndex,
    UINT MinVertexIndex,
    UINT NumVertices,
    UINT StartIndex,
    UINT PrimitiveCount) {
    
    __try {
        if (s_state.isProcessingParticle || IsParticleSystem()) {
            if (!ValidatePrimitiveParams(MinVertexIndex, NumVertices, PrimitiveCount)) {
                Warning("[Shader Fixes] Blocked invalid draw call for %s\n", 
                    s_state.lastMaterialName.c_str());
                return D3D_OK;
            }
        }

        return g_original_DrawIndexedPrimitive(
            device, PrimitiveType, BaseVertexIndex, MinVertexIndex,
            NumVertices, StartIndex, PrimitiveCount);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in DrawIndexedPrimitive for %s\n", 
            s_state.lastMaterialName.c_str());
        return D3D_OK;
    }
}

HRESULT __stdcall ShaderAPIHooks::SetVertexShaderConstantF_detour(
    IDirect3DDevice9* device,
    UINT StartRegister,
    CONST float* pConstantData,
    UINT Vector4fCount) {
    
    __try {
        if (s_state.isProcessingParticle || IsParticleSystem()) {
            if (!ValidateShaderConstants(pConstantData, Vector4fCount)) {
                Warning("[Shader Fixes] Blocked invalid shader constants for %s\n",
                    s_state.lastMaterialName.c_str());
                return D3D_OK;
            }
        }

        return g_original_SetVertexShaderConstantF(
            device, StartRegister, pConstantData, Vector4fCount);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in SetVertexShaderConstantF\n");
        return D3D_OK;
    }
}

HRESULT __stdcall ShaderAPIHooks::SetStreamSource_detour(
    IDirect3DDevice9* device,
    UINT StreamNumber,
    IDirect3DVertexBuffer9* pStreamData,
    UINT OffsetInBytes,
    UINT Stride) {
    
    __try {
        if (s_state.isProcessingParticle || IsParticleSystem()) {
            if (pStreamData && !ValidateParticleVertexBuffer(pStreamData, Stride)) {
                Warning("[Shader Fixes] Blocked invalid vertex buffer for %s\n",
                    s_state.lastMaterialName.c_str());
                return D3D_OK;
            }
        }

        return g_original_SetStreamSource(device, StreamNumber, pStreamData, OffsetInBytes, Stride);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in SetStreamSource\n");
        return D3D_OK;
    }
}

HRESULT __stdcall ShaderAPIHooks::SetVertexShader_detour(
    IDirect3DDevice9* device,
    IDirect3DVertexShader9* pShader) {
    
    __try {
        if (s_state.isProcessingParticle || IsParticleSystem()) {
            if (!ValidateVertexShader(pShader)) {
                Warning("[Shader Fixes] Blocked invalid vertex shader for %s\n",
                    s_state.lastMaterialName.c_str());
                return D3D_OK;
            }
        }

        return g_original_SetVertexShader(device, pShader);
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Warning("[Shader Fixes] Exception in SetVertexShader\n");
        return D3D_OK;
    }
}

bool ShaderAPIHooks::ValidateVertexBuffer(
    IDirect3DVertexBuffer9* pVertexBuffer,
    UINT offsetInBytes,
    UINT stride) {
    
    if (!pVertexBuffer) return false;

    D3DVERTEXBUFFER_DESC desc;
    if (FAILED(pVertexBuffer->GetDesc(&desc))) return false;

    // Check for potentially dangerous calculations
    if (stride == 0) {
        Warning("[Shader Fixes] Zero stride detected in vertex buffer\n");
        return false;
    }

    if (offsetInBytes >= desc.Size) {
        Warning("[Shader Fixes] Offset (%u) exceeds buffer size (%u)\n", offsetInBytes, desc.Size);
        return false;
    }

    // Check division safety
    if (desc.Size > 0 && stride > 0) {
        UINT vertexCount = desc.Size / stride;
        if (vertexCount == 0) {
            Warning("[Shader Fixes] Invalid vertex count calculation prevented\n");
            return false;
        }
    }

    void* data;
    if (SUCCEEDED(pVertexBuffer->Lock(offsetInBytes, stride, &data, D3DLOCK_READONLY))) {
        bool valid = true;
        float* floatData = static_cast<float*>(data);
        
        try {
            for (UINT i = 0; i < stride/sizeof(float); i++) {
                // Log suspicious values
                if (!_finite(floatData[i]) || _isnan(floatData[i])) {
                    Warning("[Shader Fixes] Invalid float at offset %u: %f (addr: %p)\n", 
                        i * sizeof(float), floatData[i], &floatData[i]);
                    valid = false;
                    break;
                }
            }
        }
        catch (...) {
            Warning("[Shader Fixes] Exception during vertex buffer validation\n");
            valid = false;
        }
        
        pVertexBuffer->Unlock();
        return valid;
    }

    return false;
}

bool ShaderAPIHooks::ValidateParticleVertexBuffer(IDirect3DVertexBuffer9* pVertexBuffer, UINT stride) {
    if (!pVertexBuffer) return false;

    D3DVERTEXBUFFER_DESC desc;
    if (FAILED(pVertexBuffer->GetDesc(&desc))) return false;

    void* data;
    if (SUCCEEDED(pVertexBuffer->Lock(0, desc.Size, &data, D3DLOCK_READONLY))) {
        bool valid = true;
        float* floatData = static_cast<float*>(data);
        
        // Enhanced validation for particle data
        for (UINT i = 0; i < desc.Size / sizeof(float); i++) {
            // Check for invalid values
            if (!_finite(floatData[i]) || _isnan(floatData[i])) {
                Warning("[Shader Fixes] Invalid float detected at index %d: %f\n", i, floatData[i]);
                valid = false;
                break;
            }
            // Check for unreasonable values
            if (fabsf(floatData[i]) > 1e6) {
                Warning("[Shader Fixes] Unreasonable value detected at index %d: %f\n", i, floatData[i]);
                valid = false;
                break;
            }
            // Check for potential divide by zero
            if (fabsf(floatData[i]) < 1e-6) {
                Warning("[Shader Fixes] Near-zero value detected at index %d: %f\n", i, floatData[i]);
                valid = false;
                break;
            }
        }
        
        pVertexBuffer->Unlock();
        return valid;
    }

    return false;
}

bool ShaderAPIHooks::ValidateShaderConstants(const float* pConstantData, UINT Vector4fCount) {
    if (!pConstantData || Vector4fCount == 0) return false;

    for (UINT i = 0; i < Vector4fCount * 4; i++) {
        // Check for invalid values
        if (!_finite(pConstantData[i]) || _isnan(pConstantData[i])) {
            Warning("[Shader Fixes] Invalid shader constant at index %d: %f\n", i, pConstantData[i]);
            return false;
        }
        // Check for values that might cause divide by zero
        if (fabsf(pConstantData[i]) < 1e-6) {
            Warning("[Shader Fixes] Near-zero shader constant at index %d: %f\n", i, pConstantData[i]);
            return false;
        }
    }

    return true;
}

bool ShaderAPIHooks::ValidatePrimitiveParams(
    UINT MinVertexIndex,
    UINT NumVertices,
    UINT PrimitiveCount) {
    
    if (NumVertices == 0 || PrimitiveCount == 0) {
        Warning("[Shader Fixes] Zero vertices or primitives\n");
        return false;
    }
    if (MinVertexIndex >= NumVertices) {
        Warning("[Shader Fixes] MinVertexIndex (%d) >= NumVertices (%d)\n", 
            MinVertexIndex, NumVertices);
        return false;
    }

    // Additional checks for particle system primitives
    if (PrimitiveCount > 10000) {
        Warning("[Shader Fixes] Excessive primitive count: %d\n", PrimitiveCount);
        return false;
    }

    return true;
}

bool ShaderAPIHooks::ValidateVertexShader(IDirect3DVertexShader9* pShader) {
    if (!pShader) return false;

    // Basic shader validation
    UINT functionSize = 0;
    if (FAILED(pShader->GetFunction(nullptr, &functionSize)) || functionSize == 0) {
        Warning("[Shader Fixes] Invalid shader function size\n");
        return false;
    }

    // Additional validation could be added here
    return true;
}

bool ShaderAPIHooks::IsParticleSystem() {
    try {
        if (!materials) return false;

        IMatRenderContext* renderContext = materials->GetRenderContext();
        if (!renderContext) return false;

        IMaterial* currentMaterial = renderContext->GetCurrentMaterial();
        if (!currentMaterial) return false;

        const char* materialName = currentMaterial->GetName();
        const char* shaderName = currentMaterial->GetShaderName();

        UpdateShaderState(materialName, shaderName);

        // Check if we're within the error window
        float currentTime = GetTickCount64() / 1000.0f;
        if (currentTime - s_state.lastErrorTime < 0.1f) {
            return true;
        }

        // Check against known problematic materials
        if (materialName && s_problematicMaterials.find(materialName) != s_problematicMaterials.end()) {
            return true;
        }

        // Check shader name against known problematic patterns
        if (shaderName && IsKnownProblematicShader(shaderName)) {
            return true;
        }

        // Check blend states using global D3D device
        if (g_pD3DDevice) {
            DWORD srcBlend, destBlend, zEnable;
            g_pD3DDevice->GetRenderState(D3DRS_SRCBLEND, &srcBlend);
            g_pD3DDevice->GetRenderState(D3DRS_DESTBLEND, &destBlend);
            g_pD3DDevice->GetRenderState(D3DRS_ZENABLE, &zEnable);

            if ((srcBlend == D3DBLEND_SRCALPHA && destBlend == D3DBLEND_INVSRCALPHA) ||
                (srcBlend == D3DBLEND_ONE && destBlend == D3DBLEND_ONE) ||
                zEnable == D3DZB_FALSE) {
                return true;
            }
        }
    }
    catch (...) {
        Warning("[Shader Fixes] Exception in IsParticleSystem\n");
    }
    
    return false;
}

void ShaderAPIHooks::UpdateShaderState(const char* materialName, const char* shaderName) {
    if (materialName) {
        s_state.lastMaterialName = materialName;
    }
    if (shaderName) {
        s_state.lastShaderName = shaderName;
    }
}

bool ShaderAPIHooks::IsKnownProblematicShader(const char* name) {
    if (!name) return false;

    for (const auto& pattern : s_knownProblematicShaders) {
        if (strstr(name, pattern.c_str())) {
            return true;
        }
    }
    return false;
}

void ShaderAPIHooks::AddProblematicShader(const char* name) {
    if (name) {
        s_knownProblematicShaders.insert(name);
        Warning("[Shader Fixes] Added problematic shader: %s\n", name);
    }
}

void ShaderAPIHooks::LogShaderError(const char* format, ...) {
    static float lastLogTime = 0.0f;
    float currentTime = GetTickCount64() / 1000.0f;

    if (currentTime - lastLogTime < 1.0f) return;
    lastLogTime = currentTime;

    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    Warning("[Shader Fixes] %s", buffer);
}