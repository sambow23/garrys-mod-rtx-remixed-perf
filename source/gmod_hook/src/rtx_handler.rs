use gmod::lua::State;
use gmod::lua_string;
use std::ffi::CString;
use std::ptr;
use std::time::Duration;
use std::thread;
use std::sync::Once;

/// Handler for RTX Remix Fixes integration
pub struct RTXHandler;

impl RTXHandler {
    pub fn new() -> Self {
        RTXHandler
    }
    
    pub fn shutdown(&self) {
        log::info!("[RTX Handler] Shutting down RTX handler");
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

// Removed GmodHookHandler implementation - using direct hook approach instead

static INIT: Once = Once::new();

// C++ interface structures (similar to gmcl_rekinect)
#[repr(C)]
pub struct CLuaInterface {
    padding: usize,
    pub lua: *mut std::ffi::c_void,
}

#[repr(C)]
pub struct ILuaShared {
    _vtable: *const std::ffi::c_void,
}

impl ILuaShared {
    pub unsafe fn get_lua_interface(&self, realm: u8) -> *mut CLuaInterface {
        let vtable = self._vtable as *const *const std::ffi::c_void;
        let get_lua_interface_fn = *vtable.offset(6); // GetLuaInterface is at offset 6
        let func: extern "C" fn(*const ILuaShared, u8) -> *mut CLuaInterface = 
            std::mem::transmute(get_lua_interface_fn);
        func(self, realm)
    }
}

type CreateInterfaceFn = extern "C" fn(*const i8, *mut i32) -> *mut std::ffi::c_void;

// Function to get ILuaShared from lua_shared.dll
unsafe fn get_lua_shared(create_interface: CreateInterfaceFn) -> *mut ILuaShared {
    let interface_name = CString::new("LUASHARED003").unwrap();
    let mut return_code = 0i32;
    create_interface(interface_name.as_ptr(), &mut return_code) as *mut ILuaShared
}

// Hook function that will be called when CLuaManager::Startup is executed
unsafe extern "C" fn lua_manager_startup_hook() {
    INIT.call_once(|| {
        // Wait a bit to ensure Lua is fully initialized
        thread::sleep(Duration::from_millis(1000));
        
        if let Err(e) = perform_safe_injection() {
            eprintln!("RTX injection failed: {}", e);
        }
    });
}

unsafe fn perform_safe_injection() -> Result<(), String> {
    // Load lua_shared.dll
    let lua_shared_path = if cfg!(target_pointer_width = "64") {
        "bin/win64/lua_shared.dll"
    } else {
        "bin/lua_shared.dll"
    };
    
    let lua_shared = libloading::Library::new(lua_shared_path)
        .map_err(|e| format!("Failed to load lua_shared: {}", e))?;
    
    // Get CreateInterface function
    let create_interface: CreateInterfaceFn = *lua_shared
        .get(b"CreateInterface")
        .map_err(|e| format!("Failed to find CreateInterface: {}", e))?;
    
    // Get ILuaShared interface
    let lua_shared_interface = get_lua_shared(create_interface);
    if lua_shared_interface.is_null() {
        return Err("Failed to get ILuaShared interface".to_string());
    }
    
    // Get client Lua interface (realm 0 = client)
    let client_lua = (*lua_shared_interface).get_lua_interface(0);
    if client_lua.is_null() {
        return Err("Failed to get client Lua interface".to_string());
    }
    
    // Get Lua state
    let lua_state = (*client_lua).lua;
    if lua_state.is_null() {
        return Err("Failed to get Lua state".to_string());
    }
    
    // Set up gmod crate's Lua state
    gmod::set_lua_state(lua_state);
    let lua = State(lua_state);
    
    // Now perform safe RTX initialization
    safe_rtx_init(lua)?;
    
    Ok(())
}

unsafe fn safe_rtx_init(lua: State) -> Result<(), String> {
    // Check if we're in a safe context
    lua.get_global(lua_string!("CLIENT"));
    let is_client = lua.get_boolean(-1);
    lua.pop();
    
    if !is_client {
        return Ok(()); // Don't do anything on server
    }
    
    // Check if RTX namespace already exists (avoid conflicts)
    lua.get_global(lua_string!("RTX"));
    if !lua.is_nil(-1) {
        lua.pop();
        return Ok(()); // RTX already loaded
    }
    lua.pop();
    
    // Create RTX namespace
    lua.create_table(0, 0);
    lua.set_global(lua_string!("RTX"));
    
    // Load our embedded Lua addon safely
    let lua_addon = include_str!("../../../addon/lua/autorun/cl_rtx.lua");
    let lua_addon_cstr = CString::new(lua_addon).map_err(|e| format!("Failed to convert Lua addon to C string: {}", e))?;
    
    // Use protected call to prevent crashes
    if lua.load_string(lua_addon_cstr.as_ptr()).is_ok() {
        lua.get_global(lua_string!("pcall"));
        lua.push_value(-2); // Push the loaded function
        
        let result = lua.pcall(1, 0, 0);
        if result == 0 {
            println!("RTX addon loaded successfully");
        } else {
            let error_msg = lua.get_string(-1).unwrap_or(std::borrow::Cow::Borrowed("Unknown error"));
            eprintln!("RTX addon failed to load: {}", error_msg);
            lua.pop();
        }
    } else {
        return Err("Failed to load RTX addon string".to_string());
    }
    
    Ok(())
}

pub fn is_gmod_context() -> bool {
    unsafe {
        let lua_shared_path = if cfg!(target_pointer_width = "64") {
            "bin/win64/lua_shared.dll"
        } else {
            "bin/lua_shared.dll"
        };
        
        // Try to load lua_shared - if it fails, we're not in GMod
        libloading::Library::new(lua_shared_path).is_ok()
    }
}

// Hook setup function (this would need to be called from main injection point)
pub unsafe fn setup_lua_hook() -> Result<(), String> {
    // This is where we would set up the CLuaManager::Startup hook
    // For now, we'll use a simpler approach with a delay
    thread::spawn(|| {
        // Wait for GMod to be fully loaded
        thread::sleep(Duration::from_millis(3000));
        lua_manager_startup_hook();
    });
    
    Ok(())
}

#[no_mangle]
pub extern "C" fn gmod13_open(lua_state: *mut std::ffi::c_void) -> i32 {
    unsafe {
        if !lua_state.is_null() {
            gmod::set_lua_state(lua_state);
            let lua = State(lua_state);
            
            // This is called when loaded as a binary module
            if let Err(e) = safe_rtx_init(lua) {
                eprintln!("RTX binary module init failed: {}", e);
            }
        }
    }
    0
}

#[no_mangle]
pub extern "C" fn gmod13_close(_lua_state: *mut std::ffi::c_void) -> i32 {
    // Cleanup if needed
    0
} 