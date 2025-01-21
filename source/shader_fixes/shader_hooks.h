#pragma once
#include "../e_utils.h"
#include <tier0/dbg.h>
#include <materialsystem/imaterialsystem.h>
#include <materialsystem/imaterial.h>
#include <materialsystem/imaterialvar.h>
#include <shaderapi/ishaderapi.h>
#include <Windows.h>
#include <d3d9.h>
#include <unordered_set>
#include <string>
#include <regex>
#include <dbghelp.h>
#pragma comment(lib, "dbghelp.lib")

// Forward declare the shader API interface
class IShaderAPI;

extern IShaderAPI* g_pShaderAPI;
extern IDirect3DDevice9* g_pD3DDevice;

class ShaderAPIHooks {
public:
    static ShaderAPIHooks& Instance() {
        static ShaderAPIHooks instance;
        return instance;
    }

    void Initialize();
    void Shutdown();
    void EnableCustomSkyboxRendering();
    void DisableCustomSkyboxRendering();

private:
    ShaderAPIHooks() = default;
    ~ShaderAPIHooks() = default;

    // Tracking structure for shader state
    struct ShaderState {
        std::string lastMaterialName;
        std::string lastShaderName;
        std::string lastErrorMessage;
        float lastErrorTime = 0.0f;
        bool isProcessingParticle = false;
    };

    // Static members for state tracking
    static ShaderState s_state;
    static std::unordered_set<std::string> s_knownProblematicShaders;
    static std::unordered_set<std::string> s_problematicMaterials;

    // Console message hook
    static Detouring::Hook s_ConMsg_hook;
    static void __cdecl ConMsg_detour(const char* fmt, ...);
    typedef void(__cdecl* ConMsg_t)(const char* fmt, ...);
    static ConMsg_t g_original_ConMsg;

    // D3D9 hooks
    static HRESULT __stdcall DrawIndexedPrimitive_detour(
        IDirect3DDevice9* device,
        D3DPRIMITIVETYPE PrimitiveType,
        INT BaseVertexIndex,
        UINT MinVertexIndex,
        UINT NumVertices,
        UINT StartIndex,
        UINT PrimitiveCount);

    static HRESULT __stdcall SetVertexShaderConstantF_detour(
        IDirect3DDevice9* device,
        UINT StartRegister,
        CONST float* pConstantData,
        UINT Vector4fCount);

    static HRESULT __stdcall SetStreamSource_detour(
        IDirect3DDevice9* device,
        UINT StreamNumber,
        IDirect3DVertexBuffer9* pStreamData,
        UINT OffsetInBytes,
        UINT Stride);

    static HRESULT __stdcall SetVertexShader_detour(
        IDirect3DDevice9* device,
        IDirect3DVertexShader9* pShader);

    // Validation helpers
    static bool ValidateVertexBuffer(IDirect3DVertexBuffer9* pVertexBuffer, UINT offsetInBytes, UINT stride);
    static bool ValidateParticleVertexBuffer(IDirect3DVertexBuffer9* pVertexBuffer, UINT stride);
    static bool ValidateShaderConstants(const float* pConstantData, UINT Vector4fCount);
    static bool ValidatePrimitiveParams(UINT MinVertexIndex, UINT NumVertices, UINT PrimitiveCount);
    static bool ValidateVertexShader(IDirect3DVertexShader9* pShader);
    static bool IsParticleSystem();
    static void LogShaderError(const char* format, ...);

    // State management
    static void UpdateShaderState(const char* materialName, const char* shaderName);
    static bool IsKnownProblematicShader(const char* name);
    static void AddProblematicShader(const char* name);

    // Hook objects
    Detouring::Hook m_DrawIndexedPrimitive_hook;
    Detouring::Hook m_SetVertexShaderConstantF_hook;
    Detouring::Hook m_SetStreamSource_hook;
    Detouring::Hook m_SetVertexShader_hook;

    // Function pointer types
    typedef HRESULT(__stdcall* DrawIndexedPrimitive_t)(
        IDirect3DDevice9*, D3DPRIMITIVETYPE, INT, UINT, UINT, UINT, UINT);
    typedef HRESULT(__stdcall* SetVertexShaderConstantF_t)(
        IDirect3DDevice9*, UINT, CONST float*, UINT);
    typedef HRESULT(__stdcall* SetStreamSource_t)(
        IDirect3DDevice9*, UINT, IDirect3DVertexBuffer9*, UINT, UINT);
    typedef HRESULT(__stdcall* SetVertexShader_t)(
        IDirect3DDevice9*, IDirect3DVertexShader9*);

    // Original function pointers
    static DrawIndexedPrimitive_t g_original_DrawIndexedPrimitive;
    static SetVertexShaderConstantF_t g_original_SetVertexShaderConstantF;
    static SetStreamSource_t g_original_SetStreamSource;
    static SetVertexShader_t g_original_SetVertexShader;

    // Add new hook declarations
    Detouring::Hook m_VertexBufferLock_hook;
    typedef HRESULT(__stdcall* VertexBufferLock_t)(void*, UINT, UINT, void**, DWORD);
    static VertexBufferLock_t g_original_VertexBufferLock;
    static HRESULT __stdcall VertexBufferLock_detour(void* thisptr, UINT offsetToLock, UINT sizeToLock, void** ppbData, DWORD flags);

    // Add helper for tracking problematic addresses
    static std::unordered_set<uintptr_t> s_problematicAddresses;
    static void TrackProblematicAddress(void* address);

    // Division function hook
    Detouring::Hook m_DivisionFunction_hook;
    typedef int (__fastcall* DivisionFunction_t)(int a1, int a2, int dividend, int divisor);
    static DivisionFunction_t g_original_DivisionFunction;
    static int __fastcall DivisionFunction_detour(int a1, int a2, int dividend, int divisor);

    // Add particle render hook
    Detouring::Hook m_ParticleRender_hook;
    typedef void (__fastcall* ParticleRender_t)(void* thisptr);
    static ParticleRender_t g_original_ParticleRender;
    static void __fastcall ParticleRender_detour(void* thisptr);

    // Skybox
    Detouring::Hook m_R_DrawSkyBox_hook;
    static void __fastcall R_DrawSkyBox_detour(void* thisptr, void* edx);
    typedef void(__fastcall* R_DrawSkyBox_t)(void* thisptr);
    static R_DrawSkyBox_t g_original_R_DrawSkyBox;

    // Add VEH handle storage
    PVOID m_vehHandle;
    PVOID m_vehHandlerDivision;
};