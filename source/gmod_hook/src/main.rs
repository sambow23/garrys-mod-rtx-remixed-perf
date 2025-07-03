mod rtx_handler;
mod process_utils;

use std::ffi::OsString;
use std::os::windows::ffi::OsStringExt;
use std::ptr;
use std::time::Duration;
use std::thread;

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
    unsafe {
        // Check if we're in GMod context
        if !rtx_handler::is_gmod_context() {
            return 1; // Exit gracefully if not in GMod
        }
        
        // Set up the hook with proper timing
        if let Err(e) = rtx_handler::setup_lua_hook() {
            eprintln!("Failed to setup RTX hook: {}", e);
            return 0;
        }
    }
    
    1
}

// Standalone injector
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let no_wait = args.contains(&"--no-wait".to_string());
    
    if !no_wait {
        println!("Waiting for GMod to start...");
        loop {
            if ProcessUtils::is_process_running("gmod.exe") || ProcessUtils::is_process_running("hl2.exe") {
                println!("GMod detected! Waiting 3 seconds for full initialization...");
                thread::sleep(Duration::from_secs(3));
                break;
            }
            thread::sleep(Duration::from_millis(500));
        }
    }
    
    // Find GMod process
    let gmod_process = ProcessUtils::find_gmod_process();
    if gmod_process.is_none() {
        if no_wait {
            eprintln!("GMod is not running. Use without --no-wait to wait for GMod.");
            std::process::exit(1);
        } else {
            eprintln!("GMod process not found after detection. Something went wrong.");
            std::process::exit(1);
        }
    }
    
    let (pid, process_name) = gmod_process.unwrap();
    println!("Found GMod process: {} (PID: {})", process_name, pid);
    
    // Get current executable path
    let current_exe = std::env::current_exe().expect("Failed to get current executable path");
    let dll_path = current_exe.parent().unwrap().join("gmod_hook.dll");
    
    if !dll_path.exists() {
        eprintln!("gmod_hook.dll not found at: {}", dll_path.display());
        std::process::exit(1);
    }
    
    println!("Injecting {} into GMod...", dll_path.display());
    
    // Inject the DLL
    match ProcessUtils::inject_dll(pid, &dll_path) {
        Ok(()) => println!("Successfully injected RTX hook into GMod!"),
        Err(e) => {
            eprintln!("Injection failed: {}", e);
            std::process::exit(1);
        }
    }
    
    println!("RTX integration active. You can now close this window.");
    println!("Press Enter to exit...");
    let mut input = String::new();
    std::io::stdin().read_line(&mut input).unwrap();
} 