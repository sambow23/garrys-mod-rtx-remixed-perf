// rtx_light_distant.cpp
#include "rtx_light_distant.h"
#include <tier0/dbg.h>

namespace RTX {

    // Static ID generator
    uint64_t DistantLight::GenerateID() {
        static uint64_t counter = 0;
        return ++counter;
    }

    DistantLight::DistantLight(const DistantProperties& props)
        : m_remix(nullptr)
        , m_handle(nullptr)
        , m_properties(props)
        , m_id(GenerateID())
        , m_needsUpdate(false) {
    }

    DistantLight::~DistantLight() {
        // Handle is managed by RTXLightManager
    }

    remixapi_LightHandle DistantLight::Create(remix::Interface* remixInterface) {
        if (!remixInterface) return nullptr;
        
        m_remix = remixInterface;
        
        try {
            // Create distant light info
            remix::LightInfoDistantEXT distantLight;
            distantLight.direction = { m_properties.dirX, m_properties.dirY, m_properties.dirZ };
            distantLight.angularDiameterDegrees = m_properties.angularDiameter;
            
            // Create the light info
            remix::LightInfo lightInfo;
            lightInfo.pNext = &distantLight;
            lightInfo.hash = m_id;
            
            // Set radiance (color * brightness)
            lightInfo.radiance = { 
                m_properties.r * m_properties.brightness, 
                m_properties.g * m_properties.brightness, 
                m_properties.b * m_properties.brightness 
            };
            
            // Create the light
            auto result = m_remix->CreateLight(lightInfo);
            if (!result) {
                Msg("[RTX DistantLight] Failed to create light: error %d\n", result.status());
                return nullptr;
            }
            
            m_handle = result.value();
            m_needsUpdate = false;
            
            return m_handle;
        }
        catch (...) {
            Msg("[RTX DistantLight] Exception in Create\n");
            return nullptr;
        }
    }

    bool DistantLight::Update() {
        if (!m_remix || !m_needsUpdate) return false;
        
        // For update, we simply recreate the light
        auto newHandle = Create(m_remix);
        if (!newHandle) return false;
        
        // Update was successful
        m_handle = newHandle;
        m_needsUpdate = false;
        return true;
    }

    void DistantLight::SetDirection(float x, float y, float z) {
        m_properties.dirX = x;
        m_properties.dirY = y;
        m_properties.dirZ = z;
        m_needsUpdate = true;
    }

    void DistantLight::SetAngularDiameter(float degrees) {
        m_properties.angularDiameter = degrees;
        m_needsUpdate = true;
    }

    void DistantLight::SetColor(float r, float g, float b) {
        m_properties.r = r;
        m_properties.g = g;
        m_properties.b = b;
        m_needsUpdate = true;
    }

    void DistantLight::SetBrightness(float brightness) {
        m_properties.brightness = brightness;
        m_needsUpdate = true;
    }

} // namespace RTX