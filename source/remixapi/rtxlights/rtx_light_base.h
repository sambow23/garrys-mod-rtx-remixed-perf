#pragma once
#include <remix/remix_c.h>
#include <remix/remix.h>
#include <cstdint>
#include <string>

namespace RTX {
    // Base interface for all light types
    class ILight {
    public:
        virtual ~ILight() = default;
        
        // Create the light in the RTX system
        virtual remixapi_LightHandle Create(remix::Interface* remixInterface) = 0;
        
        // Update light properties
        virtual bool Update() = 0;
        
        // Get the underlying light handle
        virtual remixapi_LightHandle GetHandle() const = 0;
        
        // Get unique ID for this light
        virtual uint64_t GetID() const = 0;
        
        // Get a string representation of the light type for debugging
        virtual std::string GetTypeName() const = 0;
    };
}