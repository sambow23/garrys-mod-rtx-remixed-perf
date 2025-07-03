use std::{cell::Cell, ffi::c_void, path::Path};

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
pub fn get_lua_state() -> Option<gmod::lua::State> {
    if let GmodLoadingContext::BinaryModule(state) = LOADING_CONTEXT.get() {
        Some(state)
    } else {
        None
    }
}

#[cfg(target_os = "macos")]
pub fn get_lua_state() -> Option<*mut c_void> {
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

/// Generic function hooking macro
#[macro_export]
macro_rules! create_detour {
    ($name:ident, $func_type:ty, $hook_impl:expr, $sigs:expr) => {
        paste::paste! {
            static mut [<$name:upper _DETOUR>]: Option<gmod::detour::RawDetour> = None;

            #[cfg_attr(target_pointer_width = "64", fn_abi::abi("fastcall"))]
            #[cfg_attr(all(target_os = "windows", target_pointer_width = "32"), fn_abi::abi("thiscall"))]
            #[cfg_attr(all(target_os = "linux", target_pointer_width = "32"), fn_abi::abi("C"))]
            unsafe extern "C" fn [<$name _hook>](this: *mut c_void) {
                let trampoline = core::mem::transmute::<_, $func_type>(
                    [<$name:upper _DETOUR>].as_ref().unwrap().trampoline() as *const ()
                );
                $hook_impl(this, trampoline);
            }

            fn [<$name _signature>]() -> gmod::sigscan::Signature {
                $sigs
            }

            pub unsafe fn [<hook_ $name>](dll_path: &str) -> Result<(), Box<dyn std::error::Error>> {
                log::info!("Hooking {} in {}", stringify!($name), dll_path);
                
                let sig = [<$name _signature>]();
                let target_fn = sig.scan_module(dll_path)? as *const ();
                
                let detour = gmod::detour::RawDetour::new(target_fn, [<$name _hook>] as *const ())?;
                detour.enable()?;
                
                [<$name:upper _DETOUR>] = Some(detour);
                Ok(())
            }
        }
    };
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
    pub fn get_lua_state(c_lua_interface: *mut c_void) -> *mut c_void;
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

    let lua_state = get_lua_state(c_lua_interface);
    
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
pub unsafe fn init_hooks<H: GmodHookHandler>(handler: H) -> Result<(), Box<dyn std::error::Error>> {
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

/// Convenience function to set up CLuaManager::Startup hook
pub unsafe fn setup_standard_hook<H: GmodHookHandler + 'static>(
    handler: H,
) -> Result<(), Box<dyn std::error::Error>> {
    static mut HANDLER: Option<Box<dyn GmodHookHandler>> = None;
    HANDLER = Some(Box::new(handler));

    // Only support Windows and Linux for now due to signature scanning limitations
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        // Define the CLuaManager::Startup hook
        type CLuaManagerStartupFn = extern "C" fn(this: *mut c_void);
        
        let sigs = match () {
            _ if cfg!(all(target_pointer_width = "64", target_os = "windows")) => {
                gmod::sigscan::signature!("48 89 5C 24 ? 48 89 74 24 ? 57 48 83 EC 60 48 8B 05 ? ? ? ? 48 33 C4 48 89 44 24 ? 48 8B F1 48 8D 0D ? ? ? ? FF 15 ? ? ? ? E8 ? ? ? ? F3 0F 10 0D")
            },
            _ if cfg!(all(target_pointer_width = "32", target_os = "windows")) => {
                gmod::sigscan::signature!("55 8B EC 83 EC 18 53 68 ? ? ? ? 8B D9 FF 15 ? ? ? ? 83 C4 04 E8 ? ? ? ? D9 05 ? ? ? ? 68 ? ? ? ? 51 8B 10 8B C8 D9 1C 24")
            },
            _ if cfg!(target_os = "linux") => {
                // Linux signature - may need adjustment
                gmod::sigscan::signature!("55 48 89 E5 41 57 41 56 41 55 41 54 53 48 83 EC 28")
            },
            _ => return Err("Unsupported platform".into()),
        };

        create_detour!(
            cluamanager_startup,
            CLuaManagerStartupFn,
            |this, trampoline| {
                trampoline(this);
                if let Some(handler) = HANDLER.as_ref() {
                    if let Ok(lua) = acquire_lua_state() {
                        handler.on_lua_init(lua);
                    }
                }
            },
            sigs
        );

        hook_cluamanager_startup(client_dll_path())?;
    }
    
    // For macOS, try to use alternative approach without signature scanning
    #[cfg(target_os = "macos")]
    {
        log::warn!("macOS detected - signature scanning not available. Using alternative approach.");
        // For now, just call the handler directly to test the Lua loading
        if let Ok(lua) = acquire_lua_state() {
            if let Some(handler) = HANDLER.as_ref() {
                handler.on_lua_init(lua);
            }
        }
    }
    
    Ok(())
} 