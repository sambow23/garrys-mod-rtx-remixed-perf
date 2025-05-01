#pragma once
#include <Windows.h>
#include <d3d9.h>
#include <tier0/dbg.h>
#include <unordered_set>
#include <string>
#include <vector>

// Forward declarations
class IShaderAPI;

class ShaderAPIHooks {
public:
    static ShaderAPIHooks& Instance() {
        static ShaderAPIHooks instance;
        return instance;
    }

    void Initialize();
    void Shutdown();
    void RegisterKnownCrashAddress(void* address);
    void TestExceptionHandler() {
    // Deliberately cause an access violation to test the handler
    Msg("[RTXF2 - Shader Fixes] Testing exception handler with deliberate access violation...\n");
    
    __try {
        void* nullPtr = nullptr;
        *reinterpret_cast<int*>(nullPtr) = 1;  // This will cause an access violation
    }
    __except(EXCEPTION_EXECUTE_HANDLER) {
        Msg("[RTXF2 - Shader Fixes] SEH caught the test exception as expected\n");
    }
    
    Msg("[RTXF2 - Shader Fixes] If you see this, the VEH might not be working properly\n");
}

private:
    ShaderAPIHooks() = default;
    ~ShaderAPIHooks() = default;

    // Pattern-based crash detection
    struct CodePattern {
        std::string name;           // Description of the pattern
        std::string signature;      // Byte pattern in hex (e.g., "48 8B 01 FF 50 88")
        int crashOffsetFromMatch;   // Offset from start of pattern to crash instruction
        int instructionLength;      // Length of the crash instruction
        bool skipInstruction;       // Whether to skip the instruction or just fix registers
    };

    // Tracking and pattern scanning
    static std::vector<CodePattern> s_crashPatterns;
    static std::unordered_set<uintptr_t> s_problematicAddresses;
    
    // Helper methods
    static void TrackProblematicAddress(void* address);
    static void InitializeCrashPatterns();
    static std::vector<void*> FindPatternAddresses(HMODULE module, const char* bytePattern);
    static bool IsValidPointer(const void* ptr, size_t size);
    
    // VEH handlers
    PVOID m_vehHandle;
    PVOID m_vehHandlerDivision;
};