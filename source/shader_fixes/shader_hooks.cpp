#ifdef _WIN64
#include "shader_hooks.h"
#include <psapi.h>
#pragma comment(lib, "psapi.lib")

// Initialize static members
std::unordered_set<uintptr_t> ShaderAPIHooks::s_problematicAddresses;
std::vector<ShaderAPIHooks::CodePattern> ShaderAPIHooks::s_crashPatterns;

bool ShaderAPIHooks::IsValidPointer(const void* ptr, size_t size) {
    if (!ptr) return false;
    MEMORY_BASIC_INFORMATION mbi = { 0 };
    if (VirtualQuery(ptr, &mbi, sizeof(mbi)) == 0) return false;
    if (mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) return false;
    if (!(mbi.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE))) return false;
    return true;
}

void ShaderAPIHooks::InitializeCrashPatterns() {
    s_crashPatterns.clear();
    
    // Add multiple patterns to increase chances of finding the problematic code
    
    // Pattern 1: Exact sequence at the crash location
    s_crashPatterns.push_back({
        "Exact vtable dereferencing crash pattern",
        "F6 03 02 74 ?? 48 8B 0E 48 8B 01", // test byte ptr [rbx],2; je XX; mov rcx,[rsi]; mov rax,[rcx]
        8, // Offset to mov rax,[rcx]
        3,
        true
    });
    
    // Pattern 2: More generic version with wildcards
    s_crashPatterns.push_back({
        "Generic vtable dereference pattern",
        "48 8B 0E 48 8B 01", // mov rcx,[rsi]; mov rax,[rcx]
        3, // Offset to mov rax,[rcx]
        3, 
        true
    });
    
    // Pattern 3: Focus on the test+jump sequence that precedes the crash
    s_crashPatterns.push_back({
        "Conditional jump before crash",
        "F6 ?? 02 74 ?? 48 8B ?? 48 8B 01", // test X,2; je XX; mov reg,[reg]; mov rax,[rcx]
        9, // Approximate offset to mov rax,[rcx]
        3,
        true
    });
}

std::vector<void*> ShaderAPIHooks::FindPatternAddresses(HMODULE module, const char* bytePattern) {
    std::vector<void*> results;
    
    if (!module) return results;
    
    // Get module information
    MODULEINFO moduleInfo;
    if (!GetModuleInformation(GetCurrentProcess(), module, &moduleInfo, sizeof(moduleInfo))) {
        return results;
    }
    
    // Convert pattern string to bytes
    std::vector<std::pair<BYTE, bool>> pattern;
    const char* ptr = bytePattern;
    while (*ptr) {
        if (*ptr == ' ') {
            ptr++;
            continue;
        }
        
        if (*ptr == '?') {
            pattern.push_back({0, false}); // Wildcard
            ptr += 2;
            continue;
        }
        
        char byteStr[3] = {ptr[0], ptr[1], 0};
        BYTE byte = static_cast<BYTE>(strtol(byteStr, nullptr, 16));
        pattern.push_back({byte, true});
        ptr += 2;
    }
    
    // Scan memory
    BYTE* start = reinterpret_cast<BYTE*>(moduleInfo.lpBaseOfDll);
    BYTE* end = start + moduleInfo.SizeOfImage - pattern.size();
    
    for (BYTE* current = start; current < end; ++current) {
        bool found = true;
        
        for (size_t i = 0; i < pattern.size(); ++i) {
            if (pattern[i].second && current[i] != pattern[i].first) {
                found = false;
                break;
            }
        }
        
        if (found) {
            results.push_back(current);
        }
    }
    
    return results;
}

void ShaderAPIHooks::TrackProblematicAddress(void* address) {
    uintptr_t addr = reinterpret_cast<uintptr_t>(address);
    s_problematicAddresses.insert(addr);
    Msg("[RTX Remix Fixes 2 - Shader Fixes] Added problematic address: %p\n", address);
}

void ShaderAPIHooks::RegisterKnownCrashAddress(void* address) {
    TrackProblematicAddress(address);
}

void ShaderAPIHooks::Initialize() {
    try {
        m_vehHandle = nullptr;
        m_vehHandlerDivision = nullptr;

        // Install division by zero handler
        m_vehHandlerDivision = AddVectoredExceptionHandler(0, [](PEXCEPTION_POINTERS exceptionInfo) -> LONG {
            if (exceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_INT_DIVIDE_BY_ZERO) {
                void* crashAddress = exceptionInfo->ExceptionRecord->ExceptionAddress;
                
                // Get module information
                HMODULE hModule = NULL;
                if (GetModuleHandleEx(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                    (LPCTSTR)crashAddress, &hModule)) {
                    char moduleName[MAX_PATH];
                    GetModuleFileNameA(hModule, moduleName, sizeof(moduleName));
                    Warning("[RTX Remix Fixes 2 - Shader Fixes] Division by zero in module: %s\n", moduleName);
                }

                // Log crash details
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Division crash details:\n");
                Warning("  Address: %p\n", crashAddress);
                Warning("  Thread ID: %u\n", GetCurrentThreadId());
                
                // Stack trace
                void* stack[32];
                WORD frames = CaptureStackBackTrace(0, 32, stack, NULL);
                Warning("  Stack trace (%d frames):\n", frames);
                for (WORD i = 0; i < frames; i++) {
                    Warning("    %d: %p\n", i, stack[i]);
                }

                // Fix and continue
                exceptionInfo->ContextRecord->Rax = 1;
                exceptionInfo->ContextRecord->Rip += 2;
                return EXCEPTION_CONTINUE_EXECUTION;
            }
            return EXCEPTION_CONTINUE_SEARCH;
        });

        // Initialize pattern-based crash detection
        InitializeCrashPatterns();

        // Install access violation handler
        m_vehHandle = AddVectoredExceptionHandler(1, [](PEXCEPTION_POINTERS exceptionInfo) -> LONG {
            // Handle division by zero
            if (exceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_INT_DIVIDE_BY_ZERO) {
                void* crashAddress = exceptionInfo->ExceptionRecord->ExceptionAddress;
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Caught division by zero at %p\n", crashAddress);
                
                // Log register state
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Register state:\n");
                Warning("  RAX: %016llX\n", exceptionInfo->ContextRecord->Rax);
                Warning("  RCX: %016llX\n", exceptionInfo->ContextRecord->Rcx);
                Warning("  RDX: %016llX\n", exceptionInfo->ContextRecord->Rdx);
                Warning("  R8:  %016llX\n", exceptionInfo->ContextRecord->R8);
                Warning("  R9:  %016llX\n", exceptionInfo->ContextRecord->R9);
                Warning("  RIP: %016llX\n", exceptionInfo->ContextRecord->Rip);

                // Fix and continue
                exceptionInfo->ContextRecord->Rax = 1;
                exceptionInfo->ContextRecord->Rip += 2;
                return EXCEPTION_CONTINUE_EXECUTION;
            }

            // Handle access violations
            if (exceptionInfo->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION) {
                void* crashAddress = exceptionInfo->ExceptionRecord->ExceptionAddress;
                uintptr_t addr = reinterpret_cast<uintptr_t>(crashAddress);
                
                // First check our pattern database
                bool isKnown = false;
                if (ShaderAPIHooks::s_problematicAddresses.find(addr) != 
                    ShaderAPIHooks::s_problematicAddresses.end()) {
                    isKnown = true;
                }
                
                // If not found, do a real-time instruction analysis
                if (!isKnown) {
                    // Look for the specific "mov rax,[rcx]" instruction (48 8B 01)
                    // This is a defensive approach that works even if pattern matching failed
                    BYTE* bytes = reinterpret_cast<BYTE*>(crashAddress);
                    if (IsValidPointer(bytes, 3) && 
                        bytes[0] == 0x48 && bytes[1] == 0x8B && bytes[2] == 0x01) {
                        
                        Warning("[RTX Remix Fixes 2 - Shader Fixes] Detected 'mov rax,[rcx]' instruction at crash address %p\n", 
                            crashAddress);
                        isKnown = true;
                        
                        // Add it to our database for future reference
                        s_problematicAddresses.insert(addr);
                    }
                }
                
                if (isKnown) {
                    Warning("[RTX Remix Fixes 2 - Shader Fixes] Handling known access violation at %p\n", crashAddress);
                    Warning("[RTX Remix Fixes 2 - Shader Fixes] RCX=%016llX is invalid\n", exceptionInfo->ContextRecord->Rcx);
                    
                    // Fix RCX and RAX to avoid future problems
                    exceptionInfo->ContextRecord->Rax = 0;
                    
                    // Skip the faulting instruction (3 bytes for "mov rax,[rcx]")
                    exceptionInfo->ContextRecord->Rip += 3;
                    
                    return EXCEPTION_CONTINUE_EXECUTION;
                }
                
                // Unknown access violation - log details
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Unhandled access violation at %p\n", crashAddress);
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Type: %s, Address: %p\n", 
                    exceptionInfo->ExceptionRecord->ExceptionInformation[0] ? "Write" : "Read",
                    (void*)exceptionInfo->ExceptionRecord->ExceptionInformation[1]);
                
                // Dump register state
                Warning("[RTX Remix Fixes 2 - Shader Fixes] Register state:\n");
                Warning("  RAX: %016llX\n", exceptionInfo->ContextRecord->Rax);
                Warning("  RCX: %016llX\n", exceptionInfo->ContextRecord->Rcx);
                Warning("  RDX: %016llX\n", exceptionInfo->ContextRecord->Rdx);
                Warning("  RSI: %016llX\n", exceptionInfo->ContextRecord->Rsi);
                Warning("  RDI: %016llX\n", exceptionInfo->ContextRecord->Rdi);
                Warning("  RIP: %016llX\n", exceptionInfo->ContextRecord->Rip);
                
                // Stack trace
                void* stack[32];
                WORD frames = CaptureStackBackTrace(0, 32, stack, NULL);
                Warning("  Stack trace (%d frames):\n", frames);
                for (WORD i = 0; i < frames; i++) {
                    Warning("    %d: %p\n", i, stack[i]);
                }
            }
            
            return EXCEPTION_CONTINUE_SEARCH;
        });

        // Get shaderapidx9.dll module
        HMODULE shaderapidx9 = GetModuleHandle("shaderapidx9.dll");
        if (shaderapidx9) {
            Msg("[RTX Remix Fixes 2 - Shader Fixes] Scanning for known crash patterns in shaderapidx9.dll\n");
            
            // Scan for each pattern
            for (const auto& pattern : s_crashPatterns) {
                auto matches = FindPatternAddresses(shaderapidx9, pattern.signature.c_str());
                
                Msg("[RTX Remix Fixes 2 - Shader Fixes] Found %zu matches for pattern: %s\n", 
                    matches.size(), pattern.name.c_str());

                Msg("[RTX Remix Fixes 2 - Shader Fixes] Found %zu problematic addresses\n", s_problematicAddresses.size());
                for (uintptr_t addr : s_problematicAddresses) {
                    Msg("  - %p\n", reinterpret_cast<void*>(addr));
                    
                    // Dump 16 bytes at this address
                    void* ptr = reinterpret_cast<void*>(addr);
                    if (IsValidPointer(ptr, 16)) {
                        BYTE* bytes = reinterpret_cast<BYTE*>(ptr);
                        Msg("    Bytes: ");
                        for (int i = 0; i < 16; i++) {
                            Msg("%02X ", bytes[i]);
                        }
                        Msg("\n");
                    }
                }
                
                // Register each match
                for (void* matchAddr : matches) {
                    // Calculate the actual crash address
                    void* crashAddr = (char*)matchAddr + pattern.crashOffsetFromMatch;
                    
                    // Store address for use in exception handler
                    TrackProblematicAddress(crashAddr);
                    
                    // Print the address we're protecting
                    Msg("[RTX Remix Fixes 2 - Shader Fixes] Protected address: %p (pattern: %s)\n", 
                        crashAddr, pattern.name.c_str());
                    
                    // Dump bytes around for verification
                    BYTE* bytes = reinterpret_cast<BYTE*>(crashAddr);
                    Msg("[RTX Remix Fixes 2 - Shader Fixes] Bytes at %p: ", crashAddr);
                    for (int i = -4; i < 8; i++) {
                        Msg("%02X ", bytes[i]);
                    }
                    Msg("\n");
                }
            }
        }

        Msg("[RTX Remix Fixes 2 - Shader Fixes] Enhanced shader protection initialized successfully\n");
    }
    catch (const std::exception& e) {
        Error("[RTX Remix Fixes 2 - Shader Fixes] Exception during initialization: %s\n", e.what());
    }
    catch (...) {
        Error("[RTX Remix Fixes 2 - Shader Fixes] Unknown exception during initialization\n");
    }
    #ifdef _DEBUG
    TestExceptionHandler();
    #endif
}

void ShaderAPIHooks::Shutdown() {
    // Remove VEH handlers
    if (m_vehHandlerDivision) {
        RemoveVectoredExceptionHandler(m_vehHandlerDivision);
        m_vehHandlerDivision = nullptr;
    }

    if (m_vehHandle) {
        RemoveVectoredExceptionHandler(m_vehHandle);
        m_vehHandle = nullptr;
    }

    Msg("[RTX Remix Fixes 2 - Shader Fixes] Shader protection shutdown complete\n");
}

#endif