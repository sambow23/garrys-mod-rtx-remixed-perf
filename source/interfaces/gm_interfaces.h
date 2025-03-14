#pragma once

#include <Windows.h>
#include <string>

// Forward declarations for interfaces we don't include directly
class CHLClient;
class CEngineClient;
class ClientEntityList;
class ISurface;
class IVModelRender;
class IEngineTrace;
class CLuaShared;
class IPhysicsSurfaceProps;
class ICvar;
class IMaterialSystem;
class IShaderAPI;
class IMaterial;

namespace Interfaces
{
    // Interface pointers
    extern IMaterialSystem* g_pMaterialSystem;
    extern IShaderAPI* g_pShaderAPI;
    extern CHLClient* g_pClient;
    extern CEngineClient* g_pEngine;
    extern ClientEntityList* g_pEntityList;
    extern ISurface* g_pSurface;
    extern IVModelRender* g_pModelRender;
    extern IEngineTrace* g_pEngineTrace;
    extern CLuaShared* g_pLuaShared;
    extern IPhysicsSurfaceProps* g_pPhysicsSurfaceProps;
    extern ICvar* g_pCvar;
    
    // Core functions
    void* GetInterface(const char* moduleName, const char* interfaceName);
    bool Initialize();
    
    // Debug helpers
    void PrintInterfaces();
    
    // Interface tests
    void TestMaterialSystem();
    void TestShaderAPI();
    void TestEngineClient();
    void TestCvar();
    //void TestSurface();
    void RunInterfaceTests();

    // Material modification utilities
    bool ReplaceSpriteCardWithUnlitGeneric();
    IMaterial* FindMaterial(const char* materialName, bool complain = true);
    void SetMaterialShader(IMaterial* material, const char* shaderName);
    bool IsSpriteCardMaterial(IMaterial* material);
}