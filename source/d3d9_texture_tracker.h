#pragma once

#ifdef _WIN64

#include <d3d9.h>
#include <unordered_map>
#include <string>
#include <cstddef>

// Forward declarations
class IMaterial;
class IMatRenderContext;

// D3D9 Texture Tracker
// Hooks IDirect3DDevice9::SetTexture to track which textures are used by which materials
class D3D9TextureTracker {
public:
    static D3D9TextureTracker& Instance();

    // Initialize the tracker with the D3D9 device
    bool Initialize(IDirect3DDevice9Ex* pDevice);
    
    // Shutdown and remove hooks
    void Shutdown();

    // Track a material being rendered
    void SetCurrentMaterial(const char* materialName);
    
    // Get the D3D9 texture for a material (returns null if not found)
    IDirect3DTexture9* GetTextureForMaterial(const char* materialName);
    
    // Get all texture variants for a material
    const std::vector<IDirect3DTexture9*>* GetTextureVariantsForMaterial(const char* materialName);

    // Clear the cache (useful for map changes)
    void ClearCache();

    // Get cache statistics
    size_t GetCacheSize() const { return m_textureCache.size(); }

    // Get all cached materials
    std::vector<std::string> GetCachedMaterials() const {
        std::vector<std::string> materials;
        materials.reserve(m_textureCache.size());
        for (const auto& pair : m_textureCache) {
            materials.push_back(pair.first);
        }
        return materials;
    }

private:
    D3D9TextureTracker() = default;
    ~D3D9TextureTracker();

    // Prevent copying
    D3D9TextureTracker(const D3D9TextureTracker&) = delete;
    D3D9TextureTracker& operator=(const D3D9TextureTracker&) = delete;

    // Hook functions
    static HRESULT STDMETHODCALLTYPE Hook_SetTexture(
        IDirect3DDevice9* pDevice,
        DWORD Stage,
        IDirect3DBaseTexture9* pTexture);

    static void Hook_Bind(
        IMatRenderContext* pContext,
        IMaterial* pMaterial,
        void* proxyData);

    // Original function pointer
    typedef HRESULT (STDMETHODCALLTYPE *SetTexture_t)(
        IDirect3DDevice9* pDevice,
        DWORD Stage,
        IDirect3DBaseTexture9* pTexture);
    
    typedef void (*Bind_t)(
        IMatRenderContext* pContext,
        IMaterial* pMaterial,
        void* proxyData);

    SetTexture_t m_pOriginalSetTexture = nullptr;
    Bind_t m_pOriginalBind = nullptr;
    
    IDirect3DDevice9Ex* m_pDevice = nullptr;
    IMatRenderContext* m_pRenderContext = nullptr;
    
    // Current material being rendered (set by Bind hooks)
    std::string m_currentMaterial;
    
    // Cache: material name -> set of D3D9 textures (materials can have multiple texture variants)
    std::unordered_map<std::string, std::vector<IDirect3DTexture9*>> m_textureCache;
    
    // Track whether we're initialized
    bool m_bInitialized = false;
};

#endif // _WIN64

