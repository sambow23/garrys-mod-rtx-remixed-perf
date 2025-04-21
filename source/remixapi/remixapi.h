#ifdef _WIN64

#pragma once
#include "GarrysMod/Lua/Interface.h"

#include <Windows.h>
#include <d3d9.h>

#include <remix/remix.h>
#include <remix/remix_c.h>

namespace RemixAPI {
    // Initialize Remix API Lua functions
    void Initialize(GarrysMod::Lua::ILuaBase* LUA);
    
    // Clear Remix resources
    void ClearRemixResources();
}
#endif