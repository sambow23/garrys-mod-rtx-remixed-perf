#pragma once

#include "e_utils.h"

// External functions to control static lighting
void SetForceStaticLighting(bool enable);
bool GetForceStaticLighting();
void SetModelDrawHookEnabled(bool enable);

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