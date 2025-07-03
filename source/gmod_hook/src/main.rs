use gmod_hook::{RTXHandler, setup_standard_hook, init_hooks};

/// Main entry point for the RTX injection system
fn main() {
    // Initialize logging
    env_logger::init();
    
    println!("RTX Remix Fixes - Injection System");
    println!("==================================");
    
    // Create RTX handler
    let rtx_handler = RTXHandler::new();
    
    // Initialize the hook system
    unsafe {
        match setup_standard_hook(rtx_handler) {
            Ok(()) => {
                println!("RTX Hook system initialized successfully!");
                println!("RTX Lua addons will be injected when GMod starts");
            }
            Err(e) => {
                eprintln!("Failed to initialize RTX hook system: {}", e);
                std::process::exit(1);
            }
        }
    }
    
    // Keep the process running
    println!("RTX injection system running... Press Ctrl+C to exit");
    
    // In a real scenario, this would be called from a DLL entry point
    // For now, we'll just demonstrate the setup
    loop {
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
}

/// DLL entry point (for when compiled as a DLL)
#[cfg(windows)]
#[no_mangle]
pub extern "system" fn DllMain(
    _hinst_dll: *mut std::ffi::c_void,
    fdw_reason: u32,
    _lpv_reserved: *mut std::ffi::c_void,
) -> i32 {
    match fdw_reason {
        1 => {
            // DLL_PROCESS_ATTACH
            std::thread::spawn(|| {
                // Initialize the RTX hook system
                let rtx_handler = RTXHandler::new();
                unsafe {
                    if let Err(e) = setup_standard_hook(rtx_handler) {
                        eprintln!("Failed to initialize RTX hook system: {}", e);
                    }
                }
            });
        }
        0 => {
            // DLL_PROCESS_DETACH
            // Cleanup would go here
        }
        _ => {}
    }
    1 // TRUE
}

/// Linux/macOS shared library entry point
#[cfg(unix)]
#[no_mangle]
pub extern "C" fn _init() {
    std::thread::spawn(|| {
        // Initialize the RTX hook system
        let rtx_handler = RTXHandler::new();
        unsafe {
            if let Err(e) = setup_standard_hook(rtx_handler) {
                eprintln!("Failed to initialize RTX hook system: {}", e);
            }
        }
    });
} 