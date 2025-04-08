#include "rtx_light_disk.h"
#include <tier0/dbg.h>

namespace RTX {

    // Static ID generator
    uint64_t DiskLight::GenerateID() {
        static uint64_t counter = 0;
        return ++counter;
    }

    DiskLight::DiskLight(const DiskProperties& props)
        : m_remix(nullptr)
        , m_handle(nullptr)
        , m_properties(props)
        , m_id(GenerateID())
        , m_needsUpdate(false) {
    }

    DiskLight::~DiskLight() {
        // Handle is managed by RTXLightManager
    }

    remixapi_LightHandle DiskLight::Create(remix::Interface* remixInterface) {
        if (!remixInterface) return nullptr;
        
        m_remix = remixInterface;
        
        try {
            // Create disk light info
            remix::LightInfoDiskEXT diskLight;
            diskLight.position = { m_properties.x, m_properties.y, m_properties.z };
            
            // Ensure axes are properly normalized and orthogonal
            // Direction should be perpendicular to both axes
            float dirNorm = std::sqrt(
                m_properties.dirX * m_properties.dirX + 
                m_properties.dirY * m_properties.dirY + 
                m_properties.dirZ * m_properties.dirZ
            );
            
            // If direction vector is zero, use a default
            if (dirNorm < 0.001f) {
                diskLight.direction = { 0.0f, 0.0f, 1.0f };
            } else {
                diskLight.direction = { 
                    m_properties.dirX / dirNorm, 
                    m_properties.dirY / dirNorm, 
                    m_properties.dirZ / dirNorm 
                };
            }
            
            // For X-axis: use a vector perpendicular to direction
            // If direction is along Z, use X-axis as (1,0,0)
            if (std::abs(diskLight.direction.z) > 0.9f) {
                diskLight.xAxis = { 1.0f, 0.0f, 0.0f };
            } else {
                // Cross product of direction and up vector
                float upX = 0.0f, upY = 1.0f, upZ = 0.0f;
                float xAxisX = upY * diskLight.direction.z - upZ * diskLight.direction.y;
                float xAxisY = upZ * diskLight.direction.x - upX * diskLight.direction.z;
                float xAxisZ = upX * diskLight.direction.y - upY * diskLight.direction.x;
                
                float xNorm = std::sqrt(xAxisX * xAxisX + xAxisY * xAxisY + xAxisZ * xAxisZ);
                diskLight.xAxis = { 
                    xAxisX / xNorm, 
                    xAxisY / xNorm, 
                    xAxisZ / xNorm 
                };
            }
            
            // Y-axis is cross product of direction and x-axis
            float yAxisX = diskLight.direction.y * diskLight.xAxis.z - diskLight.direction.z * diskLight.xAxis.y;
            float yAxisY = diskLight.direction.z * diskLight.xAxis.x - diskLight.direction.x * diskLight.xAxis.z;
            float yAxisZ = diskLight.direction.x * diskLight.xAxis.y - diskLight.direction.y * diskLight.xAxis.x;
            
            float yNorm = std::sqrt(yAxisX * yAxisX + yAxisY * yAxisY + yAxisZ * yAxisZ);
            diskLight.yAxis = { 
                yAxisX / yNorm, 
                yAxisY / yNorm, 
                yAxisZ / yNorm 
            };
            
            // Set radii
            diskLight.xRadius = m_properties.xRadius;
            diskLight.yRadius = m_properties.yRadius;
            
            // Apply shaping if enabled (use wider angle)
            if (m_properties.enableShaping) {
                remix::LightInfoLightShaping shaping;
                shaping.direction = diskLight.direction;
                
                // Use a sensible default cone angle if the provided one is too small
                shaping.coneAngleDegrees = m_properties.shapingConeAngle < 1.0f ? 120.0f : m_properties.shapingConeAngle;
                shaping.coneSoftness = m_properties.shapingConeSoftness;
                shaping.focusExponent = 0.0f;
                
                diskLight.shaping_hasvalue = true;
                diskLight.shaping_value = shaping;
            } else {
                diskLight.shaping_hasvalue = false;
            }
            
            // Set volumetric radiance scale
            diskLight.volumetricRadianceScale = 1.0f;
            
            // Create the light info
            remix::LightInfo lightInfo;
            lightInfo.pNext = &diskLight;
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
                Msg("[RTX DiskLight] Failed to create light: error %d\n", result.status());
                return nullptr;
            }
            
            m_handle = result.value();
            m_needsUpdate = false;
            
            return m_handle;
        }
        catch (...) {
            Msg("[RTX DiskLight] Exception in Create\n");
            return nullptr;
        }
    }

    bool DiskLight::Update() {
        if (!m_remix || !m_needsUpdate) return false;
        
        // For update, we simply recreate the light
        auto newHandle = Create(m_remix);
        if (!newHandle) return false;
        
        // Update was successful
        m_handle = newHandle;
        m_needsUpdate = false;
        return true;
    }

    void DiskLight::SetPosition(float x, float y, float z) {
        m_properties.x = x;
        m_properties.y = y;
        m_properties.z = z;
        m_needsUpdate = true;
    }

    void DiskLight::SetDirection(float x, float y, float z) {
        m_properties.dirX = x;
        m_properties.dirY = y;
        m_properties.dirZ = z;
        m_needsUpdate = true;
    }

    void DiskLight::SetXAxis(float x, float y, float z) {
        m_properties.xAxisX = x;
        m_properties.xAxisY = y;
        m_properties.xAxisZ = z;
        m_needsUpdate = true;
    }

    void DiskLight::SetYAxis(float x, float y, float z) {
        m_properties.yAxisX = x;
        m_properties.yAxisY = y;
        m_properties.yAxisZ = z;
        m_needsUpdate = true;
    }

    void DiskLight::SetRadii(float xRadius, float yRadius) {
        m_properties.xRadius = xRadius;
        m_properties.yRadius = yRadius;
        m_needsUpdate = true;
    }

    void DiskLight::SetColor(float r, float g, float b) {
        m_properties.r = r;
        m_properties.g = g;
        m_properties.b = b;
        m_needsUpdate = true;
    }

    void DiskLight::SetBrightness(float brightness) {
        m_properties.brightness = brightness;
        m_needsUpdate = true;
    }

    void DiskLight::EnableShaping(bool enable) {
        m_properties.enableShaping = enable;
        m_needsUpdate = true;
    }

    void DiskLight::SetShapingConeAngle(float degrees) {
        m_properties.shapingConeAngle = degrees;
        m_needsUpdate = true;
    }

    void DiskLight::SetShapingConeSoftness(float softness) {
        m_properties.shapingConeSoftness = softness;
        m_needsUpdate = true;
    }

} // namespace RTX