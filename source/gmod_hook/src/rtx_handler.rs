use std::{cell::Cell, ffi::c_void, path::Path, fs::File, io::Write};
use fn_abi::abi;

// Embedded Lua code from the addon files
const RTXFIXES_INIT_LUA: &str = r#"
if SERVER then
    cleanup.Register("rtx_lights")
end

if CLIENT then
    -- RTX binary module is now provided by the injected DLL
    -- Check if RTX functions are available
    if SetEnableRaytracing then
        print("[RTX] RTX Remix binary integration detected!")
    else
        print("[RTX] Warning: RTX Remix binary integration not found. Make sure the injector is running.")
    end
end
"#;

const SH_RTX_LUA: &str = r#"
if (SERVER) then
	util.AddNetworkString( "RTXPlayerSpawnedFully" )
end
hook.Add( "PlayerInitialSpawn", "RTXFullLoadSetup", function( ply )
	hook.Add( "SetupMove", ply, function( self, mvply, _, cmd )
		if self == mvply and not cmd:IsForced() then
			hook.Run( "RTXPlayerFullLoad", self )
			hook.Remove( "SetupMove", self )
			if (SERVER) then
				net.Start( "RTXPlayerSpawnedFully" )
				net.Send( mvply )
			end
		end
	end )
end )
"#;

const SH_FLASHLIGHT_OVERRIDE_LUA: &str = r#"
-- Flashlight override will be loaded here if needed
"#;

const CL_RTX_LUA: &str = r#"
if not CLIENT then return end

print("[RTX] Loading client-side RTX enhancements...")

-- ConVars
local cv_enabled = CreateClientConVar("rtx_pseudoplayer", 1, true, false)
local cv_pseudoweapon = CreateClientConVar("rtx_pseudoweapon", 1, true, false)
local cv_disablevertexlighting = CreateClientConVar("rtx_disablevertexlighting", 0, true, false)
local cv_disablevertexlighting_old = CreateClientConVar("rtx_disablevertexlighting_old", 0, true, false)
local cv_fixmaterials = CreateClientConVar("rtx_fixmaterials", 1, true, false)
local cv_experimental_manuallight = CreateClientConVar("rtx_experimental_manuallight", 0, true, false)
local cv_experimental_mightcrash_combinedlightingmode = CreateClientConVar("rtx_experimental_mightcrash_combinedlightingmode", 0, false, false)
local cv_disable_when_unsupported = CreateClientConVar("rtx_disable_when_unsupported", 1, false, false)
local cv_debug = CreateClientConVar("rtx_rt_debug", "0", true, false, "Enable debug messages for RT States")

-- Helper function for debug printing
local function DebugPrint(message)
    if cv_debug:GetBool() then
        print(message)
    end
end

-- RTX initialization
local function RTXLoad()
    DebugPrint("[RTXF2] - Initializing Client")

    -- Set up console commands
    RunConsoleCommand("r_radiosity", "0")
    RunConsoleCommand("r_PhysPropStaticLighting", "1")
    RunConsoleCommand("r_colorstaticprops", "0")
    RunConsoleCommand("r_lightinterp", "0")
    RunConsoleCommand("mat_fullbright", cv_experimental_manuallight:GetBool() and "1" or "0")

    print("[RTX] RTX client-side enhancements loaded!")
end

-- Register hooks
hook.Add("InitPostEntity", "RTXReady", RTXLoad)

-- Console commands
concommand.Add("rtx_fixnow", RTXLoad)

-- Test raytracing toggle if available
if SetEnableRaytracing then
    local currentRaytracingState = true
    
    local function ToggleRaytracingCommand()
        currentRaytracingState = not currentRaytracingState
        DebugPrint("[RTXF2] Toggling raytracing via command. Setting enabled to: " .. tostring(currentRaytracingState))
        local success, err = pcall(SetEnableRaytracing, currentRaytracingState)
        if success then
            DebugPrint("[RTXF2] Successfully called SetEnableRaytracing.")
            print("[RTX] Raytracing " .. (currentRaytracingState and "enabled" or "disabled"))
        else
            DebugPrint("[RTXF2] Warning: Failed to toggle raytracing via command. Error: " .. tostring(err))
            currentRaytracingState = not currentRaytracingState
        end
    end
    concommand.Add("rtx_toggle_raytracing", ToggleRaytracingCommand)
    DebugPrint("[RTXF2] Added console command: rtx_toggle_raytracing")
end

print("[RTX] Client-side RTX addon loaded via injection!")
"#;

// Custom logger that writes to both GMod console and file
static mut LOGGER: Logger = Logger(None);

struct Logger(Option<File>);
impl log::Log for Logger {
    fn log(&self, record: &log::Record) {
        if let Some(lua) = lua_state() {
            unsafe {
                lua.get_global(lua_string!("print"));
                lua.push_string(&if record.level() != log::Level::Info {
                    format!("gmod_hook: [{}] {}", record.level(), record.args())
                } else {
                    format!("gmod_hook: {}", record.args())
                });
                lua.call(1, 0);
            }
        } else if let Some(mut f) = self.0.as_ref() {
            let _ = if record.level() != log::Level::Info {
                writeln!(f, "gmod_hook: [{}] {}", record.level(), record.args())
            } else {
                writeln!(f, "gmod_hook: {}", record.args())
            };
        }
    }

    #[inline]
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::Level::Info
    }

    fn flush(&self) {}
}

#[repr(u8)]
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum GmodLuaInterfaceRealm {
    Client = 0,
    Server = 1,
    Menu = 2,
}

// C++ interface helpers (linked from hax.cpp)
#[link(name = "gmod_hook_cpp", kind = "static")]
extern "C" {
    fn get_lua_shared(create_interface_fn: *const ()) -> *mut c_void;
    fn open_lua_interface(i_lua_shared: *mut c_void, realm: GmodLuaInterfaceRealm) -> *mut c_void;
    fn get_lua_state(c_lua_interface: *mut c_void) -> *mut c_void;
}

#[derive(Clone, Copy, Debug)]
enum RtxLuaState {
    Uninitialized,
    InjectedDll,
    BinaryModule(gmod::lua::State),
}

thread_local! {
    static LUA_STATE: Cell<RtxLuaState> = Cell::new(RtxLuaState::Uninitialized);
}

static mut INIT_REFCOUNT: usize = 0;

pub fn lua_state() -> Option<gmod::lua::State> {
    if let RtxLuaState::BinaryModule(state) = LUA_STATE.get() {
        Some(state)
    } else {
        None
    }
}

pub unsafe fn already_initialized() -> bool {
    INIT_REFCOUNT != 0
}

// DLL path helpers similar to gmcl_rekinect
macro_rules! dll_paths {
    ($($func:ident => $bin:literal / $linux_main_branch:literal),*) => {
        $(pub fn $func() -> &'static str {
            match () {
                _ if cfg!(all(windows, target_pointer_width = "64")) => concat!("bin/win64/", $bin, ".dll"),
                _ if cfg!(all(target_os = "linux", target_pointer_width = "64")) => concat!("bin/linux64/", $bin, ".so"),

                _ if cfg!(all(target_os = "macos")) => concat!("GarrysMod_Signed.app/Contents/MacOS/", $bin, ".dylib"),

                _ if cfg!(all(windows, target_pointer_width = "32")) => {
                    let x86_64_branch = concat!("bin/", $bin, ".dll");
                    if Path::new(x86_64_branch).exists() {
                        x86_64_branch
                    } else {
                        concat!("garrysmod/bin/", $bin, ".dll")
                    }
                },

                _ if cfg!(all(target_os = "linux", target_pointer_width = "32")) => {
                    let x86_64_branch = concat!("bin/linux32/", $bin, ".so");
                    if Path::new(x86_64_branch).exists() {
                        x86_64_branch
                    } else {
                        concat!("garrysmod/bin/", $linux_main_branch, ".so")
                    }
                },

                _ => panic!("Unsupported platform"),
            }
        })*
    };
}

dll_paths! {
    client_dll_path => "client"/"client",
    lua_shared_dll_path => "lua_shared"/"lua_shared",
    lua_shared_srv_dll_path => "lua_shared"/"lua_shared_srv"
}

#[cfg_attr(target_pointer_width = "64", abi("fastcall"))]
#[cfg_attr(all(target_os = "windows", target_pointer_width = "32"), abi("thiscall"))]
#[cfg_attr(all(target_os = "linux", target_pointer_width = "32"), abi("C"))]
type CLuaManagerStartup = extern "C" fn(this: *mut c_void);

macro_rules! cluamanager_detours {
    ($($func:ident => { hook($this_var:ident): $hook:block, $trampoline_var:ident: $trampoline:ident, sigs: $sigfunc:ident => { $($cfg:expr => $sig:literal),* } }),*) => {
        $(
            static mut $trampoline: Option<gmod::detour::RawDetour> = None;

            #[cfg_attr(target_pointer_width = "64", abi("fastcall"))]
            #[cfg_attr(all(target_os = "windows", target_pointer_width = "32"), abi("thiscall"))]
            #[cfg_attr(all(target_os = "linux", target_pointer_width = "32"), abi("C"))]
            unsafe extern "C" fn $func($this_var: *mut c_void) {
                let $trampoline_var = core::mem::transmute::<_, CLuaManagerStartup>($trampoline.as_ref().unwrap().trampoline() as *const ());
                $hook;
            }

            fn $sigfunc() -> gmod::sigscan::Signature {
                match () {
                    $(_ if $cfg => gmod::sigscan::signature!($sig),)*
                    _ => todo!("Unsupported platform")
                }
            }
        )*
    };
}

cluamanager_detours! {
    client_cluamanager_startup => {
        hook(this): {
            trampoline(this);
            cluamanager_startup();
        },
        trampoline: CLIENT_CLUAMANAGER_STARTUP,
        sigs: client_cluamanager_startup_sig => {
            // string search: "Clientside Lua startup!"
            cfg!(all(target_pointer_width = "64", target_os = "windows")) => "48 89 5C 24 ? 48 89 74 24 ? 57 48 83 EC 60 48 8B 05 ? ? ? ? 48 33 C4 48 89 44 24 ? 48 8B F1 48 8D 0D ? ? ? ? FF 15 ? ? ? ? E8 ? ? ? ? F3 0F 10 0D",
            cfg!(all(target_pointer_width = "32", target_os = "windows")) => "55 8B EC 83 EC 18 53 68 ? ? ? ? 8B D9 FF 15 ? ? ? ? 83 C4 04 E8 ? ? ? ? D9 05 ? ? ? ? 68 ? ? ? ? 51 8B 10 8B C8 D9 1C 24"
        }
    }
}

unsafe fn cluamanager_startup() {
    let lib_path = lua_shared_dll_path();

    let lib = {
        #[cfg(windows)]
        {
            libloading::os::windows::Library::open_already_loaded(lib_path)
        }
        #[cfg(unix)]
        {
            libloading::os::unix::Library::open(Some(lib_path), libc::RTLD_NOLOAD)
                .or_else(|_| libloading::os::unix::Library::open(Some(lib_path), libc::RTLD_NOLOAD))
        }
    }
    .expect("Failed to load lua_shared");

    let i_lua_shared = get_lua_shared(
        *lib.get::<*const ()>(b"CreateInterface")
            .expect("Failed to find CreateInterface in lua_shared"),
    );

    if i_lua_shared.is_null() {
        panic!("Failed to get ILuaShared");
    }

    let c_lua_interface = open_lua_interface(i_lua_shared, GmodLuaInterfaceRealm::Client);
    if c_lua_interface.is_null() {
        panic!("Failed to get CLuaInterface");
    }

    let lua_state = get_lua_state(c_lua_interface);

    {
        static mut GMOD_RS_SET_LUA_STATE: bool = false;
        if !core::mem::replace(&mut GMOD_RS_SET_LUA_STATE, true) {
            gmod::set_lua_state(lua_state);
        }
    }

    crate::init(gmod::lua::State(lua_state));
}

pub unsafe fn init_injection() {
    if is_ctor_binary_module() {
        // If we were loaded by GMOD_LoadBinaryModule, we don't need to hook CLuaManager::Startup
        return;
    }

    LUA_STATE.set(RtxLuaState::InjectedDll);

    init_logging_for_injected_dll();

    log::info!("DLL injected");

    let client_dll_path = client_dll_path();

    let (dll_path, sig, global, detour) = (
        client_dll_path,
        client_cluamanager_startup_sig(),
        &mut CLIENT_CLUAMANAGER_STARTUP,
        client_cluamanager_startup as *const (),
    );
    log::info!("Hooking CLuaManager::Startup in {}", dll_path);

    let cluamanager_startup_addr = sig.scan_module(dll_path).expect("Failed to find CLuaManager::Startup") as *const ();

    *global = Some({
        let cluamanager_startup = gmod::detour::RawDetour::new(cluamanager_startup_addr, detour).expect("Failed to hook CLuaManager::Startup");
        cluamanager_startup.enable().expect("Failed to enable CLuaManager::Startup hook");
        cluamanager_startup
    });
}

unsafe fn is_ctor_binary_module() -> bool {
    let lib = {
        #[cfg(windows)]
        {
            libloading::os::windows::Library::open_already_loaded("lua_shared")
        }
        #[cfg(unix)]
        {
            libloading::os::unix::Library::open(Some("lua_shared_srv"), libc::RTLD_NOLOAD)
                .or_else(|_| libloading::os::unix::Library::open(Some("lua_shared"), libc::RTLD_NOLOAD))
        }
    };

    let lib = lib.expect("Failed to find lua_shared");

    let i_lua_shared = get_lua_shared(
        *lib.get::<*const ()>(b"CreateInterface")
            .expect("Failed to find CreateInterface in lua_shared"),
    );
    if i_lua_shared.is_null() {
        panic!("Failed to get ILuaShared");
    }

    let cl = open_lua_interface(i_lua_shared, GmodLuaInterfaceRealm::Client);
    let sv = open_lua_interface(i_lua_shared, GmodLuaInterfaceRealm::Server);

    // This detection really sucks, can't really think of anything better
    if cl.is_null() && sv.is_null() {
        // We're being injected if the client and server Lua states are inactive
        false
    } else {
        // We're being loaded by GMOD_LoadBinaryModule
        true
    }
}

pub fn binary_module_init(lua: gmod::lua::State) {
    if !matches!(LUA_STATE.get(), RtxLuaState::InjectedDll) {
        LUA_STATE.set(RtxLuaState::BinaryModule(lua));
    }
}

pub unsafe fn init(lua: gmod::lua::State) {
    INIT_REFCOUNT += 1;

    if INIT_REFCOUNT != 1 {
        return;
    }

    log::info!(concat!("gmod_hook v", env!("CARGO_PKG_VERSION"), " loaded!"));
    
    // Initialize RTX Remix integration
    lua_stack_guard!(lua => {
        init_rtx_bindings(lua);
    });
}

unsafe fn init_rtx_bindings(lua: gmod::lua::State) {
    log::info!("Initializing RTX Remix Lua bindings...");
    
    // Create the RTX global table
    lua.create_table(0, 10);
    
    // Add SetEnableRaytracing function
    lua.push_function(lua_set_enable_raytracing);
    lua.set_field(-2, lua_string!("SetEnableRaytracing"));
    
    // Add GetRaytracingSupported function  
    lua.push_function(lua_get_raytracing_supported);
    lua.set_field(-2, lua_string!("GetRaytracingSupported"));
    
    // Add light management functions (placeholders for now)
    lua.push_function(lua_create_rtx_light);
    lua.set_field(-2, lua_string!("CreateRTXLight"));
    
    lua.push_function(lua_destroy_rtx_light);
    lua.set_field(-2, lua_string!("DestroyRTXLight"));
    
    lua.push_function(lua_draw_rtx_lights);
    lua.set_field(-2, lua_string!("DrawRTXLights"));
    
    // Set the global RTX table
    lua.set_global(lua_string!("RTX"));
    
    // Also add the functions to the global scope for backward compatibility
    lua.push_function(lua_set_enable_raytracing);
    lua.set_global(lua_string!("SetEnableRaytracing"));
    
    lua.push_function(lua_get_raytracing_supported);
    lua.set_global(lua_string!("GetRaytracingSupported"));
    
    lua.push_function(lua_create_rtx_light);
    lua.set_global(lua_string!("CreateRTXLight"));
    
    lua.push_function(lua_destroy_rtx_light);
    lua.set_global(lua_string!("DestroyRTXLight"));
    
    lua.push_function(lua_draw_rtx_lights);
    lua.set_global(lua_string!("DrawRTXLights"));
    
    log::info!("RTX Remix Lua bindings initialized successfully!");
    
    // Print to GMod console
    lua.get_global(lua_string!("print"));
    lua.push_string("[RTX] RTX Remix integration loaded successfully!");
    lua.call(1, 0);
    
    // Load the RTX addon files
    load_rtx_addon_files(lua);
}

// Lua binding functions
unsafe extern "C-unwind" fn lua_set_enable_raytracing(lua: gmod::lua::State) -> i32 {
    if lua.is_boolean(1) {
        let enabled = lua.get_boolean(1);
        log::info!("SetEnableRaytracing called with: {}", enabled);
        
        // TODO: Implement actual RTX Remix API call here
        // For now, just log the call
        
        // Return success
        lua.push_boolean(true);
        1
    } else {
        lua.push_boolean(false);
        1
    }
}

unsafe extern "C-unwind" fn lua_get_raytracing_supported(lua: gmod::lua::State) -> i32 {
    log::info!("GetRaytracingSupported called");
    
    // TODO: Implement actual RTX support detection
    // For now, return true if we're running
    lua.push_boolean(true);
    1
}

unsafe extern "C-unwind" fn lua_create_rtx_light(lua: gmod::lua::State) -> i32 {
    log::info!("CreateRTXLight called");
    
    // TODO: Implement RTX light creation
    // Return a dummy handle for now
    lua.push_number(1.0);
    1
}

unsafe extern "C-unwind" fn lua_destroy_rtx_light(lua: gmod::lua::State) -> i32 {
    if lua.get_top() >= 1 {
        let handle = lua.to_number(1);
        log::info!("DestroyRTXLight called with handle: {}", handle);
    }
    
    // TODO: Implement RTX light destruction
    0
}

unsafe extern "C-unwind" fn lua_draw_rtx_lights(_lua: gmod::lua::State) -> i32 {
    // TODO: Implement RTX lights drawing
    // This would typically be called per frame
    0
}

unsafe fn load_rtx_addon_files(lua: gmod::lua::State) {
    log::info!("Loading RTX addon files from injected DLL...");
    
    // Execute the core RTX initialization code
    execute_lua_code(lua, "rtxfixes_init", RTXFIXES_INIT_LUA);
    execute_lua_code(lua, "sh_rtx", SH_RTX_LUA);
    execute_lua_code(lua, "cl_rtx", CL_RTX_LUA);
    execute_lua_code(lua, "sh_flashlight_override", SH_FLASHLIGHT_OVERRIDE_LUA);
    
    log::info!("RTX addon files loaded successfully!");
}

unsafe fn execute_lua_code(lua: gmod::lua::State, name: &str, code: &str) {
    log::info!("Executing Lua code: {}", name);
    
    lua_stack_guard!(lua => {
        // Use lua.load_string with proper C string conversion
        let code_cstring = std::ffi::CString::new(code).expect("Failed to create CString");
        if lua.load_string(code_cstring.as_ptr()).is_ok() {
            // Use lua.pcall and check return value (0 = success)
            let result = lua.pcall(0, 0, 0);
            if result == 0 {
                log::info!("Successfully executed: {}", name);
            } else {
                log::info!("Error executing Lua code: {}", name);
                // Get error message from stack - just try to get string directly
                if let Some(error_msg) = lua.get_string(-1) {
                    log::info!("Lua error in {}: {}", name, error_msg.to_string());
                }
                lua.pop();
            }
        } else {
            log::info!("Error loading Lua code: {}", name);
        }
    });
}

pub unsafe fn shutdown() {
    INIT_REFCOUNT = INIT_REFCOUNT.saturating_sub(1);
    
    if INIT_REFCOUNT == 0 {
        // TODO: Add cleanup code here
    }
}

// Logging functions
pub unsafe fn init_logging_for_injected_dll() {
    std::fs::remove_file("gmod_hook.log").ok();

    LOGGER = Logger(
        std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .truncate(false)
            .open("gmod_hook.log")
            .ok(),
    );

    init_logging_for_binary_module();
}

pub unsafe fn init_logging_for_binary_module() {
    log::set_logger(&LOGGER).ok();
    log::set_max_level(log::LevelFilter::Info);
}

 