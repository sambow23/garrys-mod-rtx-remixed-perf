#pragma once
#include <d3d9.h>
#include "../../public/include/remix/remix.h"
#include "../../public/include/remix/remix_c.h"
#include <remix/remix_c.h>
#include <vector>
#include <queue>
#include <mutex>
#include <atomic>
#include <Windows.h>
#include <utility>
#include <unordered_map>

class RTXLightManager {
public:
    struct LightProperties {
            float x = 0.0f;
            float y = 0.0f;
            float z = 0.0f;
            float size = 1.0f;
            float brightness = 1.0f;
            float r = 1.0f;
            float g = 1.0f;
            float b = 1.0f;
            uint64_t hash = 0;  // Add this field for light identity tracking
        };

    struct PendingUpdate {
        remixapi_LightHandle handle;
        LightProperties properties;
        bool needsUpdate;
        bool requiresRecreation;
    };

    struct ManagedLight {
        remixapi_LightHandle handle;
        LightProperties properties;
        uint64_t entityID = 0;
        float lastUpdateTime;
        bool needsUpdate;
    };

    static RTXLightManager& Instance();

    // Light management functions
    remixapi_LightHandle CreateLight(const LightProperties& props, uint64_t entityID);
    bool UpdateLight(remixapi_LightHandle handle, const LightProperties& props, remixapi_LightHandle* newHandle = nullptr);
    bool IsValidHandle(remixapi_LightHandle handle) const;
    void DestroyLight(remixapi_LightHandle handle);
    void DrawLights();
    bool HasLightForEntity(uint64_t entityID) const;
    void ValidateState();
    void RegisterLuaEntityValidator(std::function<bool(uint64_t)> validator);

    // Frame synchronization
    void BeginFrame();
    void EndFrame();
    void ProcessPendingUpdates();
    
    // Utility functions
    void Initialize(remix::Interface* remixInterface);
    void Shutdown();
    void CleanupInvalidLights();
    void ValidateResources();
    bool IsHandleStillValid(remixapi_LightHandle handle);
    void ProcessFrameRender();
    bool HasActiveLights() const { return !m_lights.empty(); }
    void OnFrameRender();  // Add this declaration
    IDirect3DDevice9* GetD3D9Device() { return m_device; }

private:
    RTXLightManager();
    ~RTXLightManager();

    // Internal helper functions
    IDirect3DDevice9* m_device = nullptr;
    remixapi_LightInfoSphereEXT CreateSphereLight(const LightProperties& props);
    remixapi_LightInfo CreateLightInfo(const remixapi_LightInfoSphereEXT& sphereLight);
    uint64_t GenerateLightHash() const;
    void LogMessage(const char* format, ...);

    // Member variables
    remix::Interface* m_remix;
    std::vector<ManagedLight> m_lights;
    std::vector<ManagedLight> m_lightsToDestroy;
    std::queue<PendingUpdate> m_pendingUpdates;
    std::unordered_map<uint64_t, ManagedLight> m_lightsByEntityID;  // Track lights by entity ID
    std::function<bool(uint64_t)> m_luaEntityValidator;
    std::atomic<bool> m_isUpdating{false};
    std::atomic<bool> m_isDrawing{false};
    std::atomic<bool> m_isValidating{false};
    std::atomic<uint32_t> m_frameCount{0};
    mutable CRITICAL_SECTION m_lightCS;
    mutable CRITICAL_SECTION m_updateCS;
    bool m_initialized;
    bool m_isFrameActive;
    float m_lastValidationTime;

    bool ValidateLightHandle(remixapi_LightHandle handle) const {
        if (!handle || !m_remix) return false;
        
        try {
            // Try to query light properties as validation
            auto result = m_remix->DrawLightInstance(handle);
            return static_cast<bool>(result);
        } catch (...) {
            return false;
        }
    }

    // Delete copy constructor and assignment operator
    RTXLightManager(const RTXLightManager&) = delete;
    RTXLightManager& operator=(const RTXLightManager&) = delete;

    std::atomic<bool> m_requiresRedraw{false};
    std::chrono::steady_clock::time_point m_lastDrawTime;
    static constexpr double FRAME_RATE_LIMIT = 1.0 / 60.0; // 60 FPS limit
    std::unordered_map<remixapi_LightHandle, bool> m_activeHandles;  // Track active handles
    std::mutex m_handleMutex;
    
    // Add method to safely check handle validity
    bool IsHandleActive(remixapi_LightHandle handle) {
        std::lock_guard<std::mutex> lock(m_handleMutex);
        return m_activeHandles.find(handle) != m_activeHandles.end();
    }
};