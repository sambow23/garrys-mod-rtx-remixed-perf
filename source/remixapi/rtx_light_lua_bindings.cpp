#ifdef _WIN64

#include "rtx_light_manager.h"
#include "./rtxlights/rtx_light_sphere.h"
#include "./rtxlights/rtx_light_rect.h"
#include "./rtxlights/rtx_light_disk.h"
#include "./rtxlights/rtx_light_distant.h"
#include "GarrysMod/Lua/Interface.h"
#include <tier0/dbg.h>

using namespace GarrysMod::Lua;

// Frame synchronization functions
LUA_FUNCTION(RTXBeginFrame) {
    RTXLightManager::Instance().BeginFrame();
    return 0;
}

LUA_FUNCTION(RTXEndFrame) {
    RTXLightManager::Instance().EndFrame();
    return 0;
}

// Entity validator registration
LUA_FUNCTION(RegisterRTXLightEntityValidator) {
    if (!LUA->IsType(1, GarrysMod::Lua::Type::FUNCTION)) {
        LUA->ThrowError("Expected function as argument 1");
        return 0;
    }

    // Store the function reference
    LUA->Push(1); // Push the function
    int functionRef = LUA->ReferenceCreate();

    // Create the validator function that will call back to Lua
    auto validator = [=](uint64_t entityID) -> bool {
        LUA->ReferencePush(functionRef); // Push the stored function
        LUA->PushNumber(static_cast<double>(entityID)); // Push entity ID
        LUA->Call(1, 1); // Call with 1 arg, expect 1 return

        bool exists = LUA->GetBool(-1);
        LUA->Pop(); // Pop the return value

        return exists;
    };

    // Register the validator with the RTX Light Manager
    RTXLightManager::Instance().RegisterLuaEntityValidator(validator);

    return 0;
}

// Sphere light creation
LUA_FUNCTION(CreateRTXSphereLight) {
    try {
        // Extract properties from Lua
        float x = LUA->CheckNumber(1);
        float y = LUA->CheckNumber(2);
        float z = LUA->CheckNumber(3);
        float radius = LUA->CheckNumber(4);
        float brightness = LUA->CheckNumber(5);
        float r = LUA->CheckNumber(6);
        float g = LUA->CheckNumber(7);
        float b = LUA->CheckNumber(8);
        uint64_t entityID = LUA->IsType(9, Type::NUMBER) ? static_cast<uint64_t>(LUA->GetNumber(9)) : 0;
        
        // Optional shaping parameters
        bool enableShaping = LUA->IsType(10, Type::BOOL) ? LUA->GetBool(10) : false;
        
        RTX::SphereProperties props;
        props.x = x;
        props.y = y;
        props.z = z;
        props.radius = radius;
        props.brightness = brightness;
        props.r = r / 255.0f;
        props.g = g / 255.0f;
        props.b = b / 255.0f;
        props.enableShaping = enableShaping;
        
        if (enableShaping && LUA->IsType(11, Type::NUMBER) && LUA->IsType(12, Type::NUMBER) && LUA->IsType(13, Type::NUMBER)) {
            props.shapingDirection[0] = LUA->GetNumber(11);
            props.shapingDirection[1] = LUA->GetNumber(12);
            props.shapingDirection[2] = LUA->GetNumber(13);
            
            if (LUA->IsType(14, Type::NUMBER)) {
                props.shapingConeAngle = LUA->GetNumber(14);
            }
            
            if (LUA->IsType(15, Type::NUMBER)) {
                props.shapingConeSoftness = LUA->GetNumber(15);
            }
        }
        
        Msg("[RTX Light Module] Creating sphere light at (%f,%f,%f) with radius %f\n", x, y, z, radius);
        
        auto handle = RTXLightManager::Instance().CreateSphereLight(props, entityID);
        if (!handle) {
            LUA->ThrowError("[RTX Remix Fixes] - Failed to create sphere light");
            return 0;
        }
        
        LUA->PushUserdata(handle);
        return 1;
    }
    catch (...) {
        Msg("[RTX Light Module] Exception in CreateRTXSphereLight\n");
        LUA->ThrowError("[RTX Remix Fixes] - Exception in sphere light creation");
        return 0;
    }
}

// Rectangle light creation
LUA_FUNCTION(CreateRTXRectLight) {
    try {
        // Extract properties from Lua
        float x = LUA->CheckNumber(1);
        float y = LUA->CheckNumber(2);
        float z = LUA->CheckNumber(3);
        float xSize = LUA->CheckNumber(4);
        float ySize = LUA->CheckNumber(5);
        float brightness = LUA->CheckNumber(6);
        float r = LUA->CheckNumber(7);
        float g = LUA->CheckNumber(8);
        float b = LUA->CheckNumber(9);
        uint64_t entityID = LUA->IsType(10, Type::NUMBER) ? static_cast<uint64_t>(LUA->GetNumber(10)) : 0;
        
        RTX::RectProperties props;
        props.x = x;
        props.y = y;
        props.z = z;
        props.xSize = xSize;
        props.ySize = ySize;
        props.brightness = brightness;
        props.r = r / 255.0f;
        props.g = g / 255.0f;
        props.b = b / 255.0f;
        
        // Default direction and axes if not provided
        props.dirX = 0.0f; props.dirY = 0.0f; props.dirZ = 1.0f;
        props.xAxisX = 1.0f; props.xAxisY = 0.0f; props.xAxisZ = 0.0f;
        props.yAxisX = 0.0f; props.yAxisY = 1.0f; props.yAxisZ = 0.0f;
        
        // Optional direction vector
        if (LUA->IsType(11, Type::NUMBER) && LUA->IsType(12, Type::NUMBER) && LUA->IsType(13, Type::NUMBER)) {
            props.dirX = LUA->GetNumber(11);
            props.dirY = LUA->GetNumber(12);
            props.dirZ = LUA->GetNumber(13);
        }
        
        // Optional X axis vector
        if (LUA->IsType(14, Type::NUMBER) && LUA->IsType(15, Type::NUMBER) && LUA->IsType(16, Type::NUMBER)) {
            props.xAxisX = LUA->GetNumber(14);
            props.xAxisY = LUA->GetNumber(15);
            props.xAxisZ = LUA->GetNumber(16);
        }
        
        // Optional Y axis vector
        if (LUA->IsType(17, Type::NUMBER) && LUA->IsType(18, Type::NUMBER) && LUA->IsType(19, Type::NUMBER)) {
            props.yAxisX = LUA->GetNumber(17);
            props.yAxisY = LUA->GetNumber(18);
            props.yAxisZ = LUA->GetNumber(19);
        }
        
        // Optional shaping parameters
        if (LUA->IsType(20, Type::BOOL)) {
            props.enableShaping = LUA->GetBool(20);
            
            if (props.enableShaping) {
                if (LUA->IsType(21, Type::NUMBER)) {
                    props.shapingConeAngle = LUA->GetNumber(21);
                }
                
                if (LUA->IsType(22, Type::NUMBER)) {
                    props.shapingConeSoftness = LUA->GetNumber(22);
                }
            }
        }
        
        Msg("[RTX Light Module] Creating rect light at (%f,%f,%f) with size %fx%f\n", x, y, z, xSize, ySize);
        
        auto handle = RTXLightManager::Instance().CreateRectLight(props, entityID);
        if (!handle) {
            LUA->ThrowError("[RTX Remix Fixes] - Failed to create rect light");
            return 0;
        }
        
        LUA->PushUserdata(handle);
        return 1;
    }
    catch (...) {
        Msg("[RTX Light Module] Exception in CreateRTXRectLight\n");
        LUA->ThrowError("[RTX Remix Fixes] - Exception in rect light creation");
        return 0;
    }
}

// Disk light creation
LUA_FUNCTION(CreateRTXDiskLight) {
    try {
        // Extract properties from Lua
        float x = LUA->CheckNumber(1);
        float y = LUA->CheckNumber(2);
        float z = LUA->CheckNumber(3);
        float xRadius = LUA->CheckNumber(4);
        float yRadius = LUA->CheckNumber(5);
        float brightness = LUA->CheckNumber(6);
        float r = LUA->CheckNumber(7);
        float g = LUA->CheckNumber(8);
        float b = LUA->CheckNumber(9);
        uint64_t entityID = LUA->IsType(10, Type::NUMBER) ? static_cast<uint64_t>(LUA->GetNumber(10)) : 0;
        
        RTX::DiskProperties props;
        props.x = x;
        props.y = y;
        props.z = z;
        props.xRadius = xRadius;
        props.yRadius = yRadius;
        props.brightness = brightness;
        props.r = r / 255.0f;
        props.g = g / 255.0f;
        props.b = b / 255.0f;
        
        // Default direction and axes if not provided
        props.dirX = 0.0f; props.dirY = 0.0f; props.dirZ = 1.0f;
        props.xAxisX = 1.0f; props.xAxisY = 0.0f; props.xAxisZ = 0.0f;
        props.yAxisX = 0.0f; props.yAxisY = 1.0f; props.yAxisZ = 0.0f;
        
        // Optional direction vector
        if (LUA->IsType(11, Type::NUMBER) && LUA->IsType(12, Type::NUMBER) && LUA->IsType(13, Type::NUMBER)) {
            props.dirX = LUA->GetNumber(11);
            props.dirY = LUA->GetNumber(12);
            props.dirZ = LUA->GetNumber(13);
        }
        
        // Optional X axis vector
        if (LUA->IsType(14, Type::NUMBER) && LUA->IsType(15, Type::NUMBER) && LUA->IsType(16, Type::NUMBER)) {
            props.xAxisX = LUA->GetNumber(14);
            props.xAxisY = LUA->GetNumber(15);
            props.xAxisZ = LUA->GetNumber(16);
        }
        
        // Optional Y axis vector
        if (LUA->IsType(17, Type::NUMBER) && LUA->IsType(18, Type::NUMBER) && LUA->IsType(19, Type::NUMBER)) {
            props.yAxisX = LUA->GetNumber(17);
            props.yAxisY = LUA->GetNumber(18);
            props.yAxisZ = LUA->GetNumber(19);
        }
        
        // Optional shaping parameters
        if (LUA->IsType(20, Type::BOOL)) {
            props.enableShaping = LUA->GetBool(20);
            
            if (props.enableShaping) {
                if (LUA->IsType(21, Type::NUMBER)) {
                    props.shapingConeAngle = LUA->GetNumber(21);
                }
                
                if (LUA->IsType(22, Type::NUMBER)) {
                    props.shapingConeSoftness = LUA->GetNumber(22);
                }
            }
        }
        
        Msg("[RTX Light Module] Creating disk light at (%f,%f,%f) with radii %fx%f\n", x, y, z, xRadius, yRadius);
        
        auto handle = RTXLightManager::Instance().CreateDiskLight(props, entityID);
        if (!handle) {
            LUA->ThrowError("[RTX Remix Fixes] - Failed to create disk light");
            return 0;
        }
        
        LUA->PushUserdata(handle);
        return 1;
    }
    catch (...) {
        Msg("[RTX Light Module] Exception in CreateRTXDiskLight\n");
        LUA->ThrowError("[RTX Remix Fixes] - Exception in disk light creation");
        return 0;
    }
}

// Distant light creation
LUA_FUNCTION(CreateRTXDistantLight) {
    try {
        // Extract properties from Lua
        float dirX = LUA->CheckNumber(1);
        float dirY = LUA->CheckNumber(2);
        float dirZ = LUA->CheckNumber(3);
        float angularDiameter = LUA->CheckNumber(4);
        float brightness = LUA->CheckNumber(5);
        float r = LUA->CheckNumber(6);
        float g = LUA->CheckNumber(7);
        float b = LUA->CheckNumber(8);
        uint64_t entityID = LUA->IsType(9, Type::NUMBER) ? static_cast<uint64_t>(LUA->GetNumber(9)) : 0;
        
        RTX::DistantProperties props;
        props.dirX = dirX;
        props.dirY = dirY;
        props.dirZ = dirZ;
        props.angularDiameter = angularDiameter;
        props.brightness = brightness;
        props.r = r / 255.0f;
        props.g = g / 255.0f;
        props.b = b / 255.0f;
        
        Msg("[RTX Light Module] Creating distant light with direction (%f,%f,%f) and angular diameter %f\n", 
            dirX, dirY, dirZ, angularDiameter);
        
        auto handle = RTXLightManager::Instance().CreateDistantLight(props, entityID);
        if (!handle) {
            LUA->ThrowError("[RTX Remix Fixes] - Failed to create distant light");
            return 0;
        }
        
        LUA->PushUserdata(handle);
        return 1;
    }
    catch (...) {
        Msg("[RTX Light Module] Exception in CreateRTXDistantLight\n");
        LUA->ThrowError("[RTX Remix Fixes] - Exception in distant light creation");
        return 0;
    }
}

// Generic light update function
LUA_FUNCTION(UpdateRTXLight) {
    try {
        // Validate userdata type
        if (!LUA->IsType(1, Type::USERDATA)) {
            Msg("[RTX Remix Fixes] First argument must be userdata\n");
            LUA->PushBool(false);
            return 1;
        }

        auto handle = static_cast<remixapi_LightHandle>(LUA->GetUserdata(1));
        if (!handle) {
            Msg("[RTX Remix Fixes] Invalid light handle (null)\n");
            LUA->PushBool(false);
            return 1;
        }

        // Additional handle validation
        bool isValidHandle = false;
        try {
            auto& manager = RTXLightManager::Instance();
            isValidHandle = manager.IsValidHandle(handle);
        } catch (...) {
            Msg("[RTX Remix Fixes] Exception checking handle validity\n");
            LUA->PushBool(false);
            return 1;
        }

        if (!isValidHandle) {
            Msg("[RTX Remix Fixes] Invalid light handle (not found)\n");
            LUA->PushBool(false);
            return 1;
        }

        // Get light type
        int lightType = 0; // Default to sphere light
        if (LUA->IsType(2, Type::NUMBER)) {
            lightType = LUA->GetNumber(2);
        }

        bool success = false;
        remixapi_LightHandle newHandle = nullptr;

        // Different update logic based on light type
        switch (lightType) {
            case 0: { // Sphere light
                float x = LUA->CheckNumber(3);
                float y = LUA->CheckNumber(4);
                float z = LUA->CheckNumber(5);
                float radius = LUA->CheckNumber(6);
                float brightness = LUA->CheckNumber(7);
                float r = LUA->CheckNumber(8);
                float g = LUA->CheckNumber(9);
                float b = LUA->CheckNumber(10);
                
                // Get shaping parameters if provided
                bool enableShaping = false;
                float dirX = 0.0f, dirY = 0.0f, dirZ = 1.0f;
                float coneAngle = 120.0f;
                float coneSoftness = 0.2f;
                
                if (LUA->IsType(11, Type::BOOL)) {
                    enableShaping = LUA->GetBool(11);
                    
                    if (LUA->IsType(12, Type::NUMBER) && 
                        LUA->IsType(13, Type::NUMBER) && 
                        LUA->IsType(14, Type::NUMBER)) {
                        dirX = LUA->GetNumber(12);
                        dirY = LUA->GetNumber(13);
                        dirZ = LUA->GetNumber(14);
                    }
                    
                    if (LUA->IsType(15, Type::NUMBER)) {
                        coneAngle = LUA->GetNumber(15);
                    }
                    
                    if (LUA->IsType(16, Type::NUMBER)) {
                        coneSoftness = LUA->GetNumber(16);
                    }
                }
                
                RTX::SphereProperties props;
                props.x = x;
                props.y = y;
                props.z = z;
                props.radius = radius;
                props.brightness = brightness;
                props.r = r / 255.0f;
                props.g = g / 255.0f;
                props.b = b / 255.0f;
                props.enableShaping = enableShaping;
                props.shapingDirection[0] = dirX;
                props.shapingDirection[1] = dirY;
                props.shapingDirection[2] = dirZ;
                props.shapingConeAngle = coneAngle;
                props.shapingConeSoftness = coneSoftness;
                
                success = RTXLightManager::Instance().UpdateLight(handle, &props, lightType, &newHandle);
                break;
            }
            
            case 1: { // Rect light
                float x = LUA->CheckNumber(3);
                float y = LUA->CheckNumber(4);
                float z = LUA->CheckNumber(5);
                float xSize = LUA->CheckNumber(6);
                float ySize = LUA->CheckNumber(7);
                float brightness = LUA->CheckNumber(8);
                float r = LUA->CheckNumber(9);
                float g = LUA->CheckNumber(10);
                float b = LUA->CheckNumber(11);
                
                RTX::RectProperties props;
                props.x = x;
                props.y = y;
                props.z = z;
                props.xSize = xSize;
                props.ySize = ySize;
                props.brightness = brightness;
                props.r = r / 255.0f;
                props.g = g / 255.0f;
                props.b = b / 255.0f;
                
                // Default direction and axes
                props.dirX = 0.0f; props.dirY = 0.0f; props.dirZ = 1.0f;
                props.xAxisX = 1.0f; props.xAxisY = 0.0f; props.xAxisZ = 0.0f;
                props.yAxisX = 0.0f; props.yAxisY = 1.0f; props.yAxisZ = 0.0f;
                
                // Optional direction
                if (LUA->IsType(12, Type::NUMBER) && LUA->IsType(13, Type::NUMBER) && LUA->IsType(14, Type::NUMBER)) {
                    props.dirX = LUA->GetNumber(12);
                    props.dirY = LUA->GetNumber(13);
                    props.dirZ = LUA->GetNumber(14);
                }
                
                success = RTXLightManager::Instance().UpdateLight(handle, &props, lightType, &newHandle);
                break;
            }
            
            case 2: { // Disk light
                float x = LUA->CheckNumber(3);
                float y = LUA->CheckNumber(4);
                float z = LUA->CheckNumber(5);
                float xRadius = LUA->CheckNumber(6);
                float yRadius = LUA->CheckNumber(7);
                float brightness = LUA->CheckNumber(8);
                float r = LUA->CheckNumber(9);
                float g = LUA->CheckNumber(10);
                float b = LUA->CheckNumber(11);
                
                RTX::DiskProperties props;
                props.x = x;
                props.y = y;
                props.z = z;
                props.xRadius = xRadius;
                props.yRadius = yRadius;
                props.brightness = brightness;
                props.r = r / 255.0f;
                props.g = g / 255.0f;
                props.b = b / 255.0f;
                
                // Default direction and axes
                props.dirX = 0.0f; props.dirY = 0.0f; props.dirZ = 1.0f;
                props.xAxisX = 1.0f; props.xAxisY = 0.0f; props.xAxisZ = 0.0f;
                props.yAxisX = 0.0f; props.yAxisY = 1.0f; props.yAxisZ = 0.0f;
                
                // Optional direction
                if (LUA->IsType(12, Type::NUMBER) && LUA->IsType(13, Type::NUMBER) && LUA->IsType(14, Type::NUMBER)) {
                    props.dirX = LUA->GetNumber(12);
                    props.dirY = LUA->GetNumber(13);
                    props.dirZ = LUA->GetNumber(14);
                }
                
                success = RTXLightManager::Instance().UpdateLight(handle, &props, lightType, &newHandle);
                break;
            }
            
            case 3: { // Distant light
                float dirX = LUA->CheckNumber(3);
                float dirY = LUA->CheckNumber(4);
                float dirZ = LUA->CheckNumber(5);
                float angularDiameter = LUA->CheckNumber(6);
                float brightness = LUA->CheckNumber(7);
                float r = LUA->CheckNumber(8);
                float g = LUA->CheckNumber(9);
                float b = LUA->CheckNumber(10);
                
                RTX::DistantProperties props;
                props.dirX = dirX;
                props.dirY = dirY;
                props.dirZ = dirZ;
                props.angularDiameter = angularDiameter;
                props.brightness = brightness;
                props.r = r / 255.0f;
                props.g = g / 255.0f;
                props.b = b / 255.0f;
                
                success = RTXLightManager::Instance().UpdateLight(handle, &props, lightType, &newHandle);
                break;
            }
            
            default:
                Msg("[RTX Remix Fixes] Invalid light type: %d\n", lightType);
                LUA->PushBool(false);
                return 1;
        }

        LUA->PushBool(success);
        if (success && newHandle != handle) {
            LUA->PushUserdata(newHandle);
            return 2;
        }
        return 1;
    }
    catch (...) {
        Msg("[RTX Remix Fixes] Exception in UpdateRTXLight\n");
        LUA->PushBool(false);
        return 1;
    }
}

// Light destruction function
LUA_FUNCTION(DestroyRTXLight) {
    try {
        auto handle = static_cast<remixapi_LightHandle>(LUA->GetUserdata(1));
        RTXLightManager::Instance().DestroyLight(handle);
        return 0;
    }
    catch (...) {
        Msg("[RTX Remix Fixes] Exception in DestroyRTXLight\n");
        return 0;
    }
}

// Draw all lights
LUA_FUNCTION(DrawRTXLights) { 
    try {
        RTXLightManager::Instance().DrawLights();
        return 0;
    }
    catch (...) {
        Msg("[RTX Remix Fixes] Exception in DrawRTXLights\n");
        return 0;
    }
}

// This function is called from RTXLightManager::InitializeLuaBindings
void RegisterRTXLightBindings(GarrysMod::Lua::ILuaBase* LUA) {
    LUA->PushCFunction(RTXBeginFrame);
    LUA->SetField(-2, "RTXBeginFrame");
    
    LUA->PushCFunction(RTXEndFrame);
    LUA->SetField(-2, "RTXEndFrame");

    LUA->PushCFunction(RegisterRTXLightEntityValidator);
    LUA->SetField(-2, "RegisterRTXLightEntityValidator");

    // Register different light type creators
    LUA->PushCFunction(CreateRTXSphereLight);
    LUA->SetField(-2, "CreateRTXSphereLight");
    
    LUA->PushCFunction(CreateRTXRectLight);
    LUA->SetField(-2, "CreateRTXRectLight");
    
    LUA->PushCFunction(CreateRTXDiskLight);
    LUA->SetField(-2, "CreateRTXDiskLight");
    
    LUA->PushCFunction(CreateRTXDistantLight);
    LUA->SetField(-2, "CreateRTXDistantLight");
    
    // Register common functions
    LUA->PushCFunction(UpdateRTXLight);
    LUA->SetField(-2, "UpdateRTXLight");
    
    LUA->PushCFunction(DestroyRTXLight);
    LUA->SetField(-2, "DestroyRTXLight");
    
    LUA->PushCFunction(DrawRTXLights);
    LUA->SetField(-2, "DrawRTXLights");
}

#endif // _WIN64