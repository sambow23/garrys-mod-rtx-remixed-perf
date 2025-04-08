#pragma once
#include "GarrysMod/Lua/Interface.h"

#include <Windows.h>
#include <d3d9.h>

#ifdef _WIN64
#include <remix/remix.h>
#include <remix/remix_c.h>
#endif

namespace RemixAPI {
    // Initialize Remix API Lua functions
    void Initialize(GarrysMod::Lua::ILuaBase* LUA);
    
    // Clear Remix resources
    void ClearRemixResources();
}