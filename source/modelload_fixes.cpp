

// Hook the file opening function instead
//Define_method_Hook(FILE*, fopen, void*, const char* filename, const char* mode)
//{
//    // Check if the file being opened is a .dx90.vtx file
//    const char* vtx_ext = ".dx90.vtx";
//    size_t filename_len = strlen(filename);
//    size_t ext_len = strlen(vtx_ext);
//
//    if (filename_len > ext_len &&
//        _stricmp(filename + filename_len - ext_len, vtx_ext) == 0) {
//
//        // Create a new filename with .sw.vtx instead
//        char* sw_filename = (char*)malloc(filename_len + 1);
//        strcpy(sw_filename, filename);
//        strcpy(sw_filename + filename_len - ext_len, ".sw.vtx");
//
//        // Try to open the .sw.vtx file
//        FILE* file = fopen_trampoline()(sw_filename, mode);
//        free(sw_filename);
//
//        // If successful, return the file; otherwise fall back to original
//        if (file) {
//            Msg("[Model Load Fixes] Redirected %s to .sw.vtx version\n", filename);
//            return file;
//        }
//    }
//
//    // Fall back to original behavior
//    return fopen_trampoline()(_this, filename, mode);
//}


//Define_method_Hook(bool, CMDLCache_LoadHardwareData, void*, MDLHandle_t handle)
//{
//    // Key insight: We only need to modify the part where the VTX file is loaded
//    // Let's identify where in the function it's accessing the VTX file
//
//    // First, let the function run normally until just before it loads the VTX file
//    // We can detour it at that point by setting a breakpoint or using a strategic hook
//
//    // For demonstration purposes, here's a general approach:
//
//    // 1. First, temporarily hook the function that gets the VTX extension
//    // This is likely GetVTXExtension() in the original code
//
//    static bool trying_sw_vtx = false;
//    static void* original_GetVTXExtension = nullptr;
//
//    // Only try .sw.vtx file if we're not already trying it
//    if (!trying_sw_vtx) {
//        // Find the GetVTXExtension function
//        if (!original_GetVTXExtension) {
//            // You'll need to find this function - it might be nearby or referenced
//            // original_GetVTXExtension = FindPattern(module, "GetVTXExtension signature");
//        }
//
//        if (original_GetVTXExtension) {
//            // Hook or patch GetVTXExtension to return ".sw.vtx"
//            // This is pseudo-code - you'll need your actual hooking implementation
//            // HookFunction(original_GetVTXExtension, MyGetVTXExtension);
//
//            trying_sw_vtx = true;
//
//            // Call the original function with our hook in place
//            bool result = CMDLCache_LoadHardwareData_trampoline()(_this, handle);
//
//            // Restore the original GetVTXExtension function
//            // UnhookFunction(original_GetVTXExtension);
//
//            trying_sw_vtx = false;
//
//            // If loading with .sw.vtx succeeded, return the result
//            if (result) {
//                Msg("[Model Load Fixes] Successfully loaded .sw.vtx for handle %d\n", handle);
//                return result;
//            }
//
//            // If loading with .sw.vtx failed, we'll fall through to try .dx90.vtx
//            Msg("[Model Load Fixes] Failed to load .sw.vtx, falling back to .dx90.vtx\n");
//        }
//    }
//
//    // If we didn't succeed with .sw.vtx or couldn't hook GetVTXExtension,
//    // fall back to original behavior (which will try .dx90.vtx)
//    return CMDLCache_LoadHardwareData_trampoline()(_this, handle);
//}

// Mock implementation of our custom GetVTXExtension
//const char* MyGetVTXExtension()
//{
//    return ".sw.vtx";
//}
#include "GarrysMod/Lua/Interface.h"
#include "modelload_fixes.h"
#include "cdll_client_int.h"
#include "filesystem.h"  // Include for IFileSystem definitions
#include "datacache/imdlcache.h"

using namespace GarrysMod::Lua;

// Global filesystem interface pointer
IFileSystem* g_pFileSystem = nullptr;

// Standard method hook for the filesystem open function
Define_method_Hook(FileHandle_t, IFileSystem_OpenEx, void*, const char* pFileName,
    const char* pOptions, unsigned flags, const char* pathID, char** ppszResolvedFilename)
{
    // Safety check for null pointers
    if (!pFileName || !pOptions) {
        return IFileSystem_OpenEx_trampoline()(_this, pFileName, pOptions, flags, pathID, ppszResolvedFilename);
    }

    // Define the VTX extensions we want to check for
    const char* vtx_exts[] = { ".dx90.vtx", ".dx80.vtx", ".dx70.vtx" };
    const int ext_count = sizeof(vtx_exts) / sizeof(vtx_exts[0]);

    // Check if it's a model file (handle both forward and backslashes)
    const char* model_indicators[] = { "models/", "models\\" };
    bool is_model = false;
    for (int i = 0; i < 2; i++) {
        if (strstr(pFileName, model_indicators[i])) {
            is_model = true;
            break;
        }
    }

    if (is_model) {
        size_t filename_len = strlen(pFileName);

        // Check for each possible extension
        for (int i = 0; i < ext_count; i++) {
            const char* vtx_ext = vtx_exts[i];
            size_t ext_len = strlen(vtx_ext);

            // If filename ends with this extension (case insensitive)
            if (filename_len > ext_len &&
                _stricmp(pFileName + filename_len - ext_len, vtx_ext) == 0) {

                // Create buffer for the .sw.vtx filename
                char* sw_path = (char*)malloc(filename_len + 1);
                if (sw_path) {
                    // Copy the original file path
                    strcpy(sw_path, pFileName);

                    // Find the extension in our copied string and replace it
                    // We use the exact position rather than strstr to handle 
                    // cases where the extension might appear elsewhere in the path
                    char* ext = sw_path + (filename_len - ext_len);
                    strcpy(ext, ".sw.vtx");

                    // Check if the .sw.vtx file exists first
                    bool exists = false;
                    __try {
                        // Try a non-opening existence check first (if available)
                        if ((void*)_this && ((IFileSystem*)_this)->FileExists(sw_path, pathID)) {
                            exists = true;
                            Msg("[Model Load Fixes] .sw.vtx file exists: %s\n", sw_path);
                        }
                    }
                    __except (EXCEPTION_EXECUTE_HANDLER) {
                        // Couldn't check existence, will try direct open
                    }

                    // Try to open the .sw.vtx file
                    FileHandle_t handle = NULL;
                    __try {
                        handle = IFileSystem_OpenEx_trampoline()(_this, sw_path, pOptions, flags, pathID, ppszResolvedFilename);
                    }
                    __except (EXCEPTION_EXECUTE_HANDLER) {
                        Msg("[Model Load Fixes] Exception trying to open %s\n", sw_path);
                        handle = NULL;
                    }

                    if (handle) {
                        Msg("[Model Load Fixes] Successfully redirected %s to %s\n", pFileName, sw_path);
                        free(sw_path);
                        return handle;
                    }
                    else {
                        // Only log when we specifically tried but failed to redirect
                        Msg("[Model Load Fixes] Failed to redirect %s to %s (file may not exist)\n",
                            pFileName, sw_path);
                    }

                    free(sw_path);
                }

                // We matched an extension but couldn't redirect
                break;
            }
        }
    }

    // Fall back to original behavior without logging
    return IFileSystem_OpenEx_trampoline()(_this, pFileName, pOptions, flags, pathID, ppszResolvedFilename);
}

static IMDLCache* g_pMDLCache;
static IVEngineClient* engineClient;

void ForceModelReload() { 

    Msg("[Model Load Fixes] Forcing model reload...\n");
    if (g_pMDLCache) {
        // Flush the entire cache
        g_pMDLCache->Flush(MDLCACHE_FLUSH_ALL);
        Msg("[Model Load Fixes] Successfully flushed model cache\n");
    }
    else {
        Warning("[Model Load Fixes] Couldn't access MDL cache to force reload\n");
    }
}
void ForceModelReloadViaEngine() {
    // Get the engine client interface
    if (engineClient) {
        // Use safer commands that won't crash (r_flushlod crashes)
        engineClient->ClientCmd_Unrestricted("mat_reloadallmaterials");

        Msg("[Model Load Fixes] Executed engine reload commands\n");
    }
    else {
        Warning("[Model Load Fixes] Couldn't access engine client, early loaded map models will not be reloaded in their RTX Remix friendly .sw.vtx form!\n");
    }
}

void ModelLoadHooks::Initialize() {
    try {
        Msg("[RTX Remix Fixes 2 - Binary Module] - Loading datacache\n");
        if (!Sys_LoadInterface("datacache", MDLCACHE_INTERFACE_VERSION, NULL, (void**)&g_pMDLCache))
            Warning("[RTX Remix Fixes 2] - Could not load studiorender interface");

        if (!Sys_LoadInterface("engine", VENGINE_CLIENT_INTERFACE_VERSION, NULL, (void**)&engineClient))
            Warning("[RTX Remix Fixes 2] - Could not load engine interface");

        // Find the filesystem module
        HMODULE fsModule = GetModuleHandle("filesystem_stdio.dll");
        if (!fsModule) {
            fsModule = GetModuleHandle("filesystem.dll");
        }

        if (!fsModule) {
            Warning("[Model Load Fixes] - Could not find filesystem module");
            return;
        }

        // Use the signature to find IFileSystem::OpenEx
        static const char openSig[] = "4C 8B DC 48 81 EC";
        void* openFunc = ScanSign(fsModule, openSig, sizeof(openSig) - 1);

        if (!openFunc) {
            Warning("[Model Load Fixes] - Could not find IFileSystem::OpenEx with signature");
            return;
        }

        Msg("[Model Load Fixes] Found IFileSystem::OpenEx at %p\n", openFunc);

        // Set up the hook directly on the function
        Setup_Hook(IFileSystem_OpenEx, openFunc);
        Msg("[Model Load Fixes] Successfully hooked IFileSystem::OpenEx\n");

        ForceModelReload();
		ForceModelReloadViaEngine();
    }
    catch (...) {
        Msg("[Model Load Fixes] Exception in ModelLoadHooks::Initialize\n");
    }
}


void ModelLoadHooks::Shutdown() {
    // Existing shutdown code  
    IFileSystem_OpenEx_hook.Disable();

    // Log shutdown completion
    Msg("[Prop Fixes] Shutdown complete\n");
}