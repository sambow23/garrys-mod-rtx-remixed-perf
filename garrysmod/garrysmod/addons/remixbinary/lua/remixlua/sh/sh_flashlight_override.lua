FlashlightOverride = FlashlightOverride or {}

-- Configuration options
FlashlightOverride.Config = {
    -- Enable/disable the override system
    enabled = true,
    
    -- Sound effects
    sounds = {
        on = "items/flashlight1.wav",
        off = "items/flashlight1.wav"
    },
    
    -- Chat messages
    chat_messages = {
        enabled = true,
        prefix_color = Color(255, 255, 0),
        text_color = Color(255, 255, 255),
        prefix = "[gmRTX - Flashlight]"
    },
    
    -- Mesh settings
    mesh = {
        -- Default attachment offset from player's eye position
        default_offset = Vector(20, 5, -5),
        default_angles = Angle(0, 0, 0),
        -- Mesh color
        color = Color(255, 255, 100, 200),
        -- Use MapMarker system for mesh generation
        use_mapmarker_system = true,
        deterministic_seed = "rtx_flashlight_deterministic" -- Everyone needs to have the same mesh hash
    },
    
    -- Debounce settings
    debounce = {
        -- Default debounce delay in seconds to prevent accidental double-activation
        default_delay = 0.3,
        -- Maximum allowed debounce delay
        max_delay = 2.0
    },
    
    -- Debug mode
    debug = false
}

-- Utility functions
FlashlightOverride.Utils = {}

-- Function to print debug messages
function FlashlightOverride.Utils.DebugPrint(message)
    if FlashlightOverride.Config.debug then
        print("[Flashlight Override Debug] " .. tostring(message))
    end
end

-- Function to send chat message with proper formatting
function FlashlightOverride.Utils.ChatMessage(message)
    if CLIENT and FlashlightOverride.Config.chat_messages.enabled then
        chat.AddText(
            FlashlightOverride.Config.chat_messages.prefix_color,
            FlashlightOverride.Config.chat_messages.prefix .. " ",
            FlashlightOverride.Config.chat_messages.text_color,
            message
        )
    end
end

-- Function to play sound effect
function FlashlightOverride.Utils.PlaySound(sound_name)
    if CLIENT then
        surface.PlaySound(sound_name)
    end
end

if CLIENT then
    print("[gmRTX - Flashlight] Shared configuration loaded (Client)")
elseif SERVER then
    print("[gmRTX - Flashlight] Shared configuration loaded (Server)")
end 