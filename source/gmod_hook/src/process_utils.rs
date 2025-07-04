use std::path::Path;
use std::process::Command;
use std::os::windows::ffi::OsStrExt;
use std::io::Write;
use windows::Win32::System::Threading::{OpenProcess, PROCESS_ALL_ACCESS};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Memory::{VirtualAllocEx, VirtualFreeEx, MEM_COMMIT, MEM_RESERVE, PAGE_READWRITE, MEM_RELEASE};
use windows::Win32::System::Threading::{CreateRemoteThread, WaitForSingleObject, GetExitCodeThread};
use windows::Win32::System::LibraryLoader::GetProcAddress;
use windows::Win32::System::Diagnostics::Debug::WriteProcessMemory;
use windows::Win32::Foundation::{GetLastError, CloseHandle, WAIT_OBJECT_0, WAIT_TIMEOUT};

pub struct ProcessUtils;

impl ProcessUtils {
    /// Create a debug log function for detailed injection tracking
    fn debug_log(message: &str) {
        let timestamp = chrono::Utc::now().format("%H:%M:%S%.3f");
        let log_message = format!("[{}] [INJECTOR] {}", timestamp, message);
        
        // Print to console
        println!("{}", log_message);
        
        // Try to write to multiple log locations
        let temp_log_path = format!("{}\\rtx_injector_debug.log", std::env::temp_dir().display());
        let log_paths = vec![
            "rtx_injector_debug.log",
            "C:\\temp\\rtx_injector_debug.log",
            &temp_log_path,
        ];
        
        for log_path in &log_paths {
            if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(log_path) {
                if writeln!(file, "{}", log_message).is_ok() {
                    break;
                }
            }
        }
    }

    /// Check if a process is running
    pub fn is_process_running(process_name: &str) -> bool {
        Self::debug_log(&format!("Checking if process '{}' is running...", process_name));
        
        let output = Command::new("tasklist")
            .args(&["/FI", &format!("IMAGENAME eq {}", process_name)])
            .output();
            
        match output {
            Ok(output) => {
                let output_str = String::from_utf8_lossy(&output.stdout);
                let is_running = output_str.contains(process_name);
                Self::debug_log(&format!("Process '{}' running: {}", process_name, is_running));
                is_running
            }
            Err(e) => {
                Self::debug_log(&format!("Failed to check process '{}': {}", process_name, e));
                false
            }
        }
    }
    
    /// Find GMod process - returns (PID, process_name) if found
    pub fn find_gmod_process() -> Option<(u32, String)> {
        Self::debug_log("Searching for GMod process...");
        let gmod_processes = ["gmod.exe", "hl2.exe", "garrysmod.exe"];
        
        for process_name in &gmod_processes {
            Self::debug_log(&format!("Checking for process: {}", process_name));
            if let Some(pid) = Self::get_process_id(process_name) {
                Self::debug_log(&format!("Found GMod process: {} (PID: {})", process_name, pid));
                return Some((pid, process_name.to_string()));
            }
        }
        
        Self::debug_log("No GMod process found");
        None
    }
    
    /// Get process ID by name
    pub fn get_process_id(process_name: &str) -> Option<u32> {
        Self::debug_log(&format!("Getting PID for process: {}", process_name));
        
        let output = Command::new("tasklist")
            .args(&["/FI", &format!("IMAGENAME eq {}", process_name), "/FO", "CSV"])
            .output();
            
        match output {
            Ok(output) => {
                let output_str = String::from_utf8_lossy(&output.stdout);
                Self::debug_log(&format!("Tasklist output length: {} chars", output_str.len()));
                
                // Parse CSV output to find PID
                for (i, line) in output_str.lines().enumerate() {
                    if i == 0 {
                        Self::debug_log(&format!("CSV Header: {}", line));
                        continue; // Skip header
                    }
                    
                    if line.contains(process_name) {
                        Self::debug_log(&format!("Found matching line: {}", line));
                        let parts: Vec<&str> = line.split(',').collect();
                        if parts.len() >= 2 {
                            let pid_str = parts[1].trim_matches('"');
                            match pid_str.parse::<u32>() {
                                Ok(pid) => {
                                    Self::debug_log(&format!("Parsed PID: {}", pid));
                                    return Some(pid);
                                }
                                Err(e) => {
                                    Self::debug_log(&format!("Failed to parse PID '{}': {}", pid_str, e));
                                }
                            }
                        } else {
                            Self::debug_log(&format!("Line has insufficient parts: {}", parts.len()));
                        }
                    }
                }
                
                Self::debug_log(&format!("No matching process found for '{}'", process_name));
                None
            }
            Err(e) => {
                Self::debug_log(&format!("Failed to execute tasklist: {}", e));
                None
            }
        }
    }
    
    /// Inject DLL into process with comprehensive debugging
    pub fn inject_dll(pid: u32, dll_path: &Path) -> Result<(), String> {
        Self::debug_log(&format!("=== Starting DLL injection ==="));
        Self::debug_log(&format!("Target PID: {}", pid));
        Self::debug_log(&format!("DLL Path: {}", dll_path.display()));
        
        // Validate DLL exists and get size
        match std::fs::metadata(dll_path) {
            Ok(metadata) => {
                Self::debug_log(&format!("DLL file size: {} bytes", metadata.len()));
                if metadata.len() == 0 {
                    return Err("DLL file is empty".to_string());
                }
            }
            Err(e) => {
                let error = format!("Cannot access DLL file: {}", e);
                Self::debug_log(&error);
                return Err(error);
            }
        }
        
        unsafe {
            // Step 1: Open target process
            Self::debug_log("Step 1: Opening target process...");
            let process = match OpenProcess(PROCESS_ALL_ACCESS, false, pid) {
                Ok(handle) => {
                    Self::debug_log(&format!("Successfully opened process handle: {:?}", handle));
                    handle
                }
                Err(e) => {
                    let error = format!("Failed to open process (PID: {}): {} (Error code: {:?})", pid, e, GetLastError());
                    Self::debug_log(&error);
                    return Err(error);
                }
            };
            
            // Step 2: Get kernel32 module handle
            Self::debug_log("Step 2: Getting kernel32.dll handle...");
            let kernel32 = match GetModuleHandleW(windows::core::w!("kernel32.dll")) {
                Ok(handle) => {
                    Self::debug_log(&format!("Successfully got kernel32 handle: {:?}", handle));
                    handle
                }
                Err(e) => {
                    let error = format!("Failed to get kernel32 handle: {} (Error code: {:?})", e, GetLastError());
                    Self::debug_log(&error);
                    return Err(error);
                }
            };
            
            // Step 3: Get LoadLibraryW address
            Self::debug_log("Step 3: Getting LoadLibraryW address...");
            let loadlib_addr = match GetProcAddress(kernel32, windows::core::s!("LoadLibraryW")) {
                Some(addr) => {
                    Self::debug_log(&format!("Successfully got LoadLibraryW address: {:?}", addr));
                    addr
                }
                None => {
                    let error = format!("Failed to get LoadLibraryW address (Error code: {:?})", GetLastError());
                    Self::debug_log(&error);
                    return Err(error);
                }
            };
            
            // Step 4: Convert DLL path to wide string
            Self::debug_log("Step 4: Converting DLL path to wide string...");
            let dll_path_wide: Vec<u16> = dll_path.as_os_str()
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            
            let dll_path_size = dll_path_wide.len() * 2;
            Self::debug_log(&format!("Wide string length: {} chars, {} bytes", dll_path_wide.len(), dll_path_size));
            
            // Step 5: Allocate memory in target process
            Self::debug_log("Step 5: Allocating memory in target process...");
            let remote_mem = VirtualAllocEx(
                process,
                None,
                dll_path_size,
                MEM_COMMIT | MEM_RESERVE,
                PAGE_READWRITE
            );
            
            if remote_mem.is_null() {
                let error = format!("Failed to allocate memory in target process (Error code: {:?})", GetLastError());
                Self::debug_log(&error);
                return Err(error);
            }
            
            Self::debug_log(&format!("Successfully allocated {} bytes at address: {:?}", dll_path_size, remote_mem));
            
            // Step 6: Write DLL path to remote memory
            Self::debug_log("Step 6: Writing DLL path to remote memory...");
            let mut bytes_written = 0;
            let write_result = WriteProcessMemory(
                process,
                remote_mem,
                dll_path_wide.as_ptr() as *const std::ffi::c_void,
                dll_path_size,
                Some(&mut bytes_written)
            );
            
            if write_result.is_err() {
                let error = format!("Failed to write DLL path to target process (Error code: {:?})", GetLastError());
                Self::debug_log(&error);
                VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                return Err(error);
            }
            
            Self::debug_log(&format!("Successfully wrote {} bytes to remote memory", bytes_written));
            
            // Step 7: Create remote thread to call LoadLibraryW
            Self::debug_log("Step 7: Creating remote thread...");
            let thread = CreateRemoteThread(
                process,
                None,
                0,
                Some(std::mem::transmute(loadlib_addr)),
                Some(remote_mem),
                0,
                None
            );
            
            match thread {
                Ok(thread_handle) => {
                    Self::debug_log(&format!("Successfully created remote thread: {:?}", thread_handle));
                    
                    // Step 8: Wait for thread to complete
                    Self::debug_log("Step 8: Waiting for remote thread to complete...");
                    let wait_result = WaitForSingleObject(thread_handle, 10000); // 10 second timeout
                    
                    match wait_result {
                        WAIT_OBJECT_0 => {
                            Self::debug_log("Remote thread completed successfully");
                            
                            // Get the exit code to see if LoadLibraryW succeeded
                            let mut exit_code = 0;
                            if GetExitCodeThread(thread_handle, &mut exit_code).is_ok() {
                                if exit_code == 0 {
                                    Self::debug_log("WARNING: LoadLibraryW returned 0 (failed to load DLL)");
                                } else {
                                    Self::debug_log(&format!("LoadLibraryW returned module handle: 0x{:X}", exit_code));
                                }
                            } else {
                                Self::debug_log("Failed to get thread exit code");
                            }
                        }
                        WAIT_TIMEOUT => {
                            Self::debug_log("WARNING: Remote thread timed out");
                        }
                        _ => {
                            Self::debug_log(&format!("Remote thread wait failed: {:?}", wait_result));
                        }
                    }
                    
                    // Clean up
                    Self::debug_log("Step 9: Cleaning up resources...");
                    CloseHandle(thread_handle);
                    VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                    CloseHandle(process);
                    
                    Self::debug_log("=== DLL injection completed ===");
                    Ok(())
                }
                Err(e) => {
                    let error = format!("Failed to create remote thread: {} (Error code: {:?})", e, GetLastError());
                    Self::debug_log(&error);
                    VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                    CloseHandle(process);
                    Err(error)
                }
            }
        }
    }
} 