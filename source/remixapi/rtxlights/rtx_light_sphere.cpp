#ifdef _WIN64
#include "rtx_light_sphere.h"
#include <tier0/dbg.h>

namespace RTX {

    // Static ID generator
    uint64_t SphereLight::GenerateID() {
        static uint64_t counter = 0;
        return ++counter;
    }

    SphereLight::SphereLight(const SphereProperties& props)
        : m_remix(nullptr)
        , m_handle(nullptr)
        , m_properties(props)
        , m_id(GenerateID())
        , m_needsUpdate(false) {
    }

    SphereLight::~SphereLight() {
        // Handle is managed by RTXLightManager
    }

    remixapi_LightHandle SphereLight::Create(remix::Interface* remixInterface) {
        if (!remixInterface) return nullptr;
        
        m_remix = remixInterface;
        
        try {
            // Create sphere light info
            remix::LightInfoSphereEXT sphereLight;
            sphereLight.position = { m_properties.x, m_properties.y, m_properties.z };
            sphereLight.radius = m_properties.radius;
            
            // Apply shaping if enabled
            if (m_properties.enableShaping) {
                remix::LightInfoLightShaping shaping;
                shaping.direction = { 
                    m_properties.shapingDirection[0], 
                    m_properties.shapingDirection[1], 
                    m_properties.shapingDirection[2] 
                };
                shaping.coneAngleDegrees = m_properties.shapingConeAngle;
                shaping.coneSoftness = m_properties.shapingConeSoftness;
                shaping.focusExponent = 0.0f;
                
                sphereLight.shaping_hasvalue = true;
                sphereLight.shaping_value = shaping;
            } else {
                sphereLight.shaping_hasvalue = false;
            }
            
            // Create the light info
            remix::LightInfo lightInfo;
            lightInfo.pNext = &sphereLight;
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
                Msg("[RTX SphereLight] Failed to create light: error %d\n", result.status());
                return nullptr;
            }
            
            m_handle = result.value();
            m_needsUpdate = false;
            
            return m_handle;
        }
        catch (...) {
            Msg("[RTX SphereLight] Exception in Create\n");
            return nullptr;
        }
    }

    bool SphereLight::Update() {
        if (!m_remix || !m_needsUpdate) return false;
        
        // For update, we simply recreate the light
        auto newHandle = Create(m_remix);
        if (!newHandle) return false;
        
        // Update was successful
        m_handle = newHandle;
        m_needsUpdate = false;
        return true;
    }

    void SphereLight::SetPosition(float x, float y, float z) {
        m_properties.x = x;
        m_properties.y = y;
        m_properties.z = z;
        m_needsUpdate = true;
    }

    void SphereLight::SetRadius(float radius) {
        m_properties.radius = radius;
        m_needsUpdate = true;
    }

    void SphereLight::SetColor(float r, float g, float b) {
        m_properties.r = r;
        m_properties.g = g;
        m_properties.b = b;
        m_needsUpdate = true;
    }

    void SphereLight::SetBrightness(float brightness) {
        m_properties.brightness = brightness;
        m_needsUpdate = true;
    }

    void SphereLight::EnableShaping(bool enable) {
        m_properties.enableShaping = enable;
        m_needsUpdate = true;
    }

    void SphereLight::SetShapingDirection(float x, float y, float z) {
        m_properties.shapingDirection[0] = x;
        m_properties.shapingDirection[1] = y;
        m_properties.shapingDirection[2] = z;
        m_needsUpdate = true;
    }

    void SphereLight::SetShapingConeAngle(float degrees) {
        m_properties.shapingConeAngle = degrees;
        m_needsUpdate = true;
    }

    void SphereLight::SetShapingConeSoftness(float softness) {
        m_properties.shapingConeSoftness = softness;
        m_needsUpdate = true;
    }

} // namespace RTX
#endif