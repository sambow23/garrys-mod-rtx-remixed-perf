use std::path::Path;
use std::process::Command;
use std::os::windows::ffi::OsStrExt;
use windows::Win32::System::Threading::{OpenProcess, PROCESS_ALL_ACCESS};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Memory::{VirtualAllocEx, VirtualFreeEx, MEM_COMMIT, MEM_RESERVE, PAGE_READWRITE, MEM_RELEASE};
use windows::Win32::System::Threading::{CreateRemoteThread, WaitForSingleObject};
use windows::Win32::System::LibraryLoader::GetProcAddress;
use windows::Win32::System::Diagnostics::Debug::WriteProcessMemory;

pub struct ProcessUtils;

impl ProcessUtils {
    /// Check if a process is running
    pub fn is_process_running(process_name: &str) -> bool {
        let output = Command::new("tasklist")
            .args(&["/FI", &format!("IMAGENAME eq {}", process_name)])
            .output();
            
        if let Ok(output) = output {
            let output_str = String::from_utf8_lossy(&output.stdout);
            output_str.contains(process_name)
        } else {
            false
        }
    }
    
    /// Find GMod process - returns (PID, process_name) if found
    pub fn find_gmod_process() -> Option<(u32, String)> {
        let gmod_processes = ["gmod.exe", "hl2.exe", "garrysmod.exe"];
        
        for process_name in &gmod_processes {
            if let Some(pid) = Self::get_process_id(process_name) {
                return Some((pid, process_name.to_string()));
            }
        }
        
        None
    }
    
    /// Get process ID by name
    pub fn get_process_id(process_name: &str) -> Option<u32> {
        let output = Command::new("tasklist")
            .args(&["/FI", &format!("IMAGENAME eq {}", process_name), "/FO", "CSV"])
            .output();
            
        if let Ok(output) = output {
            let output_str = String::from_utf8_lossy(&output.stdout);
            // Parse CSV output to find PID
            for line in output_str.lines().skip(1) { // Skip header
                if line.contains(process_name) {
                    let parts: Vec<&str> = line.split(',').collect();
                    if parts.len() >= 2 {
                        let pid_str = parts[1].trim_matches('"');
                        if let Ok(pid) = pid_str.parse::<u32>() {
                            return Some(pid);
                        }
                    }
                }
            }
        }
        
        None
    }
    
    /// Inject DLL into process
    pub fn inject_dll(pid: u32, dll_path: &Path) -> Result<(), String> {
        unsafe {
            // Open target process
            let process = OpenProcess(PROCESS_ALL_ACCESS, false, pid)
                .map_err(|e| format!("Failed to open process: {}", e))?;
            
            // Get LoadLibraryW address
            let kernel32 = GetModuleHandleW(windows::core::w!("kernel32.dll"))
                .map_err(|e| format!("Failed to get kernel32 handle: {}", e))?;
            
            let loadlib_addr = GetProcAddress(kernel32, windows::core::s!("LoadLibraryW"))
                .ok_or("Failed to get LoadLibraryW address")?;
            
            // Convert DLL path to wide string
            let dll_path_wide: Vec<u16> = dll_path.as_os_str()
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            
            let dll_path_size = dll_path_wide.len() * 2;
            
            // Allocate memory in target process
            let remote_mem = VirtualAllocEx(
                process,
                None,
                dll_path_size,
                MEM_COMMIT | MEM_RESERVE,
                PAGE_READWRITE
            );
            
            if remote_mem.is_null() {
                return Err("Failed to allocate memory in target process".to_string());
            }
            
            // Write DLL path to remote memory
            let mut bytes_written = 0;
            let write_result = WriteProcessMemory(
                process,
                remote_mem,
                dll_path_wide.as_ptr() as *const std::ffi::c_void,
                dll_path_size,
                Some(&mut bytes_written)
            );
            
            if write_result.is_err() {
                VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                return Err("Failed to write DLL path to target process".to_string());
            }
            
            // Create remote thread to call LoadLibraryW
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
                    // Wait for thread to complete
                    WaitForSingleObject(thread_handle, 5000);
                    
                    // Clean up
                    VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                    
                    Ok(())
                }
                Err(e) => {
                    VirtualFreeEx(process, remote_mem, 0, MEM_RELEASE);
                    Err(format!("Failed to create remote thread: {}", e))
                }
            }
        }
    }
} 