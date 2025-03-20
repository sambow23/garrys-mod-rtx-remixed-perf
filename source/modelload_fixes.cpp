

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

using namespace GarrysMod::Lua;

// Global filesystem interface pointer
IFileSystem* g_pFileSystem = nullptr;

// Standard method hook for the filesystem open function
Define_method_Hook(FileHandle_t, IFileSystem_Open, void*, const char* pFileName, const char* pOptions, const char* pathID, int64* pSize)
{
    // Check if looking for a .dx90.vtx file
    const char* vtx_ext = ".dx90.vtx";
    size_t filename_len = strlen(pFileName);
    size_t ext_len = strlen(vtx_ext);

    if (filename_len > ext_len &&
        _stricmp(pFileName + filename_len - ext_len, vtx_ext) == 0) {

        // Create .sw.vtx filename
        char sw_path[MAX_PATH];
        strncpy(sw_path, pFileName, sizeof(sw_path) - 1);
        sw_path[sizeof(sw_path) - 1] = '\0';  // Ensure null termination

        char* ext = strstr(sw_path, ".dx90.vtx");
        if (ext) {
            strcpy(ext, ".sw.vtx");

            // Check if .sw.vtx exists by trying to open it
            FileHandle_t handle = IFileSystem_Open_trampoline()(_this, sw_path, pOptions, pathID, pSize);
            if (handle) {
                Msg("[Model Load Fixes] Redirected %s to %s\n", pFileName, sw_path);
                return handle;
            }
        }
    }

    Msg("[Model Load Fixes] couldn't redirect %s\n", pFileName);
    // Fall back to original behavior
    return IFileSystem_Open_trampoline()(_this, pFileName, pOptions, pathID, pSize);
}

void ModelLoadHooks::Initialize() {
    try {

        // Get the filesystem interface using Sys_LoadInterface
        Msg("[Model Load Fixes] - Loading filesystem interface\n");
        if (!Sys_LoadInterface("filesystem_stdio", FILESYSTEM_INTERFACE_VERSION, NULL, (void**)&g_pFileSystem)) {
            Warning("[Model Load Fixes] - Could not load filesystem interface");
            return;
        }

        Msg("[Model Load Fixes] Successfully loaded filesystem interface\n");

        // Get the vtable and the Open function
        void** vtable = *(void***)g_pFileSystem;
        void* openFunc = vtable[2];  // Verify this index for your game version

        // Set up the hook
        Setup_Hook(IFileSystem_Open, openFunc);
        Msg("[Model Load Fixes] Successfully hooked IFileSystem::Open\n");
    }
    catch (...) {
        Msg("[Model Load Fixes] Exception in ModelLoadHooks::Initialize\n");
    }
}