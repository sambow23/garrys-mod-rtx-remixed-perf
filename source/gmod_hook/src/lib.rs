use std::{cell::Cell, ffi::c_void};

pub mod rtx_handler;
pub use rtx_handler::RTXHandler;

// Only import gmod on supported platforms
#[cfg(any(target_os = "windows", target_os = "linux"))]
use gmod;

#[repr(u8)]
#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum GmodLuaInterfaceRealm {
    Client = 0,
    Server = 1,
    Menu = 2,
}

#[derive(Clone, Copy, Debug)]
pub enum GmodLoadingContext {
    Uninitialized,
    InjectedDll,
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    BinaryModule(gmod::lua::State),
    #[cfg(target_os = "macos")]
    BinaryModule(*mut c_void), // Use raw pointer on macOS
}

thread_local! {
    static LOADING_CONTEXT: Cell<GmodLoadingContext> = Cell::new(GmodLoadingContext::Uninitialized);
}

#[cfg(any(target_os = "windows", target_os = "linux"))]
pub fn get_current_lua_state() -> Option<gmod::lua::State> {
    if let GmodLoadingContext::BinaryModule(state) = LOADING_CONTEXT.get() {
        Some(state)
    } else {
        None
    }
}

#[cfg(target_os = "macos")]
pub fn get_current_lua_state() -> Option<*mut c_void> {
    if let GmodLoadingContext::BinaryModule(state) = LOADING_CONTEXT.get() {
        Some(state)
    } else {
        None
    }
}

#[cfg(any(target_os = "windows", target_os = "linux"))]
pub fn set_binary_module_context(lua: gmod::lua::State) {
    if !matches!(LOADING_CONTEXT.get(), GmodLoadingContext::InjectedDll) {
        LOADING_CONTEXT.set(GmodLoadingContext::BinaryModule(lua));
    }
}

#[cfg(target_os = "macos")]
pub fn set_binary_module_context(lua: *mut c_void) {
    if !matches!(LOADING_CONTEXT.get(), GmodLoadingContext::InjectedDll) {
        LOADING_CONTEXT.set(GmodLoadingContext::BinaryModule(lua));
    }
}

/// Trait for implementing custom module initialization
pub trait GmodHookHandler {
    /// Called when the module is successfully hooked and Lua state is available
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    unsafe fn on_lua_init(&self, lua: gmod::lua::State);
    
    /// Called when the module is successfully hooked and Lua state is available (macOS)
    #[cfg(target_os = "macos")]
    unsafe fn on_lua_init(&self, lua: *mut c_void);
    
    /// Called when the module is shutting down (optional)
    unsafe fn on_shutdown(&self) {}
}

/// Cross-platform DLL path resolution
#[macro_export]
macro_rules! dll_paths {
    ($($func:ident => $bin:literal / $linux_main_branch:literal),*) => {
        $(pub fn $func() -> &'static str {
            match () {
                _ if cfg!(all(windows, target_pointer_width = "64")) => concat!("bin/win64/", $bin, ".dll"),
                _ if cfg!(all(target_os = "linux", target_pointer_width = "64")) => concat!("bin/linux64/", $bin, ".so"),

                _ if cfg!(all(target_os = "macos")) => concat!("GarrysMod_Signed.app/Contents/MacOS/", $bin, ".dylib"),

                _ if cfg!(all(windows, target_pointer_width = "32")) => {
                    let x86_64_branch = concat!("bin/", $bin, ".dll");
                    if std::path::Path::new(x86_64_branch).exists() {
                        x86_64_branch
                    } else {
                        concat!("garrysmod/bin/", $bin, ".dll")
                    }
                },

                _ if cfg!(all(target_os = "linux", target_pointer_width = "32")) => {
                    let x86_64_branch = concat!("bin/linux32/", $bin, ".so");
                    if std::path::Path::new(x86_64_branch).exists() {
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

/// Convenience function to set up the standard hook system
pub unsafe fn setup_standard_hook<H: GmodHookHandler + 'static>(
    handler: H,
) -> Result<(), Box<dyn std::error::Error>> {
    // Store the handler
    static mut HANDLER: Option<Box<dyn GmodHookHandler>> = None;
    HANDLER = Some(Box::new(handler));

    // Try to detect if we're in the right context first
    if !is_gmod_context() {
        return Err("Not running in GMod context. This hook requires GMod to be running and the library to be loaded within GMod's process.".into());
    }

    // Try to get Lua state and initialize
    match acquire_lua_state() {
        Ok(lua) => {
            log::info!("Lua state acquired successfully");
            if let Some(handler) = HANDLER.as_ref() {
                handler.on_lua_init(lua);
            }
            Ok(())
        }
        Err(e) => {
            log::error!("Failed to acquire Lua state: {}", e);
            Err(e)
        }
    }
}

// Generate common DLL paths
dll_paths! {
    client_dll_path => "client"/"client",
    lua_shared_dll_path => "lua_shared"/"lua_shared",
    lua_shared_srv_dll_path => "lua_shared"/"lua_shared_srv"
}

/// C++ interface declarations (requires linking with appropriate C++ code)
extern "C" {
    pub fn get_lua_shared(create_interface_fn: *const ()) -> *mut c_void;
    pub fn open_lua_interface(i_lua_shared: *mut c_void, realm: GmodLuaInterfaceRealm) -> *mut c_void;
    pub fn get_lua_state_from_interface(c_lua_interface: *mut c_void) -> *mut c_void;
}

/// Detects if we're loaded as a binary module or injected
pub unsafe fn is_binary_module() -> bool {
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

    // If both client and server Lua states are inactive, we're being injected
    !(cl.is_null() && sv.is_null())
}

/// Gets the Lua state from the game engine
pub unsafe fn acquire_lua_state() -> Result<gmod::lua::State, Box<dyn std::error::Error>> {
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
    }?;

    let i_lua_shared = get_lua_shared(
        *lib.get::<*const ()>(b"CreateInterface")?,
    );

    if i_lua_shared.is_null() {
        return Err("Failed to get ILuaShared".into());
    }

    let c_lua_interface = open_lua_interface(i_lua_shared, GmodLuaInterfaceRealm::Client);
    if c_lua_interface.is_null() {
        return Err("Failed to get CLuaInterface".into());
    }

    let lua_state = get_lua_state_from_interface(c_lua_interface);
    
    // Set the global Lua state for gmod-rs
    {
        static mut GMOD_RS_SET_LUA_STATE: bool = false;
        if !core::mem::replace(&mut GMOD_RS_SET_LUA_STATE, true) {
            gmod::set_lua_state(lua_state);
        }
    }

    Ok(gmod::lua::State(lua_state))
}

/// Initialize the hooking system
pub unsafe fn init_hooks<H: GmodHookHandler>(_handler: H) -> Result<(), Box<dyn std::error::Error>> {
    if is_binary_module() {
        // If we're loaded as a binary module, we don't need to hook anything
        return Ok(());
    }

    LOADING_CONTEXT.set(GmodLoadingContext::InjectedDll);
    log::info!("DLL injected - setting up hooks");

    // Set up your specific hooks here
    // This is where you'd call hook_cluamanager_startup() or similar
    
    Ok(())
}

/// Check if we're running in GMod's context
pub unsafe fn is_gmod_context() -> bool {
    // Try to check if lua_shared is available
    let lib_result = {
        #[cfg(windows)]
        {
            libloading::os::windows::Library::open_already_loaded("lua_shared")
                .or_else(|_| libloading::os::windows::Library::open_already_loaded("lua_shared_srv"))
        }
        #[cfg(unix)]
        {
            libloading::os::unix::Library::open(Some("lua_shared_srv"), libc::RTLD_NOLOAD)
                .or_else(|_| libloading::os::unix::Library::open(Some("lua_shared"), libc::RTLD_NOLOAD))
        }
    };

    lib_result.is_ok()
} 