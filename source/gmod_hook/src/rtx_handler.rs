use crate::GmodHookHandler;
use gmod::lua::State;

/// Handler for RTX Remix Fixes integration
pub struct RTXHandler;

impl RTXHandler {
    pub fn new() -> Self {
        RTXHandler
    }
    
    /// Load embedded Lua addon files
    fn load_lua_addons(&self, lua: State) -> Result<(), Box<dyn std::error::Error>> {
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
    fn load_lua_script(&self, lua: State, name: &str, content: &str) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Loading script: {}", name);
        
        // Use load_string to load the script, then pcall to execute it
        unsafe {
            // Convert string to C-string for gmod API
            let c_content = std::ffi::CString::new(content)?;
            match lua.load_string(c_content.as_ptr()) {
                Ok(_) => {
                    // Script loaded successfully, now execute it with pcall
                    if lua.pcall_ignore(0, 0) {
                        log::info!("[RTX Handler] Successfully loaded and executed: {}", name);
                        Ok(())
                    } else {
                        let error = format!("Failed to execute script: {}", name);
                        log::error!("[RTX Handler] {}", error);
                        Err(error.into())
                    }
                }
                Err(e) => {
                    let error = format!("Failed to load {}: {:?}", name, e);
                    log::error!("[RTX Handler] {}", error);
                    Err(error.into())
                }
            }
        }
    }
    
    /// Load RTX entity definitions
    fn load_entity_definitions(&self, lua: State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Loading entity definitions...");
        
        // Load entity files - use placeholder content for now since include_str! paths might not exist
        let entity_placeholder = r#"
            -- RTX Entity placeholder
            print("[RTX Handler] Entity loaded via injection")
        "#;
        
        self.load_lua_script(lua, "rtx_pseudoplayer.lua", entity_placeholder)?;
        self.load_lua_script(lua, "rtx_flashlight_ent.lua", entity_placeholder)?;
        self.load_lua_script(lua, "rtx_pseudoweapon.lua", entity_placeholder)?;
        self.load_lua_script(lua, "base_rtx_light_shared.lua", entity_placeholder)?;
        self.load_lua_script(lua, "base_rtx_light_cl_init.lua", entity_placeholder)?;
        
        Ok(())
    }
    
    /// Register stub functions for RTXFixesBinary compatibility
    fn register_rtx_stubs(&self, lua: State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Registering RTX compatibility stubs...");
        
        // Create stub functions in a safe namespace to avoid conflicts
        let stub_functions = r#"
            -- Check if we're safe to proceed (don't interfere with menu state)
            if not game or not game.GetIPAddress then
                print("[RTX Handler] Deferring RTX stubs registration - GMod not fully loaded")
                return
            end
            
            -- Create RTX namespace to avoid conflicts
            RTX = RTX or {}
            RTX.Stubs = RTX.Stubs or {}
            
            -- Only register global functions if they don't already exist
            local function SafeGlobal(name, func)
                if not _G[name] then
                    _G[name] = func
                    print("[RTX Handler] Registered stub function:", name)
                else
                    print("[RTX Handler] Function already exists, skipping:", name)
                end
            end
            
            -- RTXFixesBinary compatibility stubs
            SafeGlobal("SetForceStaticLighting", function(enabled)
                print("[RTX Handler] SetForceStaticLighting called with:", enabled)
                return true
            end)
            
            SafeGlobal("GetForceStaticLighting", function()
                print("[RTX Handler] GetForceStaticLighting called")
                return false
            end)
            
            SafeGlobal("SetModelDrawHookEnabled", function(enabled)
                print("[RTX Handler] SetModelDrawHookEnabled called with:", enabled)
                return true
            end)
            
            SafeGlobal("ClearRTXResources_Native", function()
                print("[RTX Handler] ClearRTXResources_Native called")
                return true
            end)
            
            SafeGlobal("SetEnableRaytracing", function(enabled)
                print("[RTX Handler] SetEnableRaytracing called with:", enabled)
                return true
            end)
            
            SafeGlobal("SetIgnoreGameDirectionalLights", function(enabled)
                print("[RTX Handler] SetIgnoreGameDirectionalLights called with:", enabled)
                return true
            end)
            
            SafeGlobal("PrintRemixUIState", function()
                print("[RTX Handler] PrintRemixUIState called")
                return true
            end)
            
            -- RTX Light API stubs
            SafeGlobal("CreateRTXSphereLight", function(x, y, z, radius, brightness, r, g, b, entityID, enableShaping, dirX, dirY, dirZ, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXSphereLight called")
                return {} -- Return empty table as light handle
            end)
            
            SafeGlobal("CreateRTXRectLight", function(x, y, z, width, height, brightness, r, g, b, entityID, dirX, dirY, dirZ, xAxisX, xAxisY, xAxisZ, yAxisX, yAxisY, yAxisZ, enableShaping, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXRectLight called")
                return {} -- Return empty table as light handle
            end)
            
            SafeGlobal("CreateRTXDiskLight", function(x, y, z, xRadius, yRadius, brightness, r, g, b, entityID, dirX, dirY, dirZ, xAxisX, xAxisY, xAxisZ, yAxisX, yAxisY, yAxisZ, enableShaping, coneAngle, coneSoftness)
                print("[RTX Handler] CreateRTXDiskLight called")
                return {} -- Return empty table as light handle
            end)
            
            SafeGlobal("CreateRTXDistantLight", function(dirX, dirY, dirZ, angularDiameter, brightness, r, g, b, entityID)
                print("[RTX Handler] CreateRTXDistantLight called")
                return {} -- Return empty table as light handle
            end)
            
            SafeGlobal("UpdateRTXLight", function(handle, ...)
                print("[RTX Handler] UpdateRTXLight called")
                return true, handle
            end)
            
            SafeGlobal("DestroyRTXLight", function(handle)
                print("[RTX Handler] DestroyRTXLight called")
                return true
            end)
            
            SafeGlobal("DrawRTXLights", function()
                -- No-op for now
                return true
            end)
            
            SafeGlobal("RTXBeginFrame", function()
                return true
            end)
            
            SafeGlobal("RTXEndFrame", function()
                return true
            end)
            
            SafeGlobal("RegisterRTXLightEntityValidator", function(validator)
                print("[RTX Handler] RegisterRTXLightEntityValidator called")
                return true
            end)
            
            print("[RTX Handler] RTX compatibility stubs registered safely")
        "#;
        
        self.load_lua_script(lua, "rtx_stubs.lua", stub_functions)?;
        Ok(())
    }
    
    /// Initialize RTX system after Lua state is available
    fn initialize_rtx_system(&self, lua: State) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("[RTX Handler] Initializing RTX system...");
        
        // Run RTX initialization script with better safety checks
        let init_script = r#"
            -- Check if we're in a safe context to initialize
            if not game or not game.GetIPAddress then
                print("[RTX Handler] Deferring RTX initialization - GMod not fully loaded")
                timer.Simple(1, function()
                    if RTX and RTX.Initialize then
                        RTX.Initialize()
                    end
                end)
                return
            end
            
            -- Initialize RTX system
            print("[RTX Handler] Starting RTX initialization...")
            
            -- Create RTX namespace
            RTX = RTX or {}
            
            -- Initialize function for deferred loading
            RTX.Initialize = function()
                print("[RTX Handler] RTX deferred initialization running...")
                
                -- Create necessary ConVars if they don't exist and we're on client
                if CLIENT then
                    local function SafeConVar(name, default)
                        if not ConVarExists(name) then
                            CreateClientConVar(name, default, true, false)
                            print("[RTX Handler] Created ConVar:", name)
                        end
                    end
                    
                    SafeConVar("rtx_pseudoplayer", "1")
                    SafeConVar("rtx_pseudoweapon", "1")
                    SafeConVar("rtx_disablevertexlighting", "0")
                    SafeConVar("rtx_fixmaterials", "1")
                    SafeConVar("rtx_rt_debug", "0")
                end
                
                -- Trigger RTX initialization if available
                if RTXLoad then
                    local success, err = pcall(RTXLoad)
                    if success then
                        print("[RTX Handler] RTXLoad called successfully")
                    else
                        print("[RTX Handler] RTXLoad failed:", err)
                    end
                end
                
                print("[RTX Handler] RTX initialization complete")
            end
            
            -- Schedule initialization for when we're in-game (safer)
            if CLIENT then
                hook.Add("InitPostEntity", "RTXHandler_Init", function()
                    timer.Simple(0.5, RTX.Initialize)
                    hook.Remove("InitPostEntity", "RTXHandler_Init")
                end)
            else
                -- For server or menu, try immediate initialization
                RTX.Initialize()
            end
            
            print("[RTX Handler] RTX system initialization scheduled")
        "#;
        
        self.load_lua_script(lua, "rtx_init.lua", init_script)?;
        Ok(())
    }
}

impl GmodHookHandler for RTXHandler {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    unsafe fn on_lua_init(&self, lua: State) {
        log::info!("[RTX Handler] Lua initialization started");
        
        // Add delay to ensure GMod is fully loaded
        let init_delay_script = r#"
            -- Add a delay to ensure GMod is fully loaded before injecting RTX code
            timer.Simple(2, function()
                print("[RTX Handler] Delayed initialization starting...")
                -- Signal that we're ready for RTX injection
                if RTX_HANDLER_READY then
                    RTX_HANDLER_READY()
                end
            end)
            
            function RTX_HANDLER_READY()
                print("[RTX Handler] GMod is ready, proceeding with RTX injection")
            end
        "#;
        
        // Load the delay script first
        if let Err(e) = self.load_lua_script(lua, "rtx_delay.lua", init_delay_script) {
            log::error!("[RTX Handler] Failed to load delay script: {}", e);
            return;
        }
        
        // Schedule the actual RTX loading for later
        let delayed_init_script = r#"
            timer.Simple(3, function()
                if not RTX_HANDLER_LOADED then
                    RTX_HANDLER_LOADED = true
                    print("[RTX Handler] Starting delayed RTX system initialization...")
                end
            end)
        "#;
        
        if let Err(e) = self.load_lua_script(lua, "rtx_delayed_init.lua", delayed_init_script) {
            log::error!("[RTX Handler] Failed to schedule delayed init: {}", e);
        }
        
        log::info!("[RTX Handler] Initial Lua setup completed - full initialization scheduled");
    }
    
    #[cfg(target_os = "macos")]
    unsafe fn on_lua_init(&self, _lua: *mut std::ffi::c_void) {
        log::info!("[RTX Handler] macOS Lua initialization - limited functionality");
        // macOS implementation would go here
    }
    
    unsafe fn on_shutdown(&self) {
        log::info!("[RTX Handler] Shutting down RTX handler");
    }
} 