// cursed but it fixes compile errors for x32
#ifdef _WIN64

#include "rtx_light_manager.h"
#include <tier0/dbg.h>
#include <algorithm>

extern remix::Interface* g_remix;

RTXLightManager& RTXLightManager::Instance() {
    static RTXLightManager instance;
    return instance;
}

RTXLightManager::RTXLightManager() 
    : m_remix(nullptr)
    , m_initialized(false)
    , m_isFrameActive(false) {
    InitializeCriticalSection(&m_lightCS);
    InitializeCriticalSection(&m_updateCS);
}

RTXLightManager::~RTXLightManager() {
    Shutdown();
    DeleteCriticalSection(&m_lightCS);
    DeleteCriticalSection(&m_updateCS);
}

void RTXLightManager::BeginFrame() {
    EnterCriticalSection(&m_updateCS);
    m_isFrameActive = true;
    
    // Process any pending destroys from last frame
    for (const auto& light : m_lightsToDestroy) {
        if (m_remix && light.handle) {
            m_remix->DestroyLight(light.handle);
        }
    }
    m_lightsToDestroy.clear();

    // Store current lights that need updates for recreation
    std::vector<remixapi_LightHandle> handlesToUpdate;
    while (!m_pendingUpdates.empty()) {
        const auto& update = m_pendingUpdates.front();
        if (update.needsUpdate) {
            handlesToUpdate.push_back(update.handle);
        }
        m_pendingUpdates.pop();
    }

    // Remove lights that need updates
    for (const auto& handleToUpdate : handlesToUpdate) {
        for (auto it = m_lights.begin(); it != m_lights.end(); ) {
            if (it->handle == handleToUpdate) {
                m_lightsToDestroy.push_back(*it);
                it = m_lights.erase(it);
            } else {
                ++it;
            }
        }
    }

    ProcessPendingUpdates();
    LeaveCriticalSection(&m_updateCS);
}

void RTXLightManager::EndFrame() {
    EnterCriticalSection(&m_updateCS);
    m_isFrameActive = false;
    ProcessPendingUpdates();
    LeaveCriticalSection(&m_updateCS);
}

bool RTXLightManager::IsValidHandle(remixapi_LightHandle handle) const {
    if (!m_initialized || !m_remix || !handle) {
        return false;
    }

    // Check if handle exists in our managed lights
    for (const auto& light : m_lights) {
        if (light.handle == handle) {
            return true;
        }
    }

    // Check pending updates
    std::queue<PendingUpdate> tempQueue = m_pendingUpdates;
    while (!tempQueue.empty()) {
        if (tempQueue.front().handle == handle) {
            return true;
        }
        tempQueue.pop();
    }

    return false;
}

void RTXLightManager::ProcessPendingUpdates() {
    if (!m_initialized || !m_remix) return;

    EnterCriticalSection(&m_lightCS);
    
    try {
        while (!m_pendingUpdates.empty()) {
            auto& update = m_pendingUpdates.front();
            
            if (update.needsUpdate && update.handle) {
                LogMessage("Processing update for light %p\n", update.handle);

                // Validate handle before processing
                if (!IsValidHandle(update.handle)) {
                    LogMessage("Warning: Skipping update for invalid handle %p\n", update.handle);
                    m_pendingUpdates.pop();
                    continue;
                }

                // First destroy the old light if it exists
                for (auto it = m_lights.begin(); it != m_lights.end();) {
                    if (it->handle == update.handle) {
                        if (m_remix) {
                            LogMessage("Destroying old light %p\n", it->handle);
                            m_remix->DestroyLight(it->handle);
                        }
                        it = m_lights.erase(it);
                    } else {
                        ++it;
                    }
                }

                // Create new light with updated properties
                auto sphereLight = CreateSphereLight(update.properties);
                auto lightInfo = CreateLightInfo(sphereLight);
                
                auto result = m_remix->CreateLight(lightInfo);
                if (result) {
                    // Add as new light
                    ManagedLight newLight{};
                    newLight.handle = result.value();
                    newLight.properties = update.properties;
                    newLight.lastUpdateTime = GetTickCount64() / 1000.0f;
                    newLight.needsUpdate = false;
                    
                    m_lights.push_back(newLight);

                    // Important: Update the original handle to match the new one
                    update.handle = newLight.handle;

                    LogMessage("Created new light %p with updated position (%f, %f, %f)\n", 
                        newLight.handle, 
                        update.properties.x,
                        update.properties.y,
                        update.properties.z);
                } else {
                    LogMessage("Failed to create new light during update\n");
                }
            }
            
            m_pendingUpdates.pop();
        }

        // Draw all lights immediately after updates
        for (const auto& light : m_lights) {
            if (light.handle) {
                auto drawResult = m_remix->DrawLightInstance(light.handle);
                if (!static_cast<bool>(drawResult)) {
                    LogMessage("Failed to draw light handle: %p\n", light.handle);
                }
            }
        }
    }
    catch (const std::exception& e) {
        LogMessage("Exception in ProcessPendingUpdates: %s\n", e.what());
    }
    catch (...) {
        LogMessage("Unknown exception in ProcessPendingUpdates\n");
    }
    
    LeaveCriticalSection(&m_lightCS);
}

void RTXLightManager::Initialize(remix::Interface* remixInterface) {
    EnterCriticalSection(&m_lightCS);
    m_remix = remixInterface;
    m_initialized = true;
    m_lights.reserve(100);  // Pre-allocate space for lights
    LeaveCriticalSection(&m_lightCS);
    LogMessage("RTX Light Manager initialized\n");
}

void RTXLightManager::Shutdown() {
    EnterCriticalSection(&m_lightCS);
    for (const auto& light : m_lights) {
        if (m_remix && light.handle) {
            m_remix->DestroyLight(light.handle);
        }
    }
    m_lights.clear();
    m_initialized = false;
    m_remix = nullptr;
    LeaveCriticalSection(&m_lightCS);
}

bool RTXLightManager::HasLightForEntity(uint64_t entityID) const {
    EnterCriticalSection(&m_lightCS);  // Use Critical Section instead of mutex
    bool exists = m_lightsByEntityID.find(entityID) != m_lightsByEntityID.end();
    LeaveCriticalSection(&m_lightCS);
    return exists;
}

remixapi_LightHandle RTXLightManager::CreateLight(const LightProperties& props, uint64_t entityID) {
    if (!m_initialized || !m_remix) {
        LogMessage("Cannot create light: Manager not initialized\n");
        return nullptr;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Check if we already have a light for this entity
        if (HasLightForEntity(entityID)) {
            LogMessage("Warning: Attempted to create duplicate light for entity %llu\n", entityID);
            auto existingHandle = m_lightsByEntityID[entityID].handle;
            LeaveCriticalSection(&m_lightCS);
            return existingHandle;
        }

        LogMessage("Creating light at (%f, %f, %f) with size %f\n", 
            props.x, props.y, props.z, props.size);

        auto sphereLight = remixapi_LightInfoSphereEXT{};
        sphereLight.sType = REMIXAPI_STRUCT_TYPE_LIGHT_INFO_SPHERE_EXT;
        sphereLight.position = {props.x, props.y, props.z};
        sphereLight.radius = props.size;
        sphereLight.shaping_hasvalue = false;
        memset(&sphereLight.shaping_value, 0, sizeof(sphereLight.shaping_value));

        auto lightInfo = remixapi_LightInfo{};
        lightInfo.sType = REMIXAPI_STRUCT_TYPE_LIGHT_INFO;
        lightInfo.pNext = &sphereLight;
        lightInfo.hash = GenerateLightHash();
        lightInfo.radiance = {
            props.r * props.brightness,
            props.g * props.brightness,
            props.b * props.brightness
        };

        auto result = m_remix->CreateLight(lightInfo);
        if (!result) {
            LogMessage("Remix CreateLight failed\n");
            LeaveCriticalSection(&m_lightCS);
            return nullptr;
        }

        ManagedLight managedLight{};
        managedLight.handle = result.value();
        managedLight.properties = props;
        managedLight.lastUpdateTime = GetTickCount64() / 1000.0f;
        managedLight.needsUpdate = false;

        // Add to both tracking containers
        m_lights.push_back(managedLight);
        m_lightsByEntityID[entityID] = managedLight;
        
        LogMessage("Successfully created light handle: %p (Total lights: %d)\n", 
            managedLight.handle, m_lights.size());

        LeaveCriticalSection(&m_lightCS);
        return managedLight.handle;
    }
    catch (...) {
        LogMessage("Exception in CreateLight\n");
        LeaveCriticalSection(&m_lightCS);
        return nullptr;
    }
}

void RTXLightManager::RegisterLuaEntityValidator(std::function<bool(uint64_t)> validator) {
    m_luaEntityValidator = validator;
}

void RTXLightManager::ValidateState() {
    if (!m_initialized || !m_remix) return;

    EnterCriticalSection(&m_lightCS);
    
    try {
        // First pass: validate RTX light handles and build a list of invalid ones
        std::vector<remixapi_LightHandle> invalidHandles;
        for (const auto& light : m_lights) {
            if (!light.handle) {
                LogMessage("Found null light handle\n");
                invalidHandles.push_back(light.handle);
                continue;
            }

            // Try to draw the light as a validity check
            auto result = m_remix->DrawLightInstance(light.handle);
            if (!static_cast<bool>(result)) {
                LogMessage("Found invalid light handle: %p\n", light.handle);
                invalidHandles.push_back(light.handle);
            }
        }

        // Second pass: validate entities and their associated lights
        for (auto it = m_lightsByEntityID.begin(); it != m_lightsByEntityID.end(); ) {
            bool shouldKeep = false;

            // Check if the entity still exists in Lua
            if (m_luaEntityValidator) {
                shouldKeep = m_luaEntityValidator(it->first);
            }

            // Also check if the light handle is valid
            if (shouldKeep) {
                auto handle = it->second.handle;
                shouldKeep = std::find(invalidHandles.begin(), invalidHandles.end(), handle) == invalidHandles.end();
            }

            if (!shouldKeep) {
                LogMessage("Removing light for invalid entity %llu with handle %p\n", 
                    it->first, it->second.handle);
                
                // Clean up the RTX light
                if (it->second.handle) {
                    m_remix->DestroyLight(it->second.handle);
                }

                // Remove from main lights vector
                auto lightIt = std::find_if(m_lights.begin(), m_lights.end(),
                    [handle = it->second.handle](const ManagedLight& light) {
                        return light.handle == handle;
                    });
                
                if (lightIt != m_lights.end()) {
                    m_lights.erase(lightIt);
                }

                // Remove from entity tracking
                it = m_lightsByEntityID.erase(it);
            } else {
                ++it;
            }
        }

        LogMessage("State validation complete. Remaining lights: %d, Tracked entities: %d\n", 
            m_lights.size(), m_lightsByEntityID.size());
    }
    catch (const std::exception& e) {
        LogMessage("Exception in ValidateState: %s\n", e.what());
    }
    catch (...) {
        LogMessage("Unknown exception in ValidateState\n");
    }

    LeaveCriticalSection(&m_lightCS);
}

// Add a method to generate unique hashes
uint64_t RTXLightManager::GenerateLightHash() const {
    static uint64_t counter = 0;
    return (static_cast<uint64_t>(GetCurrentProcessId()) << 32) | (++counter);
}

bool RTXLightManager::UpdateLight(remixapi_LightHandle handle, const LightProperties& props, remixapi_LightHandle* newHandle) {
    if (!m_initialized || !m_remix) return false;

    EnterCriticalSection(&m_updateCS);
    
    try {
        // Verify the light exists before queuing update
        bool lightExists = false;
        for (const auto& light : m_lights) {
            if (light.handle == handle) {
                lightExists = true;
                break;
            }
        }

        if (!lightExists) {
            LogMessage("Warning: Attempting to update non-existent light %p\n", handle);
            LeaveCriticalSection(&m_updateCS);
            return false;
        }

        // Queue the update
        PendingUpdate update;
        update.handle = handle;
        update.properties = props;
        update.needsUpdate = true;
        update.requiresRecreation = true;

        LogMessage("Queueing update for light %p at position (%f, %f, %f)\n", 
            handle, props.x, props.y, props.z);

        m_pendingUpdates.push(update);

        // Process immediately if not in active frame
        if (!m_isFrameActive) {
            ProcessPendingUpdates();
            
            // Find the new handle if requested
            if (newHandle) {
                for (const auto& light : m_lights) {
                    if (light.properties.x == props.x && 
                        light.properties.y == props.y && 
                        light.properties.z == props.z) {
                        *newHandle = light.handle;
                        break;
                    }
                }
            }
        }
    }
    catch (...) {
        LogMessage("Exception in UpdateLight\n");
        LeaveCriticalSection(&m_updateCS);
        return false;
    }

    LeaveCriticalSection(&m_updateCS);
    return true;
}

void RTXLightManager::DestroyLight(remixapi_LightHandle handle) {
    EnterCriticalSection(&m_lightCS);  // Just use one Critical Section
    
    try {
        // Find and remove from entity tracking
        for (auto it = m_lightsByEntityID.begin(); it != m_lightsByEntityID.end(); ) {
            if (it->second.handle == handle) {
                it = m_lightsByEntityID.erase(it);
            } else {
                ++it;
            }
        }

        // Find and remove all instances of this handle
        auto it = m_lights.begin();
        while (it != m_lights.end()) {
            if (it->handle == handle) {
                LogMessage("Destroying light handle: %p\n", handle);
                m_remix->DestroyLight(it->handle);
                it = m_lights.erase(it);
            } else {
                ++it;
            }
        }
        LogMessage("Light cleanup complete, remaining lights: %d\n", m_lights.size());
    }
    catch (...) {
        LogMessage("Exception in DestroyLight\n");
    }

    LeaveCriticalSection(&m_lightCS);
}

void RTXLightManager::CleanupInvalidLights() {
    try {
        auto it = m_lights.begin();
        while (it != m_lights.end()) {
            bool isValid = false;
            if (it->handle) {
                // Try to draw the light as a validity check
                auto result = m_remix->DrawLightInstance(it->handle);
                isValid = static_cast<bool>(result); // Use the bool operator
            }

            if (!isValid) {
                LogMessage("Removing invalid light handle: %p\n", it->handle);
                if (it->handle) {
                    m_remix->DestroyLight(it->handle);
                }
                it = m_lights.erase(it);
            } else {
                ++it;
            }
        }
    }
    catch (...) {
        LogMessage("Exception in CleanupInvalidLights\n");
    }
}

void RTXLightManager::DrawLights() {
    if (!m_initialized || !m_remix) return;

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Process any pending updates before drawing
        if (!m_isFrameActive) {
            ProcessPendingUpdates();
        }

        for (const auto& light : m_lights) {
            if (light.handle) {
                auto result = m_remix->DrawLightInstance(light.handle);
                if (!static_cast<bool>(result)) {
                    LogMessage("Failed to draw light handle: %p\n", light.handle);
                }
            }
        }
    }
    catch (...) {
        LogMessage("Exception in DrawLights\n");
    }

    LeaveCriticalSection(&m_lightCS);
}

// Helper functions implementation...
remixapi_LightInfoSphereEXT RTXLightManager::CreateSphereLight(const LightProperties& props) {
    remixapi_LightInfoSphereEXT sphereLight = {};
    sphereLight.sType = REMIXAPI_STRUCT_TYPE_LIGHT_INFO_SPHERE_EXT;
    sphereLight.position = {props.x, props.y, props.z};
    sphereLight.radius = props.size;
    sphereLight.shaping_hasvalue = false;
    return sphereLight;
}

remixapi_LightInfo RTXLightManager::CreateLightInfo(const remixapi_LightInfoSphereEXT& sphereLight) {
    remixapi_LightInfo lightInfo = {};
    lightInfo.sType = REMIXAPI_STRUCT_TYPE_LIGHT_INFO;
    lightInfo.pNext = const_cast<remixapi_LightInfoSphereEXT*>(&sphereLight);  // Fix const cast
    lightInfo.hash = GenerateLightHash();
    lightInfo.radiance = {
        sphereLight.position.x * sphereLight.radius,
        sphereLight.position.y * sphereLight.radius,
        sphereLight.position.z * sphereLight.radius
    };
    return lightInfo;
}

void RTXLightManager::LogMessage(const char* format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    Msg("[RTX Light Manager] %s", buffer);
}

using namespace GarrysMod::Lua;

LUA_FUNCTION(RTXBeginFrame) {
    RTXLightManager::Instance().BeginFrame();
    return 0;
}

LUA_FUNCTION(RTXEndFrame) {
    RTXLightManager::Instance().EndFrame();
    return 0;
}

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

LUA_FUNCTION(CreateRTXLight) {
    try {
        if (!g_remix) {
            Msg("[RTX Remix Fixes] Remix interface is null\n");
            LUA->ThrowError("[RTX Remix Fixes] - Remix interface is null");
            return 0;
        }

        float x = LUA->CheckNumber(1);
        float y = LUA->CheckNumber(2);
        float z = LUA->CheckNumber(3);
        float size = LUA->CheckNumber(4);
        float brightness = LUA->CheckNumber(5);
        float r = LUA->CheckNumber(6);
        float g = LUA->CheckNumber(7);
        float b = LUA->CheckNumber(8);
        // Get entity ID from Lua, default to 0 if not provided
        uint64_t entityID = LUA->IsType(9, Type::NUMBER) ? static_cast<uint64_t>(LUA->GetNumber(9)) : 0;

        // Debug print received values
        Msg("[RTX Light Module] Received values - Pos: %.2f,%.2f,%.2f, Size: %f, Brightness: %f, Color: %f,%f,%f, EntityID: %llu\n",
            x, y, z, size, brightness, r, g, b, entityID);

        auto props = RTXLightManager::LightProperties();
        props.x = x;
        props.y = y;
        props.z = z;
        props.size = size;
        props.brightness = brightness;
        props.r = r / 255.0f;
        props.g = g / 255.0f;
        props.b = b / 255.0f;

        auto& manager = RTXLightManager::Instance();
        auto handle = manager.CreateLight(props, entityID);  // Pass the entityID
        if (!handle) {
            Msg("[RTX Light Module] Failed to create light!\n");
            LUA->ThrowError("[RTX Remix Fixes] - Failed to create light");
            return 0;
        }

        Msg("[RTX Light Module] Light created successfully with handle %p\n", handle);
        LUA->PushUserdata(handle);
        return 1;
    }
    catch (...) {
        Msg("[RTX Light Module] Exception in CreateRTXLight\n");
        LUA->ThrowError("[RTX Remix Fixes] - Exception in light creation");
        return 0;
    }
}

LUA_FUNCTION(UpdateRTXLight) {
    try {
        if (!g_remix) {
            Msg("[RTX Remix Fixes] Remix interface is null\n");
            LUA->PushBool(false);
            return 1;
        }

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

        float x = LUA->CheckNumber(2);
        float y = LUA->CheckNumber(3);
        float z = LUA->CheckNumber(4);
        float size = LUA->CheckNumber(5);
        float brightness = LUA->CheckNumber(6);
        float r = LUA->CheckNumber(7);
        float g = LUA->CheckNumber(8);
        float b = LUA->CheckNumber(9);

        Msg("[RTX Remix Fixes] Updating light at (%f, %f, %f) with size %f and brightness %f\n", 
            x, y, z, size, brightness);

        auto props = RTXLightManager::LightProperties();
        props.x = x;
        props.y = y;
        props.z = z;
        props.size = size < 1.0f ? 1.0f : size;
        props.brightness = brightness < 0.1f ? 0.1f : brightness;
        props.r = (r / 255.0f) > 1.0f ? 1.0f : (r / 255.0f < 0.0f ? 0.0f : r / 255.0f);
        props.g = (g / 255.0f) > 1.0f ? 1.0f : (g / 255.0f < 0.0f ? 0.0f : g / 255.0f);
        props.b = (b / 255.0f) > 1.0f ? 1.0f : (b / 255.0f < 0.0f ? 0.0f : b / 255.0f);

        auto& manager = RTXLightManager::Instance();
        remixapi_LightHandle newHandle;
        if (!manager.UpdateLight(handle, props, &newHandle)) {
            Msg("[RTX Remix Fixes] Failed to update light\n");
            LUA->PushBool(false);
            return 1;
        }

        LUA->PushBool(true);
        if (newHandle != handle) {
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

LUA_FUNCTION(DrawRTXLights) { 
    try {
        if (!g_remix) {
            Msg("[RTX Remix Fixes] Cannot draw lights - Remix interface is null\n");
            return 0;
        }

        RTXLightManager::Instance().DrawLights();
        return 0;
    }
    catch (...) {
        Msg("[RTX Remix Fixes] Exception in DrawRTXLights\n");
        return 0;
    }
}

// Initialize Lua bindings for RTX lights
void RTXLightManager::InitializeLuaBindings(GarrysMod::Lua::ILuaBase* LUA) {
    // Create table for RTX light functions
    LUA->PushCFunction(RTXBeginFrame);
    LUA->SetField(-2, "RTXBeginFrame");
    
    LUA->PushCFunction(RTXEndFrame);
    LUA->SetField(-2, "RTXEndFrame");

    LUA->PushCFunction(RegisterRTXLightEntityValidator);
    LUA->SetField(-2, "RegisterRTXLightEntityValidator");

    LUA->PushCFunction(CreateRTXLight);
    LUA->SetField(-2, "CreateRTXLight");
    
    LUA->PushCFunction(UpdateRTXLight);
    LUA->SetField(-2, "UpdateRTXLight");
    
    LUA->PushCFunction(DestroyRTXLight);
    LUA->SetField(-2, "DestroyRTXLight");
    
    LUA->PushCFunction(DrawRTXLights);
    LUA->SetField(-2, "DrawRTXLights");
}
#endif // _WIN64