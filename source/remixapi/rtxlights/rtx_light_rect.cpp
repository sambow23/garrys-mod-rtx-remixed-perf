// rtx_light_rect.cpp
#include "rtx_light_rect.h"
#include <tier0/dbg.h>

namespace RTX {

    // Static ID generator
    uint64_t RectLight::GenerateID() {
        static uint64_t counter = 0;
        return ++counter;
    }

    RectLight::RectLight(const RectProperties& props)
        : m_remix(nullptr)
        , m_handle(nullptr)
        , m_properties(props)
        , m_id(GenerateID())
        , m_needsUpdate(false) {
    }

    RectLight::~RectLight() {
        // Handle is managed by RTXLightManager
    }

    remixapi_LightHandle RectLight::Create(remix::Interface* remixInterface) {
        if (!remixInterface) return nullptr;
        
        m_remix = remixInterface;
        
        try {
            // Create rect light info
            remix::LightInfoRectEXT rectLight;
            rectLight.position = { m_properties.x, m_properties.y, m_properties.z };
            
            // Set axes
            rectLight.xAxis = { m_properties.xAxisX, m_properties.xAxisY, m_properties.xAxisZ };
            rectLight.yAxis = { m_properties.yAxisX, m_properties.yAxisY, m_properties.yAxisZ };
            rectLight.direction = { m_properties.dirX, m_properties.dirY, m_properties.dirZ };
            
            // Set dimensions
            rectLight.xSize = m_properties.xSize;
            rectLight.ySize = m_properties.ySize;
            
            // Apply shaping if enabled
            if (m_properties.enableShaping) {
                remix::LightInfoLightShaping shaping;
                shaping.direction = { m_properties.dirX, m_properties.dirY, m_properties.dirZ };
                shaping.coneAngleDegrees = m_properties.shapingConeAngle;
                shaping.coneSoftness = m_properties.shapingConeSoftness;
                shaping.focusExponent = 0.0f;
                
                rectLight.shaping_hasvalue = true;
                rectLight.shaping_value = shaping;
            } else {
                rectLight.shaping_hasvalue = false;
            }
            
            // Create the light info
            remix::LightInfo lightInfo;
            lightInfo.pNext = &rectLight;
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
                Msg("[RTX RectLight] Failed to create light: error %d\n", result.status());
                return nullptr;
            }
            
            m_handle = result.value();
            m_needsUpdate = false;
            
            return m_handle;
        }
        catch (...) {
            Msg("[RTX RectLight] Exception in Create\n");
            return nullptr;
        }
    }

    bool RectLight::Update() {
        if (!m_remix || !m_needsUpdate) return false;
        
        // For update, we simply recreate the light
        auto newHandle = Create(m_remix);
        if (!newHandle) return false;
        
        // Update was successful
        m_handle = newHandle;
        m_needsUpdate = false;
        return true;
    }

    void RectLight::SetPosition(float x, float y, float z) {
        m_properties.x = x;
        m_properties.y = y;
        m_properties.z = z;
        m_needsUpdate = true;
    }

    void RectLight::SetDirection(float x, float y, float z) {
        m_properties.dirX = x;
        m_properties.dirY = y;
        m_properties.dirZ = z;
        m_needsUpdate = true;
    }

    void RectLight::SetXAxis(float x, float y, float z) {
        m_properties.xAxisX = x;
        m_properties.xAxisY = y;
        m_properties.xAxisZ = z;
        m_needsUpdate = true;
    }

    void RectLight::SetYAxis(float x, float y, float z) {
        m_properties.yAxisX = x;
        m_properties.yAxisY = y;
        m_properties.yAxisZ = z;
        m_needsUpdate = true;
    }

    void RectLight::SetDimensions(float xSize, float ySize) {
        m_properties.xSize = xSize;
        m_properties.ySize = ySize;
        m_needsUpdate = true;
    }

    void RectLight::SetColor(float r, float g, float b) {
        m_properties.r = r;
        m_properties.g = g;
        m_properties.b = b;
        m_needsUpdate = true;
    }

    void RectLight::SetBrightness(float brightness) {
        m_properties.brightness = brightness;
        m_needsUpdate = true;
    }

    void RectLight::EnableShaping(bool enable) {
        m_properties.enableShaping = enable;
        m_needsUpdate = true;
    }

    void RectLight::SetShapingConeAngle(float degrees) {
        m_properties.shapingConeAngle = degrees;
        m_needsUpdate = true;
    }

    void RectLight::SetShapingConeSoftness(float softness) {
        m_properties.shapingConeSoftness = softness;
        m_needsUpdate = true;
    }

} // namespace RTX