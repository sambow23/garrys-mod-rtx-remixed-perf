// rtx_light_manager.cpp
#ifdef _WIN64

#include "rtx_light_manager.h"
#include <tier0/dbg.h>
#include <algorithm>
#include "./rtxlights/rtx_light_base.h"
#include "./rtxlights/rtx_light_sphere.h"
#include "./rtxlights/rtx_light_rect.h"
#include "./rtxlights/rtx_light_disk.h"
#include "./rtxlights/rtx_light_distant.h"

extern remix::Interface* g_remix;

RTXLightManager& RTXLightManager::Instance() {
    static RTXLightManager instance;
    return instance;
}

RTXLightManager::RTXLightManager()
#ifdef _WIN64
    : m_remix(nullptr)
#endif
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
                auto newHandle = update.newLightObject->Create(m_remix);
                if (newHandle) {
                    // Add as new light
                    ManagedLight newLight{};
                    newLight.handle = newHandle;
                    newLight.lightObject = update.newLightObject;
                    newLight.entityID = 0; // Will be updated if this is tied to an entity
                    newLight.lastUpdateTime = GetTickCount64() / 1000.0f;
                    newLight.needsUpdate = false;
                    
                    m_lights.push_back(newLight);

                    // Update the original handle to match the new one
                    update.handle = newHandle;

                    LogMessage("Created new light %p with updated properties\n", 
                        newLight.handle);
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
    EnterCriticalSection(&m_lightCS);
    bool exists = m_lightsByEntityID.find(entityID) != m_lightsByEntityID.end();
    LeaveCriticalSection(&m_lightCS);
    return exists;
}

// Sphere light creation
remixapi_LightHandle RTXLightManager::CreateSphereLight(const RTX::SphereProperties& props, uint64_t entityID) {
    if (!m_initialized || !m_remix) {
        LogMessage("Cannot create light: Manager not initialized\n");
        return nullptr;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Check if we already have a light for this entity
        if (entityID != 0 && HasLightForEntity(entityID)) {
            LogMessage("Warning: Attempted to create duplicate light for entity %llu\n", entityID);
            auto existingHandle = m_lightsByEntityID.find(entityID)->second.handle;
            LeaveCriticalSection(&m_lightCS);
            return existingHandle;
        }

        LogMessage("Creating sphere light at (%f, %f, %f) with radius %f\n", 
            props.x, props.y, props.z, props.radius);

        // Create the light object
        auto sphereLight = std::make_shared<RTX::SphereLight>(props);
        auto handle = sphereLight->Create(m_remix);
        
        if (!handle) {
            LogMessage("Remix CreateLight failed\n");
            LeaveCriticalSection(&m_lightCS);
            return nullptr;
        }

        ManagedLight managedLight{};
        managedLight.handle = handle;
        managedLight.lightObject = sphereLight;
        managedLight.entityID = entityID;
        managedLight.lastUpdateTime = GetTickCount64() / 1000.0f;
        managedLight.needsUpdate = false;

        // Add to both tracking containers
        m_lights.push_back(managedLight);
        if (entityID != 0) {
            m_lightsByEntityID[entityID] = managedLight;
        }
        
        LogMessage("Successfully created sphere light handle: %p (Total lights: %d)\n", 
            managedLight.handle, m_lights.size());

        LeaveCriticalSection(&m_lightCS);
        return managedLight.handle;
    }
    catch (...) {
        LogMessage("Exception in CreateSphereLight\n");
        LeaveCriticalSection(&m_lightCS);
        return nullptr;
    }
}

// Rect light creation
remixapi_LightHandle RTXLightManager::CreateRectLight(const RTX::RectProperties& props, uint64_t entityID) {
    if (!m_initialized || !m_remix) {
        LogMessage("Cannot create light: Manager not initialized\n");
        return nullptr;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Check if we already have a light for this entity
        if (entityID != 0 && HasLightForEntity(entityID)) {
            LogMessage("Warning: Attempted to create duplicate light for entity %llu\n", entityID);
            auto existingHandle = m_lightsByEntityID.find(entityID)->second.handle;
            LeaveCriticalSection(&m_lightCS);
            return existingHandle;
        }

        LogMessage("Creating rect light at (%f, %f, %f) with dimensions %f x %f\n", 
            props.x, props.y, props.z, props.xSize, props.ySize);

        // Create the light object
        auto rectLight = std::make_shared<RTX::RectLight>(props);
        auto handle = rectLight->Create(m_remix);
        
        if (!handle) {
            LogMessage("Remix CreateLight failed\n");
            LeaveCriticalSection(&m_lightCS);
            return nullptr;
        }

        ManagedLight managedLight{};
        managedLight.handle = handle;
        managedLight.lightObject = rectLight;
        managedLight.entityID = entityID;
        managedLight.lastUpdateTime = GetTickCount64() / 1000.0f;
        managedLight.needsUpdate = false;

        // Add to both tracking containers
        m_lights.push_back(managedLight);
        if (entityID != 0) {
            m_lightsByEntityID[entityID] = managedLight;
        }
        
        LogMessage("Successfully created rect light handle: %p (Total lights: %d)\n", 
            managedLight.handle, m_lights.size());

        LeaveCriticalSection(&m_lightCS);
        return managedLight.handle;
    }
    catch (...) {
        LogMessage("Exception in CreateRectLight\n");
        LeaveCriticalSection(&m_lightCS);
        return nullptr;
    }
}

// Disk light creation
remixapi_LightHandle RTXLightManager::CreateDiskLight(const RTX::DiskProperties& props, uint64_t entityID) {
    if (!m_initialized || !m_remix) {
        LogMessage("Cannot create light: Manager not initialized\n");
        return nullptr;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Check if we already have a light for this entity
        if (entityID != 0 && HasLightForEntity(entityID)) {
            LogMessage("Warning: Attempted to create duplicate light for entity %llu\n", entityID);
            auto existingHandle = m_lightsByEntityID.find(entityID)->second.handle;
            LeaveCriticalSection(&m_lightCS);
            return existingHandle;
        }

        LogMessage("Creating disk light at (%f, %f, %f) with radii %f x %f\n", 
            props.x, props.y, props.z, props.xRadius, props.yRadius);

        // Create the light object
        auto diskLight = std::make_shared<RTX::DiskLight>(props);
        auto handle = diskLight->Create(m_remix);
        
        if (!handle) {
            LogMessage("Remix CreateLight failed\n");
            LeaveCriticalSection(&m_lightCS);
            return nullptr;
        }

        ManagedLight managedLight{};
        managedLight.handle = handle;
        managedLight.lightObject = diskLight;
        managedLight.entityID = entityID;
        managedLight.lastUpdateTime = GetTickCount64() / 1000.0f;
        managedLight.needsUpdate = false;

        // Add to both tracking containers
        m_lights.push_back(managedLight);
        if (entityID != 0) {
            m_lightsByEntityID[entityID] = managedLight;
        }
        
        LogMessage("Successfully created disk light handle: %p (Total lights: %d)\n", 
            managedLight.handle, m_lights.size());

        LeaveCriticalSection(&m_lightCS);
        return managedLight.handle;
    }
    catch (...) {
        LogMessage("Exception in CreateDiskLight\n");
        LeaveCriticalSection(&m_lightCS);
        return nullptr;
    }
}

// Distant light creation
remixapi_LightHandle RTXLightManager::CreateDistantLight(const RTX::DistantProperties& props, uint64_t entityID) {
    if (!m_initialized || !m_remix) {
        LogMessage("Cannot create light: Manager not initialized\n");
        return nullptr;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        // Check if we already have a light for this entity
        if (entityID != 0 && HasLightForEntity(entityID)) {
            LogMessage("Warning: Attempted to create duplicate light for entity %llu\n", entityID);
            auto existingHandle = m_lightsByEntityID.find(entityID)->second.handle;
            LeaveCriticalSection(&m_lightCS);
            return existingHandle;
        }

        LogMessage("Creating distant light with direction (%f, %f, %f) and angular diameter %f\n", 
            props.dirX, props.dirY, props.dirZ, props.angularDiameter);

        // Create the light object
        auto distantLight = std::make_shared<RTX::DistantLight>(props);
        auto handle = distantLight->Create(m_remix);
        
        if (!handle) {
            LogMessage("Remix CreateLight failed\n");
            LeaveCriticalSection(&m_lightCS);
            return nullptr;
        }

        ManagedLight managedLight{};
        managedLight.handle = handle;
        managedLight.lightObject = distantLight;
        managedLight.entityID = entityID;
        managedLight.lastUpdateTime = GetTickCount64() / 1000.0f;
        managedLight.needsUpdate = false;

        // Add to both tracking containers
        m_lights.push_back(managedLight);
        if (entityID != 0) {
            m_lightsByEntityID[entityID] = managedLight;
        }
        
        LogMessage("Successfully created distant light handle: %p (Total lights: %d)\n", 
            managedLight.handle, m_lights.size());

        LeaveCriticalSection(&m_lightCS);
        return managedLight.handle;
    }
    catch (...) {
        LogMessage("Exception in CreateDistantLight\n");
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

// Generic light update function - delegates to specific light type
bool RTXLightManager::UpdateLight(remixapi_LightHandle handle, const void* props, int lightType, remixapi_LightHandle* newHandle) {
    if (!m_initialized || !m_remix) return false;

    EnterCriticalSection(&m_updateCS);
    
    try {
        // Verify the light exists before queuing update
        bool lightExists = false;
        std::shared_ptr<RTX::ILight> newLight = nullptr;
        
        // Find the existing light in our collection
        for (const auto& light : m_lights) {
            if (light.handle == handle) {
                lightExists = true;
                
                // Create a new light object based on the light type
                switch (lightType) {
                    case 0: // Sphere light
                        newLight = std::make_shared<RTX::SphereLight>(
                            *static_cast<const RTX::SphereProperties*>(props));
                        break;
                    case 1: // Rect light
                        newLight = std::make_shared<RTX::RectLight>(
                            *static_cast<const RTX::RectProperties*>(props));
                        break;
                    case 2: // Disk light
                        newLight = std::make_shared<RTX::DiskLight>(
                            *static_cast<const RTX::DiskProperties*>(props));
                        break;
                    case 3: // Distant light
                        newLight = std::make_shared<RTX::DistantLight>(
                            *static_cast<const RTX::DistantProperties*>(props));
                        break;
                    default:
                        LeaveCriticalSection(&m_updateCS);
                        return false;
                }
                break;
            }
        }

        if (!lightExists || !newLight) {
            LogMessage("Warning: Attempting to update non-existent light %p\n", handle);
            LeaveCriticalSection(&m_updateCS);
            return false;
        }

        // Queue the update
        PendingUpdate update;
        update.handle = handle;
        update.newLightObject = newLight;
        update.needsUpdate = true;
        update.requiresRecreation = true;

        LogMessage("Queueing update for light %p\n", handle);

        m_pendingUpdates.push(update);

        // Process immediately if not in active frame
        if (!m_isFrameActive) {
            ProcessPendingUpdates();
            
            // Find the new handle if requested and it was recreated
            if (newHandle) {
                for (const auto& light : m_lights) {
                    if (light.lightObject->GetID() == newLight->GetID()) {
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
    EnterCriticalSection(&m_lightCS);
    
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
                isValid = static_cast<bool>(result);
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

void RTXLightManager::LogMessage(const char* format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    Msg("[RTX Light Manager] %s", buffer);
}

// Lua bindings will be moved to a separate file for better organization
// Here we just register the function pointers

using namespace GarrysMod::Lua;

void RTXLightManager::InitializeLuaBindings(GarrysMod::Lua::ILuaBase* LUA) {
    // Call the function from rtx_light_lua_bindings.cpp
    extern void RegisterRTXLightBindings(GarrysMod::Lua::ILuaBase* LUA);
    RegisterRTXLightBindings(LUA);
}

#endif // _WIN64