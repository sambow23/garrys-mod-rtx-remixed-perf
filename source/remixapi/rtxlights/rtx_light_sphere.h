#ifdef _WIN64
#pragma once
#include "rtx_light_base.h"

namespace RTX {
    struct SphereProperties {
        float x, y, z;          // Position
        float radius;           // Light radius
        float brightness;       // Intensity scaling factor
        float r, g, b;          // Color (0-1)
        bool enableShaping;     // Enable light shaping
        float shapingDirection[3]; // Direction for light shaping
        float shapingConeAngle; // Cone angle for shaped light
        float shapingConeSoftness; // Softness of cone edge
    };

    class SphereLight : public ILight {
    public:
        SphereLight(const SphereProperties& props);
        ~SphereLight() override;

        remixapi_LightHandle Create(remix::Interface* remixInterface) override;
        bool Update() override;
        remixapi_LightHandle GetHandle() const override { return m_handle; }
        uint64_t GetID() const override { return m_id; }
        std::string GetTypeName() const override { return "SphereLight"; }
        
        // Specific setters for this light type
        void SetPosition(float x, float y, float z);
        void SetRadius(float radius);
        void SetColor(float r, float g, float b);
        void SetBrightness(float brightness);
        void EnableShaping(bool enable);
        void SetShapingDirection(float x, float y, float z);
        void SetShapingConeAngle(float degrees);
        void SetShapingConeSoftness(float softness);
        
        // Getters
        const SphereProperties& GetProperties() const { return m_properties; }

    private:
        remix::Interface* m_remix;
        remixapi_LightHandle m_handle;
        SphereProperties m_properties;
        uint64_t m_id;
        bool m_needsUpdate;
        
        // Generate unique light ID
        static uint64_t GenerateID();
    };
}
#endif