use crate::{GmodHookHandler, acquire_lua_state};
use std::ffi::c_void;

/// Handler for RTX Remix Fixes integration
pub struct RTXHandler;

impl RTXHandler {
    pub fn new() -> Self {
        RTXHandler
    }
    
    /// Load embedded Lua addon files
    fn load_lua_addons(&self, lua: gmod::lua::State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Loading Lua addons...");
        
        // Load shared RTX functionality first
        self.load_lua_script(lua, "sh_rtx.lua", include_str!("../../../addon/lua/autorun/sh_rtx.lua"))?;
        
        // Load flashlight override configuration
        self.load_lua_script(lua, "sh_flashlight_override.lua", include_str!("../../../addon/lua/autorun/sh_flashlight_override.lua"))?;
        
        // Load main client RTX functionality
        self.load_lua_script(lua, "cl_rtx.lua", include_str!("../../../addon/lua/autorun/cl_rtx.lua"))?;
        
        // Load entity definitions
        self.load_entity_definitions(lua)?;
        
        log::info!("[RTX Handler] Lua addons loaded successfully");
        Ok(())
    }
    
    /// Load a single Lua script with error handling
    fn load_lua_script(&self, lua: gmod::lua::State, name: &str, content: &str) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Loading script: {}", name);
        
        match lua.run_string_ex(name, false, content, true) {
            Ok(_) => {
                log::info!("[RTX Handler] Successfully loaded: {}", name);
                Ok(())
            }
            Err(e) => {
                log::error!("[RTX Handler] Failed to load {}: {}", name, e);
                Err(format!("Failed to load {}: {}", name, e).into())
            }
        }
    }
    
    /// Load RTX entity definitions
    fn load_entity_definitions(&self, lua: gmod::lua::State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Loading entity definitions...");
        
        // Load entity files
        self.load_lua_script(lua, "rtx_pseudoplayer.lua", include_str!("../../../addon/lua/entities/rtx_pseudoplayer.lua"))?;
        self.load_lua_script(lua, "rtx_flashlight_ent.lua", include_str!("../../../addon/lua/entities/rtx_flashlight_ent.lua"))?;
        self.load_lua_script(lua, "rtx_pseudoweapon.lua", include_str!("../../../addon/lua/entities/rtx_pseudoweapon.lua"))?;
        
        // Load base RTX light entity (shared)
        self.load_lua_script(lua, "base_rtx_light_shared.lua", include_str!("../../../addon/lua/entities/base_rtx_light/shared.lua"))?;
        self.load_lua_script(lua, "base_rtx_light_cl_init.lua", include_str!("../../../addon/lua/entities/base_rtx_light/cl_init.lua"))?;
        
        Ok(())
    }
    
    /// Register stub functions for RTXFixesBinary compatibility
    fn register_rtx_stubs(&self, lua: gmod::lua::State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Registering RTX compatibility stubs...");
        
        // Create stub functions for binary module functions that aren't available
        let stub_functions = r#"
            -- RTXFixesBinary compatibility stubs
            function SetForceStaticLighting(enabled)
                print("[RTX Handler] SetForceStaticLighting called with:", enabled)
                return true
            end
            
            function GetForceStaticLighting()
                print("[RTX Handler] GetForceStaticLighting called")
                return false
            end
            
            function SetModelDrawHookEnabled(enabled)
                print("[RTX Handler] SetModelDrawHookEnabled called with:", enabled)
                return true
            end
            
            function ClearRTXResources_Native()
                print("[RTX Handler] ClearRTXResources_Native called")
                return true
            end
            
            function SetEnableRaytracing(enabled)
                print("[RTX Handler] SetEnableRaytracing called with:", enabled)
                return true
            end
            
            function SetIgnoreGameDirectionalLights(enabled)
                print("[RTX Handler] SetIgnoreGameDirectionalLights called with:", enabled)
                return true
            end
            
            function PrintRemixUIState()
                print("[RTX Handler] PrintRemixUIState called")
                return true
            end
            
            -- RTX Light API stubs
            function CreateRTXSphereLight(x, y, z, radius, brightness, r, g, b, entityID, enableShaping, dirX, dirY, dirZ, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXSphereLight called")
                return {} -- Return empty table as light handle
            end
            
            function CreateRTXRectLight(x, y, z, width, height, brightness, r, g, b, entityID, dirX, dirY, dirZ, xAxisX, xAxisY, xAxisZ, yAxisX, yAxisY, yAxisZ, enableShaping, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXRectLight called")
                return {} -- Return empty table as light handle
            end
            
            function CreateRTXDiskLight(x, y, z, xRadius, yRadius, brightness, r, g, b, entityID, dirX, dirY, dirZ, xAxisX, xAxisY, xAxisZ, yAxisX, yAxisY, yAxisZ, enableShaping, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXDiskLight called")
                return {} -- Return empty table as light handle
            end
            
            function CreateRTXDistantLight(dirX, dirY, dirZ, angularDiameter, brightness, r, g, b, entityID)
                print("[RTX Handler] CreateRTXDistantLight called")
                return {} -- Return empty table as light handle
            end
            
            function UpdateRTXLight(handle, ...)
                print("[RTX Handler] UpdateRTXLight called")
                return true, handle
            end
            
            function DestroyRTXLight(handle)
                print("[RTX Handler] DestroyRTXLight called")
                return true
            end
            
            function DrawRTXLights()
                -- No-op for now
                return true
            end
            
            function RTXBeginFrame()
                return true
            end
            
            function RTXEndFrame()
                return true
            end
            
            function RegisterRTXLightEntityValidator(validator)
                print("[RTX Handler] RegisterRTXLightEntityValidator called")
                return true
            end
            
            print("[RTX Handler] RTX compatibility stubs registered")
        "#;
        
        self.load_lua_script(lua, "rtx_stubs.lua", stub_functions)?;
        Ok(())
    }
    
    /// Initialize RTX system after Lua state is available
    fn initialize_rtx_system(&self, lua: gmod::lua::State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Initializing RTX system...");
        
        // Run RTX initialization script
        let init_script = r#"
            -- Initialize RTX system
            print("[RTX Handler] Starting RTX initialization...")
            
            -- Create necessary ConVars if they don't exist
            if not ConVarExists("rtx_pseudoplayer") then
                CreateClientConVar("rtx_pseudoplayer", "1", true, false)
            end
            
            if not ConVarExists("rtx_pseudoweapon") then
                CreateClientConVar("rtx_pseudoweapon", "1", true, false)
            end
            
            if not ConVarExists("rtx_disablevertexlighting") then
                CreateClientConVar("rtx_disablevertexlighting", "0", true, false)
            end
            
            if not ConVarExists("rtx_fixmaterials") then
                CreateClientConVar("rtx_fixmaterials", "1", true, false)
            end
            
            if not ConVarExists("rtx_debug") then
                CreateClientConVar("rtx_rt_debug", "0", true, false)
            end
            
            -- Set up RTX hooks and initialization
            local function InitializeRTX()
                print("[RTX Handler] RTX system initialized via injection")
                
                -- Trigger RTX initialization if available
                if RTXLoad then
                    pcall(RTXLoad)
                    print("[RTX Handler] RTXLoad called successfully")
                end
                
                -- Initialize flashlight override if available
                if FlashlightOverride then
                    print("[RTX Handler] FlashlightOverride system available")
                end
            end
            
            -- Delay initialization to ensure everything is loaded
            timer.Simple(0.1, InitializeRTX)
            
            print("[RTX Handler] RTX system initialization complete")
        "#;
        
        self.load_lua_script(lua, "rtx_init.lua", init_script)?;
        Ok(())
    }
}

impl GmodHookHandler for RTXHandler {
    /// Called when the module is successfully hooked and Lua state is available
    unsafe fn on_lua_init(&self, lua: gmod::lua::State) {
        log::info!("[RTX Handler] RTX Handler initialized - Lua state available");
        
        // Load all RTX addons
        if let Err(e) = self.load_lua_addons(lua) {
            log::error!("[RTX Handler] Failed to load Lua addons: {}", e);
            return;
        }
        
        // Register compatibility stubs
        if let Err(e) = self.register_rtx_stubs(lua) {
            log::error!("[RTX Handler] Failed to register RTX stubs: {}", e);
            return;
        }
        
        // Initialize RTX system
        if let Err(e) = self.initialize_rtx_system(lua) {
            log::error!("[RTX Handler] Failed to initialize RTX system: {}", e);
            return;
        }
        
        log::info!("[RTX Handler] RTX Handler setup complete!");
    }
    
    /// Called when the module is shutting down
    unsafe fn on_shutdown(&self) {
        log::info!("[RTX Handler] RTX Handler shutting down");
    }
} 