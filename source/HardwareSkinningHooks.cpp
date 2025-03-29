#include "HardwareSkinningHooks.h"
#include "e_utils.h"  
#include "c_baseentity.h"
#include "iclientrenderable.h"
#include "engine/ivmodelinfo.h"
#include "interfaces/interfaces.h"
#include <memory_patcher.h>
#include "icliententity.h"
#include "bone_setup.h"
#include "studio.h"
#include "materialsystem/imaterialsystem.h"
#include "istudiorender.h"
#include "optimize.h"
#include "materialsystem/imesh.h"
#include "mathlib/vmatrix.h"
 

// Global variables for bone data handling
BoneData_t g_BONEDATA = { -1 };
static bool activate_holder = false;
static matrix3x4_t modelToWorld;

// Static variables for bone handling
static int bone_count = -1;

// Function pointer typedefs
typedef void* (__fastcall* F_StudioRenderFinal)(void*, void*, void*, void*, void*, void*, void*, void*, void*, void*, void*);
typedef void* (__fastcall* F_StudioBuildMeshGroup)(void*, void*, studiomeshgroup_t*, OptimizedModel::StripGroupHeader_t*, mstudiomesh_t*, studiohdr_t*);
typedef int(__fastcall* F_StudioDrawGroupHWSkin)(void*, void*, studiomeshgroup_t*, void*, void*);
typedef void* (__fastcall* F_malloc)(void*, void*, size_t);
typedef void(__fastcall* F_SetFixedFunctionStateSkinningMatrices)(void*, void*);

// Function pointers for hooks
F_StudioRenderFinal R_StudioRenderFinal = nullptr;
F_StudioBuildMeshGroup R_StudioBuildMeshGroup = nullptr;
F_StudioDrawGroupHWSkin R_StudioDrawGroupHWSkin = nullptr;
F_SetFixedFunctionStateSkinningMatrices CShaderAPIDX_SetFixedFunctionStateSkinningMatrices = nullptr;

// Type definition for method pointers, todo: work without maybe?
typedef void(__fastcall* srv_MethodSingleArg)(void*, void*, void*);
typedef void(__fastcall* srv_MethodDoubleArg)(void*, void*, void*, void*);
typedef void(__fastcall* srv_MethodTripleArg)(void*, void*, void*, void*, void*);
typedef void(__fastcall* srv_MethodQuadArg)(void*, void*, void*, void*, void*, void*);
typedef void* (__fastcall* srv_MethodSingleArgRet)(void*, void*);
typedef void* (__fastcall* srv_MethodQuadArgRet)(void*, void*, void*, void*, void*);

// Helper functions to manipulate matrices, these might be defined elsewhere right now and i actually didnt notice.

void MatrixInverseTR(const matrix3x4_t& in, matrix3x4_t& out)
{
    VMatrix tmp, inverse;
    tmp.CopyFrom3x4(in);
    inverse = tmp.InverseTR();
    memcpy(&out, &inverse, sizeof(matrix3x4_t));
}

void MatrixCopy(const matrix3x4_t& in, VMatrix& out)
{
	out.CopyFrom3x4(in);
}

// Hook implementation for StudioDrawGroupHWSkin
Define_method_Hook(int, R_StudioDrawGroupHWSkin, void*, IMatRenderContext* pRenderContext, studiomeshgroup_t* pGroup, IMesh* pMesh, ColorMeshInfo_t* pColorMeshInfo)
{
	Msg("Running R_StudioDrawGroupHWSkin\n");
    studiohdr_t* pStudioHdr = *(studiohdr_t**)((long int)_this + 44 * sizeof(void*));
    if (pStudioHdr->numbones == 1 || !activate_holder)
    {
        return R_StudioDrawGroupHWSkin_trampoline()(_this, pRenderContext, pGroup, pMesh, pColorMeshInfo);
    }

    int numberTrianglesRendered = 0;

    matrix3x4_t* m_pBoneToWorld = *(matrix3x4_t**)((intptr_t)_this + 39 * sizeof(void*));
    matrix3x4_t* m_PoseToWorld = *(matrix3x4_t**)((intptr_t)_this + 40 * sizeof(void*));
    int zero = 0;

    matrix3x4_t worldToModel;
    MatrixInvert(modelToWorld, worldToModel);
    matrix3x4_t temp_pBoneToWorld[512];
    for (int i = 0; i < pStudioHdr->numbones; i++)
    {
        mstudiobone_t* bdata = pStudioHdr->pBone(i);
        matrix3x4_t invert;
        MatrixInverseTR(bdata->poseToBone, invert);
        ConcatTransforms(m_PoseToWorld[i], invert, temp_pBoneToWorld[i]);
    }

    matrix3x4_t new_BoneToWorld[512];
    for (int i = 0; i < pStudioHdr->numbones; i++)
    {
        ConcatTransforms(worldToModel, temp_pBoneToWorld[i], new_BoneToWorld[i]);
    }

    matrix3x4_t new_PoseToWorld[512];
    for (int i = 0; i < pStudioHdr->numbones; i++)
    {
        mstudiobone_t* bdata = pStudioHdr->pBone(i);
        ConcatTransforms(new_BoneToWorld[i], bdata->poseToBone, new_PoseToWorld[i]);
    }

    matrix3x4_t viewmat;
    pRenderContext->GetMatrix(MATERIAL_VIEW, &viewmat);
    if (pStudioHdr->numbones == 1)
    {
        pRenderContext->MatrixMode(MATERIAL_MODEL);
        pRenderContext->LoadMatrix(m_PoseToWorld[0]);
        pRenderContext->SetNumBoneWeights(0);
        g_BONEDATA.bone_count = -1;
    }
    else
    {
        for (int i = 0; i < pStudioHdr->numbones; i++)
        {
            ConcatTransforms(modelToWorld, new_PoseToWorld[i], new_PoseToWorld[i]);
        }
    }

    for (int i = 0; i < pGroup->m_NumStrips; i++)
    {
        OptimizedModel::StripHeader_t* pStrip = &pGroup->m_pStripData[i];

        if (pStudioHdr->numbones > 1)
        {
            pRenderContext->SetNumBoneWeights(pStrip->numBones);

            // Will only activate if there's bone state changes, otherwise behaves like a software skin
            g_BONEDATA.bone_count = pStrip->numBoneStateChanges;
            for (int j = 0; j < pStrip->numBoneStateChanges; j++)
            {
                OptimizedModel::BoneStateChangeHeader_t* m_StateChange = pStrip->pBoneStateChange(j);
                if (m_StateChange->newBoneID < 0)
                    break;

                MatrixCopy(new_PoseToWorld[m_StateChange->newBoneID], g_BONEDATA.bone_matrices[m_StateChange->newBoneID]);
            }
        }
        // Tristrip optimization? If yes, mat_tristrip, or mat_triangles
        int flags = pStrip->flags & 2 ? 3 : 2;

        pMesh->SetColorMesh(NULL,0);
        pMesh->SetPrimitiveType((MaterialPrimitiveType_t)flags);
        pMesh->Draw(pStrip->indexOffset, pStrip->numIndices);
        pMesh->SetColorMesh(NULL,0);

        // Increment Magic
        void* m_uniqueTris_Base = *(void**)((intptr_t)pGroup + 28);
        void* m_pUniqueTris = (void*)((intptr_t)m_uniqueTris_Base + (4 * i));
        int triangle_count = *(int*)m_pUniqueTris;
        numberTrianglesRendered += triangle_count;
    }
    g_BONEDATA.bone_count = -1;

    if (pStudioHdr->numbones != 1)
    {
        pRenderContext->MatrixMode(MATERIAL_VIEW);
        pRenderContext->LoadMatrix(viewmat);
    }

    pRenderContext->MatrixMode(MATERIAL_MODEL);
    pRenderContext->LoadIdentity();

    return numberTrianglesRendered;
}

Define_method_Hook(void*, R_StudioBuildMeshGroup, void*, const char* pModelName, bool bNeedsTangentSpace, studiomeshgroup_t* pMeshGroup,
    OptimizedModel::StripGroupHeader_t* pStripGroup, mstudiomesh_t* pMesh,
    studiohdr_t* pStudioHdr, VertexFormat_t vertexFormat)
{
	Msg("Running R_StudioBuildMeshGroup\n");
    if (pStudioHdr->numbones > 0 && !(pStripGroup->flags & 0x02))
    {
        pMeshGroup->m_Flags |= 2u;
        bone_count = pStudioHdr->numbones;
    }
    else
    {
        bone_count = -1;
    }
    return R_StudioBuildMeshGroup_trampoline()(_this, pModelName, bNeedsTangentSpace, pMeshGroup, pStripGroup, pMesh, pStudioHdr, vertexFormat);
}

Define_method_Hook(void*, R_StudioRenderFinal, void*, IMatRenderContext* pRenderContext,
    int skin, int nBodyPartCount, void* pBodyPartInfo, IClientEntity* pClientEntity,
    IMaterial** ppMaterials, int* pMaterialFlags, int boneMask, int lod, ColorMeshInfo_t* pColorMeshes)
{
	Msg("Running StudioRenderFinal\n");

    Msg("Running m_rgflCoordinateFrame =\n");
    matrix3x4_t m_rgflCoordinateFrame = *(matrix3x4_t*)((intptr_t)pClientEntity + 776);  // NOTE!!!!! Offset might need adjustment, this is just what was given to me as is right now.
    Msg("Running StudioRenderFinal - MatrixCopy\n");

    // TODO, ACTUALLY DO THIS BECAUSE IT CRASHES AND I CANT FIGURE OUT WHY!!!!!
    //MatrixCopy(m_rgflCoordinateFrame, modelToWorld);

    Msg("Running StudioRenderFinal - activate_holder = true\n");
    activate_holder = true;
    Msg("Running StudioRenderFinal - R_StudioRenderFinal_trampoline\n");
    void* ret = R_StudioRenderFinal_trampoline()(_this, pRenderContext, skin, nBodyPartCount, pBodyPartInfo, pClientEntity, ppMaterials, pMaterialFlags, boneMask, lod, pColorMeshes);
    Msg("Running StudioRenderFinal - activate_holder = false\n");
    activate_holder = false;
    Msg("Running StudioRenderFinal - return\n");
    return ret;
}


// I can't actually find SetFixedFunctionStateSkinningMatrices, only SetSkinningMatrices, so i'm just going to use that for now.
// BUT unfortunately, I can't actually see this being called at all at runtime???
Define_method_Hook(void, SetFixedFunctionStateSkinningMatrices, void*)
{
	Msg("Running SetFixedFunctionStateSkinningMatrices\n");
    void* mystery_obj = (void*)((intptr_t)_this + 4);
    void* mystery_obj_vtable = *(void**)(mystery_obj);
    srv_MethodSingleArgRet GetMaxBlendMatricies = *(srv_MethodSingleArgRet*)((intptr_t)mystery_obj_vtable + 96);
    int blend_count = (int)GetMaxBlendMatricies(mystery_obj, edx);

    if (blend_count < 1)
        return;

    // guesses, (206?), 196, 164, copilot reckons 140, 
    IDirect3DDevice9* m_pD3DDevice = *(IDirect3DDevice9**)((intptr_t)_this + 164);  // NOTE!!!!! Offset might need adjustment, this is just what was given to me as is right now.

    if (g_BONEDATA.bone_count > 1)
        m_pD3DDevice->SetRenderState(D3DRS_INDEXEDVERTEXBLENDENABLE, TRUE);
    else
        m_pD3DDevice->SetRenderState(D3DRS_INDEXEDVERTEXBLENDENABLE, FALSE);

    for (int i = 0; i < g_BONEDATA.bone_count; i++)
    {
        VMatrix mat;
        MatrixCopy(g_BONEDATA.bone_matrices[i], mat);

        if (g_BONEDATA.bone_count != 1)
            MatrixTranspose(mat, mat);

        m_pD3DDevice->SetTransform(D3DTS_WORLDMATRIX(i), (D3DMATRIX*)&mat);
    }
}
void HardwareSkinningHooks::Initialize() {
    try {
        Msg("[Hardware Skinning] - Initializing...\n");

        // Get module handles
        auto studiorenderdll = GetModuleHandle("studiorender.dll");
        if (!studiorenderdll) {
            Msg("[Hardware Skinning] - studiorender.dll == NULL\n");
            return;
        }

        auto materialsystemdll = GetModuleHandle("materialsystem.dll");
        if (!materialsystemdll) {
            Msg("[Hardware Skinning] - materialsystem.dll == NULL\n");
            return;
        }

		// Define signature patterns for the functions we need to hook, copilot wanted to autocomplete these so i let it lmao, Still have yet to actually find the signatures
#ifdef _WIN64
        static const char StudioDrawGroupHWSkin_sign[] = "48 89 5C 24 ?? 48 89 74 24 ?? 57 48 83 EC 30 48 8B 01";
        static const char StudioBuildMeshGroup_sign[] = "40 53 55 56 57 41 54 41 55 41 56 41 57 48 83 EC 68";
        static const char StudioRenderFinal_sign[] = "40 55 53 56 57 41 54 41 55 41 56 41 57 48 8D AC 24";
        static const char SetFixedFunctionStateSkinningMatrices_sign[] = "40 53 48 83 EC 20 48 8B 81";
#else   // the 32 bit ones have been done though.
        static const char StudioDrawGroupHWSkin_sign[] = "55 8B EC 83 EC 0C 53 8B 5D ? 56";
        static const char StudioBuildMeshGroup_sign[] = "55 8B EC 81 EC 00 02 00 00";
        static const char StudioRenderFinal_sign[] = "55 8B EC 83 EC 10 53 57";
        static const char SetFixedFunctionStateSkinningMatrices_sign[] = "55 8B EC 83 EC 48 53 8B D9"; // to find this, search for D3DXMatrixTranspose, it's actually SetSkinningMatrices and SetFixedFunctionStateSkinningMatrices is baked in i think
#endif

        // Scan for function addresses
        auto StudioDrawGroupHWSkin_addr = ScanSign(studiorenderdll, StudioDrawGroupHWSkin_sign, sizeof(StudioDrawGroupHWSkin_sign) - 1);
        auto StudioBuildMeshGroup_addr = ScanSign(studiorenderdll, StudioBuildMeshGroup_sign, sizeof(StudioBuildMeshGroup_sign) - 1);
        auto StudioRenderFinal_addr = ScanSign(studiorenderdll, StudioRenderFinal_sign, sizeof(StudioRenderFinal_sign) - 1);
        auto SetFixedFunctionStateSkinningMatrices_addr = ScanSign(materialsystemdll, SetFixedFunctionStateSkinningMatrices_sign, sizeof(SetFixedFunctionStateSkinningMatrices_sign) - 1);

        modelToWorld.SetToIdentity();

        // Check if all addresses were found
        if (!StudioDrawGroupHWSkin_addr) {
            Msg("[Hardware Skinning] - StudioDrawGroupHWSkin == NULL\n");
            return;
        }
        if (!StudioBuildMeshGroup_addr) {
            Msg("[Hardware Skinning] - StudioBuildMeshGroup == NULL\n");
            return;
        }
        if (!StudioRenderFinal_addr) {
            Msg("[Hardware Skinning] - StudioRenderFinal == NULL\n");
            return;
        }
        if (!SetFixedFunctionStateSkinningMatrices_addr) {
            Msg("[Hardware Skinning] - SetFixedFunctionStateSkinningMatrices == NULL\n");
            // This one isn't critical, so we'll continue
        }

        // Set up hooks
        R_StudioDrawGroupHWSkin = (F_StudioDrawGroupHWSkin)StudioDrawGroupHWSkin_addr;
        R_StudioBuildMeshGroup = (F_StudioBuildMeshGroup)StudioBuildMeshGroup_addr;
        R_StudioRenderFinal = (F_StudioRenderFinal)StudioRenderFinal_addr;
        CShaderAPIDX_SetFixedFunctionStateSkinningMatrices =
            (F_SetFixedFunctionStateSkinningMatrices)SetFixedFunctionStateSkinningMatrices_addr;

        // Create and enable the hooks
        Setup_Hook(R_StudioDrawGroupHWSkin, StudioDrawGroupHWSkin_addr);
        Setup_Hook(R_StudioBuildMeshGroup, StudioBuildMeshGroup_addr);
        Setup_Hook(R_StudioRenderFinal, StudioRenderFinal_addr);

        if (SetFixedFunctionStateSkinningMatrices_addr) {
            Setup_Hook(SetFixedFunctionStateSkinningMatrices, SetFixedFunctionStateSkinningMatrices_addr);
        }

        Msg("[Hardware Skinning] - Successfully initialized all hooks\n");
    }
    catch (...) {
        Msg("[Hardware Skinning] - Exception in HardwareSkinningHooks::Initialize\n");
    }
}

void HardwareSkinningHooks::Shutdown() {
    try {
        // Disable all hooks
        m_StudioDrawGroupHWSkin_hook.Disable();
        m_StudioBuildMeshGroup_hook.Disable();
        m_StudioRenderFinal_hook.Disable();
        m_SetFixedFunctionStateSkinningMatrices_hook.Disable();

        // Reset global state
        g_BONEDATA.bone_count = -1;
        activate_holder = false;

        // Log shutdown completion
        Msg("[Hardware Skinning] - Shutdown complete\n");
    }
    catch (...) {
        Msg("[Hardware Skinning] - Exception in HardwareSkinningHooks::Shutdown\n");
    }
}