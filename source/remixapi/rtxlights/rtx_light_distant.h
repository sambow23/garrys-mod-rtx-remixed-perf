#pragma once
#include "rtx_light_base.h"

namespace RTX {
    struct DistantProperties {
        float dirX, dirY, dirZ;   // Direction vector
        float angularDiameter;    // Angular diameter in degrees
        float brightness;         // Intensity scaling
        float r, g, b;            // Color (0-1)
    };

    class DistantLight : public ILight {
    public:
        DistantLight(const DistantProperties& props);
        ~DistantLight() override;

        remixapi_LightHandle Create(remix::Interface* remixInterface) override;
        bool Update() override;
        remixapi_LightHandle GetHandle() const override { return m_handle; }
        uint64_t GetID() const override { return m_id; }
        std::string GetTypeName() const override { return "DistantLight"; }
        
        // Specific setters for this light type
        void SetDirection(float x, float y, float z);
        void SetAngularDiameter(float degrees);
        void SetColor(float r, float g, float b);
        void SetBrightness(float brightness);
        
        // Getters
        const DistantProperties& GetProperties() const { return m_properties; }

    private:
        remix::Interface* m_remix;
        remixapi_LightHandle m_handle;
        DistantProperties m_properties;
        uint64_t m_id;
        bool m_needsUpdate;
        
        static uint64_t GenerateID();
    };
}