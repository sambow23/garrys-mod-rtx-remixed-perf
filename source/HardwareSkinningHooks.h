#pragma once
#include <Windows.h>
#include "studio.h"
#include "e_utils.h"
#include <d3d9.h>
#include "mathlib/vmatrix.h" 

class HardwareSkinningHooks {
public:
    static HardwareSkinningHooks& Instance() {
        static HardwareSkinningHooks instance;
        return instance;
    }

    void Initialize();
    void Shutdown();
private:
    // Hook objects
    Detouring::Hook m_StudioDrawGroupHWSkin_hook;
    Detouring::Hook m_StudioBuildMeshGroup_hook;
    Detouring::Hook m_StudioRenderFinal_hook;
    Detouring::Hook m_SetFixedFunctionStateSkinningMatrices_hook;
};

// Global data structure for bone data
struct BoneData_t {
    int bone_count;
    VMatrix bone_matrices[512];
};

extern BoneData_t g_BONEDATA;
