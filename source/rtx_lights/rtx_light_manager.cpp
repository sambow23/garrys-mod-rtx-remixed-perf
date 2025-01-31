#include "rtx_light_manager.h"
#include <tier0/dbg.h>
#include <algorithm>

RTXLightManager& RTXLightManager::Instance() {
    static RTXLightManager instance;
    return instance;
}

RTXLightManager::RTXLightManager() 
    : m_remix(nullptr)
    , m_initialized(false)
    , m_isFrameActive(false)
    , m_isValidating(false)
    , m_lastValidationTime(0.0f) {
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

    bool expected = false;
    if (!m_isValidating.compare_exchange_strong(expected, true)) {
        return;
    }

    EnterCriticalSection(&m_lightCS);
    
    try {
        float currentTime = GetTickCount64() / 1000.0f;
        if (currentTime - m_lastValidationTime < 5.0f) { // Increased delay further
            LeaveCriticalSection(&m_lightCS);
            m_isValidating.store(false);
            return;
        }
        m_lastValidationTime = currentTime;

        if (!m_luaEntityValidator) {
            LeaveCriticalSection(&m_lightCS);
            m_isValidating.store(false);
            return;
        }

        std::vector<uint64_t> entitiesToRemove;
        std::vector<uint64_t> entitiesToKeep;

        // First pass: identify entities
        for (const auto& pair : m_lightsByEntityID) {
            bool isValid = false;
            try {
                isValid = m_luaEntityValidator(pair.first);
                LogMessage("Entity %llu (Index: %llu) validation result: %s\n", 
                    pair.first, 
                    pair.first % 1000000,
                    isValid ? "valid" : "invalid");
                
                if (isValid) {
                    entitiesToKeep.push_back(pair.first);
                } else {
                    // Only mark for removal if we haven't seen this entity recently
                    float timeSinceUpdate = currentTime - pair.second.lastUpdateTime;
                    if (timeSinceUpdate > 10.0f) { // Only remove if not updated for 10 seconds
                        entitiesToRemove.push_back(pair.first);
                    }
                }
            }
            catch (...) {
                LogMessage("Exception during validation of entity %llu\n", pair.first);
                continue;
            }
        }

        // Only remove if we have clearly invalid entities AND some valid ones
        if (!entitiesToRemove.empty() && !entitiesToKeep.empty()) {
            for (uint64_t entityID : entitiesToRemove) {
                auto it = m_lightsByEntityID.find(entityID);
                if (it != m_lightsByEntityID.end()) {
                    LogMessage("Removing light for invalid entity %llu (Index: %llu) with handle %p\n", 
                        entityID, entityID % 1000000, it->second.handle);
                    
                    if (it->second.handle) {
                        m_remix->DestroyLight(it->second.handle);
                    }

                    auto lightIt = std::find_if(m_lights.begin(), m_lights.end(),
                        [handle = it->second.handle](const ManagedLight& light) {
                            return light.handle == handle;
                        });
                    
                    if (lightIt != m_lights.end()) {
                        m_lights.erase(lightIt);
                    }

                    m_lightsByEntityID.erase(it);
                }
            }
        }

        LogMessage("State validation complete. Valid: %zu, Invalid: %zu, Total remaining: %d\n", 
            entitiesToKeep.size(), entitiesToRemove.size(), m_lights.size());
    }
    catch (const std::exception& e) {
        LogMessage("Exception in ValidateState: %s\n", e.what());
    }
    catch (...) {
        LogMessage("Unknown exception in ValidateState\n");
    }

    m_isValidating.store(false);
    LeaveCriticalSection(&m_lightCS);
}

// Add a method to generate unique hashes
uint64_t RTXLightManager::GenerateLightHash() const {
    static uint64_t counter = 0;
    return (static_cast<uint64_t>(GetCurrentProcessId()) << 32) | (++counter);
}

bool RTXLightManager::UpdateLight(remixapi_LightHandle handle, const LightProperties& props, remixapi_LightHandle* newHandle) {
    if (!m_initialized || !m_remix) return false;

    // Prevent recursive updates
    if (m_isUpdating.exchange(true)) {
        LogMessage("Warning: Recursive UpdateLight call detected\n");
        return false;
    }

    EnterCriticalSection(&m_updateCS);
    
    try {
        // Validate handle before updating
        if (!ValidateLightHandle(handle)) {
            LogMessage("Attempted to update invalid light handle: %p\n", handle);
            LeaveCriticalSection(&m_updateCS);
            m_isUpdating = false;
            return false;
        }

        // Store old properties for rollback
        LightProperties oldProps;
        bool foundOld = false;
        for (const auto& light : m_lights) {
            if (light.handle == handle) {
                oldProps = light.properties;
                foundOld = true;
                break;
            }
        }

        // Create new light before destroying old one
        auto sphereLight = CreateSphereLight(props);
        auto lightInfo = CreateLightInfo(sphereLight);
        auto result = m_remix->CreateLight(lightInfo);
        
        if (!result) {
            LogMessage("Failed to create new light during update\n");
            LeaveCriticalSection(&m_updateCS);
            m_isUpdating = false;
            return false;
        }

        // Only destroy old after successful creation
        m_remix->DestroyLight(handle);

        // Update tracking
        bool updated = false;
        for (auto& light : m_lights) {
            if (light.handle == handle) {
                light.handle = result.value();
                light.properties = props;
                light.lastUpdateTime = GetTickCount64() / 1000.0f;
                updated = true;
                if (newHandle) *newHandle = light.handle;
                break;
            }
        }

        if (!updated) {
            LogMessage("Warning: Light handle not found in tracking list\n");
        }

        LeaveCriticalSection(&m_updateCS);
        m_isUpdating = false;
        return true;
    }
    catch (...) {
        LogMessage("Exception in UpdateLight\n");
        LeaveCriticalSection(&m_updateCS);
        m_isUpdating = false;
        return false;
    }
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
    EnterCriticalSection(&m_lightCS);
    
    try {
        // Track orphaned lights (in m_lights but not in m_lightsByEntityID)
        std::vector<remixapi_LightHandle> orphanedLights;
        for (const auto& light : m_lights) {
            bool found = false;
            for (const auto& pair : m_lightsByEntityID) {
                if (pair.second.handle == light.handle) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                orphanedLights.push_back(light.handle);
            }
        }

        // Cleanup orphaned lights
        if (!orphanedLights.empty()) {
            LogMessage("Found %zu orphaned lights, cleaning up\n", orphanedLights.size());
            for (auto handle : orphanedLights) {
                if (handle) {
                    m_remix->DestroyLight(handle);
                }
                auto it = std::remove_if(m_lights.begin(), m_lights.end(),
                    [handle](const ManagedLight& light) {
                        return light.handle == handle;
                    });
                m_lights.erase(it, m_lights.end());
            }
        }
    }
    catch (...) {
        LogMessage("Exception in CleanupInvalidLights\n");
    }
    
    LeaveCriticalSection(&m_lightCS);
}

void RTXLightManager::ValidateResources() {
    static uint32_t validationCounter = 0;
    validationCounter++;

    // Perform deep validation every 300 frames
    if (validationCounter % 300 == 0) {
        EnterCriticalSection(&m_lightCS);
        
        try {
            size_t beforeSize = m_lights.size();
            CleanupInvalidLights();
            
            // Check for mismatched counts
            if (m_lights.size() != m_lightsByEntityID.size()) {
                LogMessage("Warning: Light count mismatch - Lights: %zu, Entities: %zu\n",
                    m_lights.size(), m_lightsByEntityID.size());
            }

            // Log memory usage
            LogMessage("Resource validation - Lights: %zu, Memory: ~%zu bytes\n",
                m_lights.size(),
                (m_lights.size() * sizeof(ManagedLight)) + 
                (m_lightsByEntityID.size() * sizeof(std::pair<uint64_t, ManagedLight>)));
        }
        catch (...) {
            LogMessage("Exception in ValidateResources\n");
        }
        
        LeaveCriticalSection(&m_lightCS);
    }
}

bool RTXLightManager::IsHandleStillValid(remixapi_LightHandle handle) {
    if (!handle || !m_remix) return false;

    // Check if handle exists and can be drawn
    try {
        auto result = m_remix->DrawLightInstance(handle);
        if (!static_cast<bool>(result)) {
            return false;
        }

        // Verify handle isn't duplicated
        int handleCount = 0;
        for (const auto& light : m_lights) {
            if (light.handle == handle) {
                handleCount++;
                if (handleCount > 1) {
                    LogMessage("Warning: Duplicate handle %p detected\n", handle);
                    return false;
                }
            }
        }

        return true;
    }
    catch (...) {
        return false;
    }
}

void RTXLightManager::DrawLights() {
    if (!m_initialized || !m_remix) return;
    if (m_lights.empty()) return;

    // Prevent recursive drawing
    if (m_isDrawing.exchange(true)) {
        LogMessage("Warning: Recursive DrawLights call detected\n");
        return;
    }

    EnterCriticalSection(&m_lightCS);
    
    std::vector<remixapi_LightHandle> invalidLights;
    
    try {
        m_frameCount++;

        // Add periodic validation
        ValidateResources();
        
        // Batch validation
        for (const auto& light : m_lights) {
            if (!ValidateLightHandle(light.handle)) {
                invalidLights.push_back(light.handle);
                LogMessage("Invalid light detected: %p\n", light.handle);
            }
        }

        // Remove invalid lights first
        if (!invalidLights.empty()) {
            LogMessage("Cleaning up %zu invalid lights\n", invalidLights.size());
            for (auto handle : invalidLights) {
                DestroyLight(handle);
            }
        }

        // Only process updates if not currently updating
        if (!m_isFrameActive && !m_isUpdating) {
            ProcessPendingUpdates();
        }

        // Draw remaining valid lights
        for (const auto& light : m_lights) {
            if (light.handle) {
                try {
                    auto result = m_remix->DrawLightInstance(light.handle);
                    if (!static_cast<bool>(result)) {
                        LogMessage("Failed to draw light %p\n", light.handle);
                    }
                } catch (...) {
                    LogMessage("Exception drawing light %p\n", light.handle);
                }
            }
        }

        // Add handle validation
        for (const auto& light : m_lights) {
            if (light.handle && !IsHandleStillValid(light.handle)) {
                invalidLights.push_back(light.handle);
                LogMessage("Invalid light handle detected: %p\n", light.handle);
            }
        }

        // Periodic validation (every 60 frames)
        if ((m_frameCount % 60) == 0) {
            ValidateState();
        }
    }
    catch (const std::exception& e) {
        LogMessage("Exception in DrawLights: %s\n", e.what());
    }
    catch (...) {
        LogMessage("Unknown exception in DrawLights\n");
    }

    LeaveCriticalSection(&m_lightCS);
    m_isDrawing = false;
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