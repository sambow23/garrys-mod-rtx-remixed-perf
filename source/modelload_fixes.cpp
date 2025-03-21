

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
#include <stdint.h>
#include <vector>
#include <unordered_map>
#include <string>
#include <thread>
#include <mutex>

using namespace GarrysMod::Lua;

// Global filesystem interface pointer
IFileSystem* g_pFileSystem = nullptr;

// VTX file structure for checksum
#pragma pack(push, 1)
struct OptimizedModelFileHeader_t
{
    int version;
    int vertCacheSize;
    short maxBonesPerStrip;
    short maxBonesPerTri;
    int maxBonesPerVert;
    int checkSum;
    int numLODs;
    int numBodyParts;
    int bodyPartOffset;
};
#pragma pack(pop)

// Forward declare helper functions, will implement after the hook
int GetVtxFileChecksum(void* fs, const char* filename, const char* pathID, void* openFunc);
int GetMdlFileChecksum(void* fs, const char* filename, const char* pathID, void* openFunc);

// Modified hook with recursion prevention and checksum verification
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

                // Create SW VTX path
                char* sw_path = (char*)malloc(filename_len + 1);
                if (sw_path) {
                    strcpy(sw_path, pFileName);
                    char* ext = sw_path + (filename_len - ext_len);
                    strcpy(ext, ".sw.vtx");

                    // Try to open both files and check checksums
                    FileHandle_t origFile = IFileSystem_OpenEx_trampoline()(_this, pFileName, "rb", 0, pathID, NULL);
                    FileHandle_t swFile = IFileSystem_OpenEx_trampoline()(_this, sw_path, "rb", 0, pathID, NULL);

                    bool canUseSwVtx = false;

                    if (origFile && swFile) {
                        // Read checksums from both files
                        OptimizedModelFileHeader_t origHeader, swHeader;
                        bool origValid = (((IFileSystem*)_this)->Read(&origHeader, sizeof(origHeader), origFile) == sizeof(origHeader));
                        bool swValid = (((IFileSystem*)_this)->Read(&swHeader, sizeof(swHeader), swFile) == sizeof(swHeader));

                        // Check if checksums match
                        if (origValid && swValid && origHeader.checkSum == swHeader.checkSum) {
                            canUseSwVtx = true;
                        }
                    }

                    // Close the test files
                    if (origFile) ((IFileSystem*)_this)->Close(origFile);
                    if (swFile) ((IFileSystem*)_this)->Close(swFile);

                    // If checksums match, use the SW VTX file for actual operation
                    if (canUseSwVtx) {
                        FileHandle_t handle = IFileSystem_OpenEx_trampoline()(_this, sw_path, pOptions, flags, pathID, ppszResolvedFilename);
                        if (handle) {
                            //Msg("[RTX Remix Fixes 2] Successfully redirected %s to checksum-verified %s\n", pFileName, sw_path);
                            free(sw_path);
                            return handle;
                        }
                    }

                    free(sw_path);
                }
                break;
            }
        }
    }

    // Fall back to original behavior
    return IFileSystem_OpenEx_trampoline()(_this, pFileName, pOptions, flags, pathID, ppszResolvedFilename);
}

// Helper function to read checksum from a VTX file - now using trampoline directly
typedef FileHandle_t(*OpenExFunc)(void*, const char*, const char*, unsigned, const char*, char**);

int GetVtxFileChecksum(void* fs, const char* filename, const char* pathID, void* openFunc)
{
    OpenExFunc openExFn = (OpenExFunc)openFunc;

    // Open the file directly using the trampoline
    FileHandle_t file = openExFn(fs, filename, "rb", 0, pathID, NULL);
    if (!file)
        return 0;

    OptimizedModelFileHeader_t header;
    size_t bytesRead = ((IFileSystem*)fs)->Read(&header, sizeof(header), file);
    ((IFileSystem*)fs)->Close(file);

    if (bytesRead != sizeof(header))
        return 0;

    return header.checkSum;
}

// Helper to get MDL checksum - using trampoline
int GetMdlFileChecksum(void* fs, const char* filename, const char* pathID, void* openFunc)
{
    // Extract base MDL path
    std::string mdlPath = filename;

    // Replace VTX extension with MDL extension
    const char* extensions[] = { ".dx90.vtx", ".dx80.vtx", ".dx70.vtx", ".sw.vtx" };
    for (const char* ext : extensions) {
        size_t pos = mdlPath.rfind(ext);
        if (pos != std::string::npos) {
            mdlPath.replace(pos, strlen(ext), ".mdl");
            break;
        }
    }

    OpenExFunc openExFn = (OpenExFunc)openFunc;

    // Open the MDL file using the trampoline
    FileHandle_t file = openExFn(fs, mdlPath.c_str(), "rb", 0, pathID, NULL);
    if (!file)
        return 0;

    // Read the checksum from the MDL file
    // For most Source engine games, the checksum is at offset 0x4C
    ((IFileSystem*)fs)->Seek(file, 0x4C, FILESYSTEM_SEEK_HEAD);

    int checksum = 0;
    ((IFileSystem*)fs)->Read(&checksum, sizeof(checksum), file);
    ((IFileSystem*)fs)->Close(file);

    return checksum;
}


static IMDLCache* g_pMDLCache;
static IVEngineClient* engineClient;

void ForceModelReload() { 

    Msg("[RTX Remix Fixes 2 - Model Load Fixes] Forcing model reload...\n");
    if (g_pMDLCache) {
        // Flush the entire cache
        g_pMDLCache->Flush(MDLCACHE_FLUSH_ALL);
        Msg("[RTX Remix Fixes 2 - Model Load Fixes] Successfully flushed model cache\n");
    }
    else {
        Warning("[RTX Remix Fixes 2 - Model Load Fixes] Couldn't access MDL cache to force reload\n");
    }
}
void ForceModelReloadViaEngine() {
    // Get the engine client interface
    if (engineClient) {
        // Use safer commands that won't crash (r_flushlod crashes)
        engineClient->ClientCmd_Unrestricted("mat_reloadallmaterials");

        Msg("[RTX Remix Fixes 2 - Model Load Fixes] Executed engine reload commands\n");
    }
    else {
        Warning("[RTX Remix Fixes 2 - Model Load Fixes] Couldn't access engine client, early loaded map models will not be reloaded in their RTX Remix friendly .sw.vtx form!\n");
    }
}

void ModelLoadHooks::Initialize() {
    try {
        Msg("[RTX Remix Fixes 2 - Model Load Fixes] - Loading datacache\n");
        if (!Sys_LoadInterface("datacache", MDLCACHE_INTERFACE_VERSION, NULL, (void**)&g_pMDLCache))
            Warning("[RTX Remix Fixes 2 - Model Load Fixes] - Could not load studiorender interface");

        Msg("[RTX Remix Fixes 2 - Model Load Fixes] - Loading clientengine\n");
        if (!Sys_LoadInterface("engine", VENGINE_CLIENT_INTERFACE_VERSION, NULL, (void**)&engineClient))
            Warning("[RTX Remix Fixes 2 - Model Load Fixes] - Could not load clientengine interface");

        // Find the filesystem module
        HMODULE fsModule = GetModuleHandle("filesystem_stdio.dll");
        if (!fsModule) {
            fsModule = GetModuleHandle("filesystem.dll");
        }

        if (!fsModule) {
            Warning("[RTX Remix Fixes 2 - Model Load Fixes] - Could not find filesystem module");
            return;
        }

        // Use the signature to find IFileSystem::OpenEx
        static const char openSig[] = "4C 8B DC 48 81 EC";
        void* openFunc = ScanSign(fsModule, openSig, sizeof(openSig) - 1);

        if (!openFunc) {
            Warning("[RTX Remix Fixes 2 - Model Load Fixes] - Could not find IFileSystem::OpenEx with signature");
            return;
        }

        Msg("[RTX Remix Fixes 2 - Model Load Fixes] Found IFileSystem::OpenEx at %p\n", openFunc);

        // Set up the hook directly on the function
        Setup_Hook(IFileSystem_OpenEx, openFunc);
        Msg("[RTX Remix Fixes 2 - Model Load Fixes] Successfully hooked IFileSystem::OpenEx\n");

        ForceModelReload();
		ForceModelReloadViaEngine();
    }
    catch (...) {
        Msg("[RTX Remix Fixes 2 - Model Load Fixes] Exception in ModelLoadHooks::Initialize\n");
    }
}


void ModelLoadHooks::Shutdown() {
    // Existing shutdown code  
    IFileSystem_OpenEx_hook.Disable();

    // Log shutdown completion
    Msg("[RTX Remix Fixes 2 - Model Load Fixes] Shutdown complete\n");
}