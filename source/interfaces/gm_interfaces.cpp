#include "gm_interfaces.h"
#include "GarrysMod/Lua/Interface.h"
#include <stdio.h>
#include "e_utils.h"

#include "materialsystem/imaterialsystem.h"
#include "materialsystem/imaterial.h"  // For IMaterial
#include "shaderapi/ishaderapi.h"
#include "cdll_int.h"                  // For CEngineClient
#include "vgui/ISurface.h"

// Interface pointers initialization
IMaterialSystem* Interfaces::g_pMaterialSystem = nullptr;
IShaderAPI* Interfaces::g_pShaderAPI = nullptr;
CHLClient* Interfaces::g_pClient = nullptr;
CEngineClient* Interfaces::g_pEngine = nullptr;
ClientEntityList* Interfaces::g_pEntityList = nullptr;
ISurface* Interfaces::g_pSurface = nullptr;
IVModelRender* Interfaces::g_pModelRender = nullptr; 
IEngineTrace* Interfaces::g_pEngineTrace = nullptr;
CLuaShared* Interfaces::g_pLuaShared = nullptr;
IPhysicsSurfaceProps* Interfaces::g_pPhysicsSurfaceProps = nullptr;
ICvar* Interfaces::g_pCvar = nullptr;

namespace Interfaces {

    // Function to dynamically load interfaces
    typedef void* (*CreateInterfaceFn)(const char* pName, int* pReturnCode);

    void* Interfaces::GetInterface(const char* moduleName, const char* interfaceName)
    {
        CreateInterfaceFn createInterface = (CreateInterfaceFn)GetProcAddress(GetModuleHandleA(moduleName), "CreateInterface");
        if (!createInterface) {
            Error("[Interfaces] Failed to find CreateInterface in %s\n", moduleName);
            return nullptr;
        }
        
        void* result = createInterface(interfaceName, nullptr);
        if (!result) {
            Error("[Interfaces] Failed to get interface %s from %s\n", interfaceName, moduleName);
            return nullptr;
        }
        
        return result;
    }

    bool Interfaces::Initialize()
    {
        Msg("[Interfaces] Initializing interfaces...\n");
        
        // Core interfaces - with immediate feedback
        if ((g_pMaterialSystem = (IMaterialSystem*)GetInterface("materialsystem.dll", "VMaterialSystem080")))
            Msg("[Interfaces] Found IMaterialSystem:      0x%p\n", g_pMaterialSystem);
        
        if ((g_pShaderAPI = (IShaderAPI*)GetInterface("shaderapidx9.dll", "ShaderApi030")))
            Msg("[Interfaces] Found IShaderAPI:           0x%p\n", g_pShaderAPI);
        
        if ((g_pClient = (CHLClient*)GetInterface("client.dll", "VClient017")))
            Msg("[Interfaces] Found CHLClient:            0x%p\n", g_pClient);
        
        if ((g_pEngine = (CEngineClient*)GetInterface("engine.dll", "VEngineClient015")))
            Msg("[Interfaces] Found CEngineClient:        0x%p\n", g_pEngine);
        
        if ((g_pEntityList = (ClientEntityList*)GetInterface("client.dll", "VClientEntityList003")))
            Msg("[Interfaces] Found ClientEntityList:     0x%p\n", g_pEntityList);
        
        if ((g_pSurface = (ISurface*)GetInterface("vguimatsurface.dll", "VGUI_Surface030")))
            Msg("[Interfaces] Found ISurface:             0x%p\n", g_pSurface);
        
        if ((g_pModelRender = (IVModelRender*)GetInterface("engine.dll", "VEngineModel016")))
            Msg("[Interfaces] Found IVModelRender:        0x%p\n", g_pModelRender);
        
        if ((g_pEngineTrace = (IEngineTrace*)GetInterface("engine.dll", "EngineTraceClient003")))
            Msg("[Interfaces] Found IEngineTrace:         0x%p\n", g_pEngineTrace);
        
        if ((g_pLuaShared = (CLuaShared*)GetInterface("lua_shared.dll", "LUASHARED003")))
            Msg("[Interfaces] Found CLuaShared:           0x%p\n", g_pLuaShared);
        
        if ((g_pPhysicsSurfaceProps = (IPhysicsSurfaceProps*)GetInterface("vphysics.dll", "VPhysicsSurfaceProps001")))
            Msg("[Interfaces] Found IPhysicsSurfaceProps: 0x%p\n", g_pPhysicsSurfaceProps);
        
        if ((g_pCvar = (ICvar*)GetInterface("vstdlib.dll", "VEngineCvar007")))
            Msg("[Interfaces] Found ICvar:                0x%p\n", g_pCvar);

        // Verify critical interfaces you need (adjust as needed)
        if (!g_pMaterialSystem || !g_pShaderAPI) {
            Error("[Interfaces] Failed to initialize critical interfaces!\n");
            return false;
        }
        
        Msg("[Interfaces] Successfully initialized interfaces\n");
        return true;
    }

    void Interfaces::PrintInterfaces()
    {
        Msg("--- Successfully Initialized Interfaces ---\n");
        
        // For each interface, check if it's valid before printing
        if (g_pMaterialSystem)
            Msg("IMaterialSystem:       0x%p\n", g_pMaterialSystem);
        
        if (g_pShaderAPI)
            Msg("IShaderAPI:            0x%p\n", g_pShaderAPI);
        
        if (g_pClient)
            Msg("CHLClient:             0x%p\n", g_pClient);
        
        if (g_pEngine)
            Msg("CEngineClient:         0x%p\n", g_pEngine);
        
        if (g_pEntityList)
            Msg("ClientEntityList:      0x%p\n", g_pEntityList);
        
        if (g_pSurface)
            Msg("ISurface:              0x%p\n", g_pSurface);
        
        if (g_pModelRender)
            Msg("IVModelRender:         0x%p\n", g_pModelRender);
        
        if (g_pEngineTrace)
            Msg("IEngineTrace:          0x%p\n", g_pEngineTrace);
        
        if (g_pLuaShared)
            Msg("CLuaShared:            0x%p\n", g_pLuaShared);
        
        if (g_pPhysicsSurfaceProps)
            Msg("IPhysicsSurfaceProps:  0x%p\n", g_pPhysicsSurfaceProps);
        
        if (g_pCvar)
            Msg("ICvar:                 0x%p\n", g_pCvar);
        
        Msg("----------------------------------------\n");
    }

    // Simple interface tests that just verify the pointers without making complex method calls

    void Interfaces::TestMaterialSystem()
    {
        Msg("[Test] Testing IMaterialSystem...\n");
        
        if (!g_pMaterialSystem) {
            Error("[Test] IMaterialSystem is null!\n");
            return;
        }
        
        // Get number of materials
        // GetNumMaterials() is typically at index 84 in the vtable
        typedef int(__thiscall* GetNumMaterialsFn)(void*);
        GetNumMaterialsFn GetNumMaterials = (GetNumMaterialsFn)(*(void***)g_pMaterialSystem)[84];
        
        int materialCount = GetNumMaterials(g_pMaterialSystem);
        Msg("[Test] Material count: %d\n", materialCount);
        
        // Get material system hardware config (at vtable index 11)
        typedef void*(__thiscall* GetHardwareConfigFn)(void*, const char*, int*);
        GetHardwareConfigFn GetHardwareConfig = (GetHardwareConfigFn)(*(void***)g_pMaterialSystem)[11];
        
        int returnCode = 0;
        void* hwConfig = GetHardwareConfig(g_pMaterialSystem, nullptr, &returnCode);
        Msg("[Test] Hardware config: 0x%p (return code: %d)\n", hwConfig, returnCode);
        
        Msg("[Test] IMaterialSystem test complete\n");
    }

    void Interfaces::TestShaderAPI()
    {
        Msg("[Test] Testing IShaderAPI...\n");
        
        if (!g_pShaderAPI) {
            Error("[Test] IShaderAPI is null!\n");
            return;
        }
        
        // Get back buffer dimensions (at vtable index 129)
        typedef void(__thiscall* GetBackBufferDimensionsFn)(void*, int&, int&);
        GetBackBufferDimensionsFn GetBackBufferDimensions = (GetBackBufferDimensionsFn)(*(void***)g_pShaderAPI)[129];
        
        int width = 0, height = 0;
        GetBackBufferDimensions(g_pShaderAPI, width, height);
        Msg("[Test] Back buffer dimensions: %dx%d\n", width, height);
        
        // Check if using graphics (at vtable index 133)
        typedef bool(__thiscall* IsUsingGraphicsFn)(void*);
        IsUsingGraphicsFn IsUsingGraphics = (IsUsingGraphicsFn)(*(void***)g_pShaderAPI)[133];
        
        bool isUsingGraphics = IsUsingGraphics(g_pShaderAPI);
        Msg("[Test] Is using graphics API: %s\n", isUsingGraphics ? "Yes" : "No");
        
        Msg("[Test] IShaderAPI test complete\n");
    }

    void Interfaces::TestEngineClient()
    {
        Msg("[Test] Testing CEngineClient...\n");
        
        if (!g_pEngine) {
            Error("[Test] CEngineClient is null!\n");
            return;
        }
        
        // Get game directory (at vtable index 36)
        typedef const char*(__thiscall* GetGameDirectoryFn)(void*);
        GetGameDirectoryFn GetGameDirectory = (GetGameDirectoryFn)(*(void***)g_pEngine)[36];
        
        const char* gameDir = GetGameDirectory(g_pEngine);
        Msg("[Test] Game directory: %s\n", gameDir);
        
        // Check if in game (at vtable index 26)
        typedef bool(__thiscall* IsInGameFn)(void*);
        IsInGameFn IsInGame = (IsInGameFn)(*(void***)g_pEngine)[26];
        
        bool inGame = IsInGame(g_pEngine);
        Msg("[Test] Is in game: %s\n", inGame ? "Yes" : "No");
        
        // Get screen size (at vtable index 5)
        typedef void(__thiscall* GetScreenSizeFn)(void*, int&, int&);
        GetScreenSizeFn GetScreenSize = (GetScreenSizeFn)(*(void***)g_pEngine)[5];
        
        int width = 0, height = 0;
        GetScreenSize(g_pEngine, width, height);
        Msg("[Test] Screen size: %dx%d\n", width, height);
        
        // Get current level name if in game (at vtable index 52)
        if (inGame) {
            typedef const char*(__thiscall* GetLevelNameFn)(void*);
            GetLevelNameFn GetLevelName = (GetLevelNameFn)(*(void***)g_pEngine)[52];
            
            const char* levelName = GetLevelName(g_pEngine);
            Msg("[Test] Current map: %s\n", levelName);
        } else {
            Msg("[Test] Not in a map\n");
        }
        
        Msg("[Test] CEngineClient test complete\n");
    }

    // void Interfaces::TestSurface()
    // {
    //     Msg("[Test] Testing ISurface...\n");
        
    //     if (!g_pSurface) {
    //         Error("[Test] ISurface is null!\n");
    //         return;
    //     }
        
    //     // // Get screen size (at vtable index 44)                                                      // This one fails
    //     // typedef void(__thiscall* GetScreenSizeFn)(void*, int&, int&);
    //     // GetScreenSizeFn GetScreenSize = (GetScreenSizeFn)(*(void***)g_pSurface)[44];
        
    //     // int width = 0, height = 0;
    //     // GetScreenSize(g_pSurface, width, height);
    //     // Msg("[Test] Surface screen size: %dx%d\n", width, height);
        
    //     // Create font (at vtable index 66)
    //     typedef int(__thiscall* CreateFontFn)(void*);
    //     CreateFontFn CreateFont = (CreateFontFn)(*(void***)g_pSurface)[66];
        
    //     int fontHandle = CreateFont(g_pSurface);
    //     Msg("[Test] Created font handle: %d\n", fontHandle);
        
    //     // // Get texture count (at vtable index 45)                                                // This one fails
    //     // typedef int(__thiscall* GetTextureCountFn)(void*);
    //     // GetTextureCountFn GetTextureCount = (GetTextureCountFn)(*(void***)g_pSurface)[45];
        
    //     // int textureCount = GetTextureCount(g_pSurface);
    //     // Msg("[Test] Surface texture count: %d\n", textureCount);
        
    //     // Msg("[Test] ISurface test complete\n");
    // }

    // void Interfaces::TestCvar()
    // {
    //     Msg("[Test] Testing ICvar...\n");
        
    //     if (!g_pCvar) {
    //         Error("[Test] ICvar is null!\n");
    //         return;
    //     }
        
    //     // Find console variable "sv_cheats" (at vtable index 16)
    //     typedef void*(__thiscall* FindVarFn)(void*, const char*);
    //     FindVarFn FindVar = (FindVarFn)(*(void***)g_pCvar)[16];
        
    //     void* sv_cheats = FindVar(g_pCvar, "sv_cheats");
    //     if (sv_cheats) {
    //         // Get integer value from ConVar (the GetInt function is typically at offset 13 in ConVar's vtable)
    //         typedef int(__thiscall* GetIntFn)(void*);
    //         GetIntFn GetInt = (GetIntFn)(*(void***)sv_cheats)[13];
            
    //         int value = GetInt(sv_cheats);
    //         Msg("[Test] sv_cheats value: %d\n", value);
    //     } else {
    //         Error("[Test] Failed to find sv_cheats\n");
    //     }
        
    //     // Print a message to console (at vtable index 25)
    //     typedef void(__cdecl* ConsoleColorPrintfFn)(void*, const unsigned char[4], const char*, ...);
    //     ConsoleColorPrintfFn ColorPrintf = (ConsoleColorPrintfFn)(*(void***)g_pCvar)[25];
        
    //     unsigned char color[4] = {0, 255, 0, 255}; // Green
    //     ColorPrintf(g_pCvar, color, "RTX Interface Test: Console command executed\n");
        
    //     Msg("[Test] ICvar test complete\n");
    // }

    void Interfaces::TestCvar()
{
    Msg("[Test] Testing ICvar...\n");
    
    if (!g_pCvar) {
        Error("[Test] ICvar is null!\n");
        return;
    }
    
    // Find console variable "sv_cheats" (at vtable index 16)
    typedef void*(__thiscall* FindVarFn)(void*, const char*);
    FindVarFn FindVar = (FindVarFn)(*(void***)g_pCvar)[16];
    
    void* sv_cheats = FindVar(g_pCvar, "sv_cheats");
    if (sv_cheats) {
        // Get integer value from ConVar (the GetInt function is typically at offset 13 in ConVar's vtable)
        typedef int(__thiscall* GetIntFn)(void*);
        GetIntFn GetInt = (GetIntFn)(*(void***)sv_cheats)[13];
        
        int value = GetInt(sv_cheats);
        Msg("[Test] sv_cheats value: %d\n", value);
    } else {
        Error("[Test] Failed to find sv_cheats\n");
    }
    
    // Print a message to console (at vtable index 25)
    typedef void(__cdecl* ConsoleColorPrintfFn)(void*, const unsigned char[4], const char*, ...);
    ConsoleColorPrintfFn ColorPrintf = (ConsoleColorPrintfFn)(*(void***)g_pCvar)[25];
    
    unsigned char color[4] = {0, 255, 0, 255}; // Green
    ColorPrintf(g_pCvar, color, "RTX Interface Test: Console command executed\n");
    
    Msg("[Test] ICvar test complete\n");
}

    void Interfaces::RunInterfaceTests()
    {
        Msg("--- Running Interface Tests ---\n");
        
        TestMaterialSystem();
        TestShaderAPI();
        TestEngineClient();
        //TestSurface();
        TestCvar();
        
        Msg("--- Interface Tests Complete ---\n");
    }

    // Function to find a material using the material system
    IMaterial* Interfaces::FindMaterial(const char* materialName, bool complain)
    {
        if (!g_pMaterialSystem) {
            Error("[MaterialUtils] MaterialSystem not initialized\n");
            return nullptr;
        }

        // FindMaterial is typically at vtable offset 79 for 64-bit Garry's Mod
        typedef IMaterial* (__thiscall* FindMaterialFn)(void*, const char*, const char*, bool, const char*);
        FindMaterialFn FindMaterial = nullptr;
        
        try {
            // Try a few potential offsets
            const int possibleOffsets[] = {78, 79, 80, 81};
            for (int offset : possibleOffsets) {
                FindMaterial = (FindMaterialFn)(*(void***)g_pMaterialSystem)[offset];
                
                // Call with safe parameters
                IMaterial* material = FindMaterial(g_pMaterialSystem, materialName, "Other", complain, nullptr);
                if (material) {
                    Msg("[MaterialUtils] Found material %s at vtable offset %d\n", materialName, offset);
                    return material;
                }
            }
        }
        catch (...) {
            Error("[MaterialUtils] Exception in FindMaterial\n");
        }

        return nullptr;
    }

    // Function to set a material's shader
    void Interfaces::SetMaterialShader(IMaterial* material, const char* shaderName)
    {
        if (!material) {
            Error("[MaterialUtils] Invalid material\n");
            return;
        }

        // SetShader is typically at vtable offset 53 for 64-bit Garry's Mod
        typedef void (__thiscall* SetShaderFn)(void*, const char*);
        SetShaderFn SetShader = nullptr;
        
        try {
            // Try a few potential offsets
            const int possibleOffsets[] = {52, 53, 54, 55};
            for (int offset : possibleOffsets) {
                SetShader = (SetShaderFn)(*(void***)material)[offset];
                
                // Call the function - we need to catch exceptions since we don't know the right offset
                try {
                    SetShader(material, shaderName);
                    Msg("[MaterialUtils] Set shader to %s at vtable offset %d\n", shaderName, offset);
                    return;
                }
                catch (...) {
                    Msg("[MaterialUtils] Failed to set shader at offset %d\n", offset);
                }
            }
        }
        catch (...) {
            Error("[MaterialUtils] Exception in SetMaterialShader\n");
        }
    }

    // Function to check if a material is using the SpriteCard shader
    bool IsSpriteCardMaterial(IMaterial* material)
    {
        if (!material) return false;

        // GetShaderName is typically at vtable offset 56 for 64-bit Garry's Mod
        typedef const char* (__thiscall* GetShaderNameFn)(void*);
        GetShaderNameFn GetShaderName = nullptr;
        
        try {
            // Try a few potential offsets
            const int possibleOffsets[] = {56};
            for (int offset : possibleOffsets) {
                GetShaderName = (GetShaderNameFn)(*(void***)material)[offset];
                
                try {
                    const char* shaderName = GetShaderName(material);
                    if (shaderName && strcmp(shaderName, "SpriteCard") == 0) {
                        Msg("[MaterialUtils] Found SpriteCard shader at vtable offset %d\n", offset);
                        return true;
                    }
                }
                catch (...) {
                    // Try next offset
                }
            }
        }
        catch (...) {
            Error("[MaterialUtils] Exception in IsSpriteCardMaterial\n");
        }

        return false;
    }

    // Function to iterate through all materials and replace SpriteCard with UnlitGeneric
    bool Interfaces::ReplaceSpriteCardWithUnlitGeneric()
    {
        if (!g_pMaterialSystem) {
            Error("[MaterialUtils] MaterialSystem not initialized\n");
            return false;
        }

        Msg("[MaterialUtils] Starting SpriteCard replacement...\n");

        // FirstMaterial is typically at vtable offset 75 for 64-bit Garry's Mod
        typedef unsigned short (__thiscall* FirstMaterialFn)(void*);
        FirstMaterialFn FirstMaterial = nullptr;
        
        // NextMaterial is typically at vtable offset 76 for 64-bit Garry's Mod
        typedef unsigned short (__thiscall* NextMaterialFn)(void*, unsigned short);
        NextMaterialFn NextMaterial = nullptr;
        
        // InvalidMaterial is typically at vtable offset 77 for 64-bit Garry's Mod
        typedef unsigned short (__thiscall* InvalidMaterialFn)(void*);
        InvalidMaterialFn InvalidMaterial = nullptr;
        
        // GetMaterial is typically at vtable offset 78 for 64-bit Garry's Mod
        typedef IMaterial* (__thiscall* GetMaterialFn)(void*, unsigned short);
        GetMaterialFn GetMaterial = nullptr;

        try {
            // Find FirstMaterial function
            const int firstMaterialOffsets[] = {74, 75, 76};
            for (int offset : firstMaterialOffsets) {
                FirstMaterial = (FirstMaterialFn)(*(void***)g_pMaterialSystem)[offset];
                try {
                    unsigned short handle = FirstMaterial(g_pMaterialSystem);
                    if (handle != 0) {
                        Msg("[MaterialUtils] Found FirstMaterial at offset %d\n", offset);
                        break;
                    }
                } catch (...) { }
            }
            
            if (!FirstMaterial) {
                Error("[MaterialUtils] Could not find FirstMaterial function\n");
                return false;
            }
            
            // Find NextMaterial function
            const int nextMaterialOffsets[] = {75, 76, 77};
            for (int offset : nextMaterialOffsets) {
                NextMaterial = (NextMaterialFn)(*(void***)g_pMaterialSystem)[offset];
                // We can't easily verify this one, so just assume it's at expected offset for now
                break;
            }
            
            if (!NextMaterial) {
                Error("[MaterialUtils] Could not find NextMaterial function\n");
                return false;
            }
            
            // Find InvalidMaterial function
            const int invalidMaterialOffsets[] = {76, 77, 78};
            for (int offset : invalidMaterialOffsets) {
                InvalidMaterial = (InvalidMaterialFn)(*(void***)g_pMaterialSystem)[offset];
                try {
                    InvalidMaterial(g_pMaterialSystem);
                    Msg("[MaterialUtils] Found InvalidMaterial at offset %d\n", offset);
                    break;
                } catch (...) { }
            }
            
            if (!InvalidMaterial) {
                Error("[MaterialUtils] Could not find InvalidMaterial function\n");
                return false;
            }
            
            // Find GetMaterial function
            const int getMaterialOffsets[] = {77, 78, 79};
            for (int offset : getMaterialOffsets) {
                GetMaterial = (GetMaterialFn)(*(void***)g_pMaterialSystem)[offset];
                try {
                    unsigned short handle = FirstMaterial(g_pMaterialSystem);
                    IMaterial* material = GetMaterial(g_pMaterialSystem, handle);
                    if (material) {
                        Msg("[MaterialUtils] Found GetMaterial at offset %d\n", offset);
                        break;
                    }
                } catch (...) { }
            }
            
            if (!GetMaterial) {
                Error("[MaterialUtils] Could not find GetMaterial function\n");
                return false;
            }
            
            // Now iterate through all materials
            unsigned short invalid = InvalidMaterial(g_pMaterialSystem);
            int replacedCount = 0;
            
            for (unsigned short handle = FirstMaterial(g_pMaterialSystem); handle != invalid; handle = NextMaterial(g_pMaterialSystem, handle)) {
                IMaterial* material = GetMaterial(g_pMaterialSystem, handle);
                if (material && IsSpriteCardMaterial(material)) {
                    Msg("[MaterialUtils] Found SpriteCard material, replacing with UnlitGeneric\n");
                    SetMaterialShader(material, "UnlitGeneric");
                    replacedCount++;
                }
            }
            
            Msg("[MaterialUtils] Replaced %d SpriteCard materials with UnlitGeneric\n", replacedCount);
            return replacedCount > 0;
        }
        catch (...) {
            Error("[MaterialUtils] Exception in ReplaceSpriteCardWithUnlitGeneric\n");
            return false;
        }
    }
}