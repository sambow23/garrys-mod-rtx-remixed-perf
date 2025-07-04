use std::{
    ffi::OsStr,
    path::PathBuf,
    time::{Duration, SystemTime},
};

#[cfg(windows)]
mod windows;

#[cfg(windows)]
use crate::windows::{Gmod, InjectedGmod};

fn main() {
    println!("RTX Injector v0.1.0 for GMod RTX Remix");

    loop {
        println!("Waiting for Garry's Mod to start...");

        let gmod = loop {
            match Gmod::find() {
                Some(gmod) => break gmod,
                None => {
                    std::thread::sleep(Duration::from_secs(5));
                    continue;
                }
            }
        };

        match gmod.pid() {
            Some(pid) => println!("Found Garry's Mod (pid {})", pid),
            None => println!("Found Garry's Mod (pid unknown)"),
        }

        println!("Injecting gmod_hook.dll...");

        let gmod = match gmod.inject() {
            Ok(gmod) => gmod,
            Err(err) => {
                eprintln!("Failed to inject gmod_hook.dll: {:?}", err);
                
                // Check for logs
                if let Ok(logs) = std::fs::read_to_string("rtx_handler_debug.log") {
                    println!("\n========= LOGS =========\n{}", logs);
                }
                
                std::thread::sleep(Duration::from_secs(5));
                continue;
            }
        };

        println!("Injected successfully!");

        println!("Waiting for Garry's Mod to close...");

        gmod.wait();
    }
} 