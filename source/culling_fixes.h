

#pragma once
#include <Windows.h>
#include "engine/ivmodelrender.h"
#include "model_types.h"
#include "e_utils.h"
class CullingHooks {
public:
    static CullingHooks& Instance() {
        static CullingHooks instance;
        return instance;
    }

    void Initialize();
    void Shutdown();
private:
    // Hook objects
    Detouring::Hook m_DrawModelExecute_hook;

};