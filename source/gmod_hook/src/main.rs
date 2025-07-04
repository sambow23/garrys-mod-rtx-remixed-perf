mod rtx_handler;
mod process_utils;

use std::ffi::OsString;
use std::os::windows::ffi::OsStringExt;
use std::ptr;
use std::time::Duration;
use std::thread;
use std::io::Write;
use chrono;

use windows::Win32::Foundation::{GetLastError, HMODULE};
use windows::Win32::System::LibraryLoader::{GetModuleHandleExW, GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS};
use windows::Win32::System::Threading::GetCurrentProcessId;

use crate::rtx_handler::RTXHandler;
use crate::process_utils::ProcessUtils;

pub struct GmodHookHandler {
    rtx_handler: RTXHandler,
}

impl GmodHookHandler {
    pub fn new() -> Self {
        Self {
            rtx_handler: RTXHandler::new(),
        }
    }
    
    pub fn initialize(&mut self) -> Result<(), String> {
        // Use the new hook-based approach
        unsafe {
            rtx_handler::setup_lua_hook()
        }
    }
    
    pub fn shutdown(&mut self) {
        self.rtx_handler.shutdown();
    }
}

// DLL entry point for injection
#[no_mangle]
pub extern "system" fn DllMain(
    _hinst_dll: HMODULE,
    _fdw_reason: u32,
    _lpv_reserved: *mut std::ffi::c_void,
) -> i32 {
    // Try multiple log file locations
    let log_paths = vec![
        "rtx_debug.log".to_string(),
        "C:\\temp\\rtx_debug.log".to_string(),
        std::env::temp_dir().join("rtx_debug.log").to_string_lossy().to_string(),
    ];
    
    let debug_msg = format!("[RTX Handler] DllMain called with reason: {} at {}", _fdw_reason, chrono::Utc::now().format("%H:%M:%S%.3f"));
    println!("{}", debug_msg);
    
    // Try to write to any available log location
    let mut logged = false;
    for log_path in &log_paths {
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
            if writeln!(file, "{}", debug_msg).is_ok() {
                logged = true;
                break;
            }
        }
    }
    
    if !logged {
        // If we can't write to file, try creating a marker file
        for i in 0..10 {
            let marker_path = format!("rtx_injection_marker_{}.txt", i);
            if std::fs::write(&marker_path, &debug_msg).is_ok() {
                break;
            }
        }
    }
    
    // Only process DLL_PROCESS_ATTACH (reason 1)
    if _fdw_reason == 1 {
        let attach_msg = format!("[RTX Handler] DLL_PROCESS_ATTACH - Starting initialization... PID: {}", std::process::id());
        println!("{}", attach_msg);
        
        // Log attach message
        for log_path in &log_paths {
            if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                let _ = writeln!(file, "{}", attach_msg);
                break;
            }
        }
        
        unsafe {
            // Check if we're in GMod context
            if !rtx_handler::is_gmod_context() {
                let context_msg = "[RTX Handler] Not in GMod context, exiting gracefully";
                println!("{}", context_msg);
                for log_path in &log_paths {
                    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                        let _ = writeln!(file, "{}", context_msg);
                        break;
                    }
                }
                return 1; // Exit gracefully if not in GMod
            }
            
            let gmod_msg = "[RTX Handler] GMod context detected, setting up hook...";
            println!("{}", gmod_msg);
            for log_path in &log_paths {
                if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                    let _ = writeln!(file, "{}", gmod_msg);
                    break;
                }
            }
            
            // Set up the hook with proper timing
            if let Err(e) = rtx_handler::setup_lua_hook() {
                let error_msg = format!("[RTX Handler] Failed to setup RTX hook: {}", e);
                eprintln!("{}", error_msg);
                for log_path in &log_paths {
                    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                        let _ = writeln!(file, "{}", error_msg);
                        break;
                    }
                }
                return 0;
            }
            
            let success_msg = "[RTX Handler] Hook setup completed successfully";
            println!("{}", success_msg);
            for log_path in &log_paths {
                if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                    let _ = writeln!(file, "{}", success_msg);
                    break;
                }
            }
        }
    } else if _fdw_reason == 0 {
        let detach_msg = "[RTX Handler] DLL_PROCESS_DETACH - Cleaning up...";
        println!("{}", detach_msg);
        for log_path in &log_paths {
            if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                let _ = writeln!(file, "{}", detach_msg);
                break;
            }
        }
    }
    
    1
}

// Standalone injector
fn main() {
    println!("=== RTX Injector Debug Log ===");
    println!("Starting RTX injector...");
    
    let args: Vec<String> = std::env::args().collect();
    let no_wait = args.contains(&"--no-wait".to_string());
    
    println!("Command line args: {:?}", args);
    println!("No-wait mode: {}", no_wait);
    
    if !no_wait {
        println!("Waiting for GMod to start...");
        loop {
            if ProcessUtils::is_process_running("gmod.exe") || ProcessUtils::is_process_running("hl2.exe") {
                println!("GMod detected! Waiting 3 seconds for full initialization...");
                thread::sleep(Duration::from_secs(3));
                break;
            }
            print!(".");
            std::io::stdout().flush().unwrap();
            thread::sleep(Duration::from_millis(500));
        }
        println!();
    }
    
    // Find GMod process
    println!("Searching for GMod process...");
    let gmod_process = ProcessUtils::find_gmod_process();
    if gmod_process.is_none() {
        if no_wait {
            eprintln!("❌ GMod is not running. Use without --no-wait to wait for GMod.");
            std::process::exit(1);
        } else {
            eprintln!("❌ GMod process not found after detection. Something went wrong.");
            std::process::exit(1);
        }
    }
    
    let (pid, process_name) = gmod_process.unwrap();
    println!("✅ Found GMod process: {} (PID: {})", process_name, pid);
    
    // Get current executable path
    let current_exe = std::env::current_exe().expect("Failed to get current executable path");
    let dll_path = current_exe.parent().unwrap().join("gmod_hook.dll");
    
    println!("Current executable: {}", current_exe.display());
    println!("Looking for DLL at: {}", dll_path.display());
    
    if !dll_path.exists() {
        eprintln!("❌ gmod_hook.dll not found at: {}", dll_path.display());
        std::process::exit(1);
    }
    
    println!("✅ Found gmod_hook.dll ({} bytes)", dll_path.metadata().unwrap().len());
    
    println!("🔧 Injecting {} into GMod...", dll_path.display());
    
    // Inject the DLL
    match ProcessUtils::inject_dll(pid, &dll_path) {
        Ok(()) => {
            println!("✅ Successfully injected RTX hook into GMod!");
            
            // Wait a moment and check if debug log was created
            thread::sleep(Duration::from_secs(2));
            
            let debug_log_path = current_exe.parent().unwrap().join("rtx_debug.log");
            println!("Checking for debug log at: {}", debug_log_path.display());
            
            if debug_log_path.exists() {
                println!("✅ Debug log found! Contents:");
                match std::fs::read_to_string(&debug_log_path) {
                    Ok(contents) => {
                        println!("--- Debug Log Contents ---");
                        println!("{}", contents);
                        println!("--- End Debug Log ---");
                    }
                    Err(e) => {
                        println!("❌ Failed to read debug log: {}", e);
                    }
                }
            } else {
                println!("❌ Debug log not found. This suggests:");
                println!("   - DLL injection failed silently");
                println!("   - DLL was injected but DllMain wasn't called");
                println!("   - File permission issues");
                println!("   - Working directory mismatch");
                
                // Try to create a test file to check permissions
                let test_file = current_exe.parent().unwrap().join("injection_test.txt");
                match std::fs::write(&test_file, "Injection test") {
                    Ok(_) => {
                        println!("✅ File write permissions OK");
                        let _ = std::fs::remove_file(&test_file);
                    }
                    Err(e) => {
                        println!("❌ File write permission issue: {}", e);
                    }
                }
            }
        }
        Err(e) => {
            eprintln!("❌ Injection failed: {}", e);
            std::process::exit(1);
        }
    }
    
    println!("🔄 RTX integration active. You can now close this window.");
    println!("💡 Check GMod console (press ~) for RTX loading messages.");
    println!("Press Enter to exit...");
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
} 