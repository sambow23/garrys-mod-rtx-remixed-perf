#ifdef _WIN64

#include "d3d9_texture_tracker.h"
#include <tier0/dbg.h>
#include <Windows.h>

// Simple vtable hook implementation
namespace VTableHook {
    // Get vtable pointer from object
    inline void** GetVTable(void* pObject) {
        return *reinterpret_cast<void***>(pObject);
    }

    // Hook a vtable entry
    inline void* HookVTableFunction(void* pObject, size_t index, void* pNewFunc) {
        void** vtable = GetVTable(pObject);
        
        // Make vtable writable
        DWORD oldProtect;
        if (!VirtualProtect(&vtable[index], sizeof(void*), PAGE_READWRITE, &oldProtect)) {
            Warning("[D3D9TextureTracker] Failed to make vtable writable\n");
            return nullptr;
        }

        // Swap function pointer
        void* pOriginal = vtable[index];
        vtable[index] = pNewFunc;

        // Restore protection
        VirtualProtect(&vtable[index], sizeof(void*), oldProtect, &oldProtect);

        return pOriginal;
    }
}

// Singleton instance
D3D9TextureTracker& D3D9TextureTracker::Instance() {
    static D3D9TextureTracker instance;
    return instance;
}

D3D9TextureTracker::~D3D9TextureTracker() {
    Shutdown();
}

bool D3D9TextureTracker::Initialize(IDirect3DDevice9Ex* pDevice) {
    if (m_bInitialized) {
        Warning("[D3D9TextureTracker] Already initialized!\n");
        return false;
    }

    if (!pDevice) {
        Warning("[D3D9TextureTracker] Invalid device pointer!\n");
        return false;
    }

    m_pDevice = pDevice;

    // Hook SetTexture (vtable index 65 for IDirect3DDevice9)
    // SetTexture is method #65 in the IDirect3DDevice9 vtable
    m_pOriginalSetTexture = reinterpret_cast<SetTexture_t>(
        VTableHook::HookVTableFunction(pDevice, 65, &Hook_SetTexture)
    );

    if (!m_pOriginalSetTexture) {
        Warning("[D3D9TextureTracker] Failed to hook SetTexture!\n");
        m_pDevice = nullptr;
        return false;
    }

    m_bInitialized = true;
    Msg("[D3D9TextureTracker] Initialized successfully\n");
    
    return true;
}

void D3D9TextureTracker::Shutdown() {
    if (!m_bInitialized) {
        return;
    }

    // Restore original function
    if (m_pDevice && m_pOriginalSetTexture) {
        VTableHook::HookVTableFunction(m_pDevice, 65, m_pOriginalSetTexture);
    }

    m_textureCache.clear();
    m_currentMaterial.clear();
    m_pDevice = nullptr;
    m_pOriginalSetTexture = nullptr;
    m_bInitialized = false;

    Msg("[D3D9TextureTracker] Shutdown complete\n");
}

void D3D9TextureTracker::SetCurrentMaterial(const char* materialName) {
    if (materialName && materialName[0]) {
        m_currentMaterial = materialName;
    } else {
        m_currentMaterial.clear();
    }
}

IDirect3DTexture9* D3D9TextureTracker::GetTextureForMaterial(const char* materialName) {
    if (!materialName || !materialName[0]) {
        return nullptr;
    }

    auto it = m_textureCache.find(materialName);
    if (it != m_textureCache.end() && !it->second.empty()) {
        // Return the first texture variant
        // TODO: We might want to try all variants and see which one has a valid hash
        return it->second[0];
    }

    return nullptr;
}

const std::vector<IDirect3DTexture9*>* D3D9TextureTracker::GetTextureVariantsForMaterial(const char* materialName) {
    if (!materialName || !materialName[0]) {
        return nullptr;
    }

    auto it = m_textureCache.find(materialName);
    if (it != m_textureCache.end()) {
        return &it->second;
    }

    return nullptr;
}

void D3D9TextureTracker::ClearCache() {
    m_textureCache.clear();
    Msg("[D3D9TextureTracker] Cache cleared\n");
}

// Hooked SetTexture function
HRESULT STDMETHODCALLTYPE D3D9TextureTracker::Hook_SetTexture(
    IDirect3DDevice9* pDevice,
    DWORD Stage,
    IDirect3DBaseTexture9* pTexture)
{
    D3D9TextureTracker& tracker = Instance();

    // For now, let's just track ALL textures at stage 0 with a generic key
    // We'll use the texture pointer itself as a way to identify it
    if (Stage == 0 && pTexture) {
        // Check if this is a 2D texture (not cube/volume)
        D3DRESOURCETYPE resType = pTexture->GetType();
        if (resType == D3DRTYPE_TEXTURE) {
            IDirect3DTexture9* p2DTexture = static_cast<IDirect3DTexture9*>(pTexture);
            
            // If we have a current material name, use it
            if (!tracker.m_currentMaterial.empty()) {
                auto& textures = tracker.m_textureCache[tracker.m_currentMaterial];
                
                // Check if we've seen this texture before
                bool found = false;
                for (auto* tex : textures) {
                    if (tex == p2DTexture) {
                        found = true;
                        break;
                    }
                }
                
                // Only log when we discover a NEW variant
                if (!found) {
                    textures.push_back(p2DTexture);
                    Msg("[D3D9TextureTracker] NEW texture variant #%zu: 0x%p for '%s'\n", 
                        textures.size(), p2DTexture, tracker.m_currentMaterial.c_str());
                }
            }
            else {
                // DEBUG: Log that we're seeing textures but don't know their material
                static int unknownCounter = 0;
                if (unknownCounter++ == 0) {  // Only log once
                    Msg("[D3D9TextureTracker] SetTexture called but no current material set (texture: 0x%p)\n", p2DTexture);
                    Msg("[D3D9TextureTracker] This is normal - we need the material system to tell us which material is being rendered\n");
                }
            }
        }
    }

    // Call original function
    if (tracker.m_pOriginalSetTexture) {
        return tracker.m_pOriginalSetTexture(pDevice, Stage, pTexture);
    }

    return D3D_OK;
}

#endif // _WIN64

