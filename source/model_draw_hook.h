#pragma once

#include "e_utils.h"
#include "mathlib/vector.h"
#include "mathlib/mathlib.h"
#include "istudiorender.h"
#include "detouring/hook.hpp"
#include "engine/ivmodelrender.h"

// External functions to control static lighting
void SetForceStaticLighting(bool enable);
bool GetForceStaticLighting();
void SetModelDrawHookEnabled(bool enable);

// DrawModelInfo_t structure (based on Source SDK and IDA analysis)
// This is passed to CModelRender::DrawModel at vtable offset 0x90
// Note: Renamed to avoid conflict with Source SDK's DrawModelInfo_t in istudiorender.h
struct DrawModelInfo_Internal_t
{
    // Based on actual IDA disassembly of CStaticProp::DrawModel
    // Structure starts at [rsp+98h+var_68] and is built from offset 0x00
    char m_Matrix[16];               // 0x00 - 16 bytes matrix/position data (xmm0)
    float m_Float1;                  // 0x10 - 4 bytes float value
    float m_Float2;                  // 0x14 - 4 bytes float value  
    void* m_pEntity;                 // 0x18 - 8 bytes pointer (entity or null)
    void* m_pStudioHdr;              // 0x20 - 8 bytes pointer from [entity+30h]
    void* m_pPointer1;               // 0x28 - 8 bytes pointer to [entity+68h]
    void* m_pZero1;                  // 0x30 - 8 bytes zero
    void* m_pPointer2;               // 0x38 - 8 bytes pointer to [entity+0B4h]
    int m_DrawFlags;                 // 0x40 - 4 bytes FLAGS (STUDIO_STATIC_LIGHTING = 0x10)
    int m_MinusOne1;                 // 0x44 - 4 bytes constant -1
    int m_ByteValue;                 // 0x48 - 4 bytes byte value from [entity+3Eh]
    void* m_pZero2;                  // 0x4C - 8 bytes zero  
    int m_MinusOne2;                 // 0x54 - 4 bytes constant -1
    short m_WordValue;               // 0x58 - 2 bytes word value from [entity+3Ah]
    // Structure may have more padding but we only need up to m_DrawFlags
};

class ModelDrawHook {
public:
    static ModelDrawHook& Instance();
    void Initialize();
    void Shutdown();

private:
    ModelDrawHook() = default;
    ~ModelDrawHook() = default;

    // Prevent copying
    ModelDrawHook(const ModelDrawHook&) = delete;
    ModelDrawHook& operator=(const ModelDrawHook&) = delete;

    bool m_bInitialized = false;
}; 