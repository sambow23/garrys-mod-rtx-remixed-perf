use gmod_hook::{RTXHandler, setup_standard_hook, is_gmod_context};
use std::thread;
use std::time::Duration;

/// Main entry point for the RTX injection system
fn main() {
    // Initialize logging
    env_logger::init();
    
    println!("RTX Remix Fixes - Injection System");
    println!("==================================");
    
    // Check command line arguments
    let args: Vec<String> = std::env::args().collect();
    let no_wait = args.len() > 1 && args[1] == "--no-wait";
    
    // Check if we're already in GMod context
    let in_gmod_context = unsafe { is_gmod_context() };
    
    if !in_gmod_context && no_wait {
        println!("⚠️  GMod is not running or this process is not in GMod context.");
        println!();
        println!("Usage: rtx_injector.exe [--no-wait]");
        println!("  --no-wait    Don't wait for GMod to start (exit immediately if not found)");
        println!();
        println!("Alternative usage:");
        println!("  1. Inject gmod_hook.dll into running GMod process using a DLL injector");
        println!("  2. Copy gmod_hook.dll to GMod's binary modules folder");
        println!("  3. Start GMod and run this executable (waits by default)");
        println!();
        println!("Current status: GMod context = {}", in_gmod_context);
        
        // Don't exit immediately, let user see the message
        thread::sleep(Duration::from_secs(5));
        return;
    }
    
    if !in_gmod_context {
        println!("🔍 GMod is not running. Waiting for Garry's Mod to start...");
        println!("💡 Tip: Start GMod now, or use --no-wait to exit immediately");
        wait_for_gmod_process();
    } else {
        println!("✅ GMod context detected!");
    }
    
    // Create RTX handler
    let rtx_handler = RTXHandler::new();
    
    // Initialize the hook system
    unsafe {
        match setup_standard_hook(rtx_handler) {
            Ok(()) => {
                println!("✅ RTX Hook system initialized successfully!");
                println!("🎮 RTX Lua addons are now active in GMod");
            }
            Err(e) => {
                eprintln!("❌ Failed to initialize RTX hook system: {}", e);
                println!("\n💡 Try injecting the DLL directly into GMod instead.");
                thread::sleep(Duration::from_secs(3));
                std::process::exit(1);
            }
        }
    }
    
    // Keep the process running
    println!("🔄 RTX injection system running... Press Ctrl+C to exit");
    
    loop {
        thread::sleep(Duration::from_secs(1));
    }
}

/// Wait for GMod process to start
fn wait_for_gmod_process() {
    println!("🔍 Scanning for GMod process...");
    
    let mut dot_count = 0;
    loop {
        if is_gmod_running() {
            println!("\n🎮 GMod process detected! Attempting injection...");
            thread::sleep(Duration::from_secs(2)); // Give GMod time to fully load
            break;
        }
        
        // Show progress dots
        print!(".");
        dot_count += 1;
        if dot_count % 60 == 0 {
            println!(" ({}s)", dot_count);
        }
        
        thread::sleep(Duration::from_secs(1));
    }
}

/// Check if GMod is running
fn is_gmod_running() -> bool {
    use std::process::Command;
    
    // Check for common GMod process names
    let gmod_processes = ["gmod.exe", "hl2.exe", "garrysmod.exe"];
    
    for process_name in &gmod_processes {
        let output = Command::new("tasklist")
            .args(&["/FI", &format!("IMAGENAME eq {}", process_name)])
            .output();
            
        if let Ok(output) = output {
            let output_str = String::from_utf8_lossy(&output.stdout);
            if output_str.contains(process_name) {
                return true;
            }
        }
    }
    
    false
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
            thread::spawn(|| {
                // Initialize logging for DLL mode
                env_logger::init();
                
                println!("[RTX Hook] DLL injected into process");
                
                // Initialize the RTX hook system
                let rtx_handler = RTXHandler::new();
                unsafe {
                    if let Err(e) = setup_standard_hook(rtx_handler) {
                        eprintln!("[RTX Hook] Failed to initialize: {}", e);
                    } else {
                        println!("[RTX Hook] RTX injection system initialized successfully!");
                    }
                }
            });
        }
        0 => {
            // DLL_PROCESS_DETACH
            println!("[RTX Hook] DLL unloading");
        }
        _ => {}
    }
    1 // TRUE
}

/// Linux/macOS shared library entry point
#[cfg(unix)]
#[no_mangle]
pub extern "C" fn _init() {
    thread::spawn(|| {
        // Initialize logging for shared library mode
        env_logger::init();
        
        println!("[RTX Hook] Shared library loaded");
        
        // Initialize the RTX hook system
        let rtx_handler = RTXHandler::new();
        unsafe {
            if let Err(e) = setup_standard_hook(rtx_handler) {
                eprintln!("[RTX Hook] Failed to initialize: {}", e);
            } else {
                println!("[RTX Hook] RTX injection system initialized successfully!");
            }
        }
    });
} 