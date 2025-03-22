// GmodPatcher.cpp
#include <Windows.h>
#include <TlHelp32.h>
#include <Psapi.h>
#include <string>
#include <vector>
#include <iostream>
#include <fstream>
#include <thread>
#include <chrono>

// Structure for patch information
struct PatchInfo {
    std::string moduleName;
    std::string pattern;
    int offset;
    std::string replacement;
};

// Function to convert hex string to bytes
std::vector<uint8_t> HexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        uint8_t byte = (uint8_t)strtol(byteString.c_str(), NULL, 16);
        bytes.push_back(byte);
    }
    return bytes;
}

// Function to find a pattern in memory
bool FindPattern(const uint8_t* data, size_t dataSize, const std::string& pattern, size_t& outPosition) {
    // Convert pattern to bytes, handling wildcards
    std::vector<std::string> parts;
    size_t start = 0;
    size_t pos;

    // Split by wildcards
    while ((pos = pattern.find("??", start)) != std::string::npos) {
        if (pos > start) {
            parts.push_back(pattern.substr(start, pos - start));
        }
        else {
            parts.push_back("");
        }
        start = pos + 2;
    }

    // Add the last part
    if (start < pattern.length()) {
        parts.push_back(pattern.substr(start));
    }

    // Simple case - no wildcards
    if (parts.size() == 1) {
        std::vector<uint8_t> patternBytes = HexToBytes(pattern);
        for (size_t i = 0; i <= dataSize - patternBytes.size(); i++) {
            bool match = true;
            for (size_t j = 0; j < patternBytes.size(); j++) {
                if (data[i + j] != patternBytes[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                outPosition = i;
                return true;
            }
        }
        return false;
    }

    // Complex case - wildcards
    size_t searchPos = 0;
    while (searchPos < dataSize) {
        std::vector<uint8_t> firstPart = HexToBytes(parts[0]);
        bool found = false;
        size_t firstPartPos = 0;

        for (size_t i = searchPos; i <= dataSize - firstPart.size(); i++) {
            bool match = true;
            for (size_t j = 0; j < firstPart.size(); j++) {
                if (data[i + j] != firstPart[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                found = true;
                firstPartPos = i;
                break;
            }
        }

        if (!found) {
            return false;
        }

        // Check if rest of parts match
        bool allMatch = true;
        size_t checkPos = firstPartPos;

        for (size_t i = 0; i < parts.size(); i++) {
            if (!parts[i].empty()) {
                std::vector<uint8_t> partBytes = HexToBytes(parts[i]);
                checkPos += (i > 0) ? 1 : 0; // Skip wildcard byte

                if (checkPos + partBytes.size() > dataSize) {
                    allMatch = false;
                    break;
                }

                for (size_t j = 0; j < partBytes.size(); j++) {
                    if (data[checkPos + j] != partBytes[j]) {
                        allMatch = false;
                        break;
                    }
                }

                if (!allMatch) {
                    break;
                }

                checkPos += partBytes.size();
            }
            else {
                checkPos += 1; // Skip wildcard
            }
        }

        if (allMatch) {
            outPosition = firstPartPos;
            return true;
        }

        // Continue search
        searchPos = firstPartPos + 1;
    }

    return false;
}

// Apply a patch to a process
bool ApplyPatch(HANDLE process, HMODULE moduleHandle, const PatchInfo& patch) {
    MODULEINFO moduleInfo;
    if (!GetModuleInformation(process, moduleHandle, &moduleInfo, sizeof(moduleInfo))) {
        std::cout << "Failed to get module info for " << patch.moduleName << std::endl;
        return false;
    }

    std::vector<uint8_t> moduleData(moduleInfo.SizeOfImage);
    SIZE_T bytesRead;
    if (!ReadProcessMemory(process, moduleHandle, moduleData.data(), moduleInfo.SizeOfImage, &bytesRead)) {
        std::cout << "Failed to read module memory for " << patch.moduleName << std::endl;
        return false;
    }

    size_t patternPos = 0;
    if (FindPattern(moduleData.data(), bytesRead, patch.pattern, patternPos)) {
        uintptr_t patchAddr = (uintptr_t)moduleHandle + patternPos + patch.offset;
        std::vector<uint8_t> replacementBytes = HexToBytes(patch.replacement);

        // Save original bytes for logging
        std::vector<uint8_t> originalBytes(replacementBytes.size());
        if (!ReadProcessMemory(process, (LPVOID)patchAddr, originalBytes.data(), originalBytes.size(), &bytesRead)) {
            std::cout << "Failed to read original bytes at " << std::hex << patchAddr << std::dec << std::endl;
            return false;
        }

        // Format original bytes for display
        std::string originalHex;
        for (auto b : originalBytes) {
            char hex[3];
            sprintf_s(hex, "%02x", b);
            originalHex += hex;
        }

        // Apply the patch
        DWORD oldProtect;
        if (!VirtualProtectEx(process, (LPVOID)patchAddr, replacementBytes.size(), PAGE_EXECUTE_READWRITE, &oldProtect)) {
            std::cout << "Failed to change memory protection for " << patch.moduleName << std::endl;
            return false;
        }

        if (!WriteProcessMemory(process, (LPVOID)patchAddr, replacementBytes.data(), replacementBytes.size(), NULL)) {
            std::cout << "Failed to write patch bytes to " << patch.moduleName << std::endl;
            return false;
        }

        // Restore protection
        DWORD temp;
        VirtualProtectEx(process, (LPVOID)patchAddr, replacementBytes.size(), oldProtect, &temp);

        // Flush instruction cache
        FlushInstructionCache(process, (LPVOID)patchAddr, replacementBytes.size());

        std::cout << "Patched " << patch.moduleName << " at 0x" << std::hex << patchAddr << std::dec
            << ": Changed '" << originalHex << "' to '" << patch.replacement << "'" << std::endl;
        return true;
    }

    std::cout << "Pattern not found in " << patch.moduleName << std::endl;
    return false;
}

// Enhanced module listing function to show paths
void ListAllModules(HANDLE process) {
    HMODULE modules[1024];
    DWORD needed;
    if (EnumProcessModules(process, modules, sizeof(modules), &needed)) {
        size_t count = needed / sizeof(HMODULE);
        std::cout << "--- Found " << count << " loaded modules: ---" << std::endl;

        // First list specifically bin/win64 modules
        std::cout << "IMPORTANT MODULES IN BIN/WIN64:" << std::endl;
        for (size_t i = 0; i < count; i++) {
            char modName[MAX_PATH];
            if (GetModuleFileNameExA(process, modules[i], modName, sizeof(modName))) {
                std::string fullPath = modName;
                if (fullPath.find("\\bin\\win64\\") != std::string::npos) {
                    size_t pos = fullPath.find_last_of('\\');
                    std::string name = (pos != std::string::npos) ? fullPath.substr(pos + 1) : fullPath;

                    if (name == "engine.dll" || name == "client.dll" ||
                        name == "shaderapidx9.dll" || name == "materialsystem.dll" ||
                        name == "gmod.exe") {
                        std::cout << "  " << name << " [0x" << std::hex << modules[i] << std::dec << "]" << std::endl;
                        std::cout << "    Path: " << fullPath << std::endl;
                    }
                }
            }
        }

        // Then list other important modules regardless of path
        std::cout << "OTHER IMPORTANT MODULES:" << std::endl;
        for (size_t i = 0; i < count; i++) {
            char modName[MAX_PATH];
            if (GetModuleFileNameExA(process, modules[i], modName, sizeof(modName))) {
                std::string fullPath = modName;
                size_t pos = fullPath.find_last_of('\\');
                std::string name = (pos != std::string::npos) ? fullPath.substr(pos + 1) : fullPath;

                if ((name == "engine.dll" || name == "client.dll" ||
                    name == "shaderapidx9.dll" || name == "materialsystem.dll" ||
                    name == "gmod.exe") &&
                    fullPath.find("\\bin\\win64\\") == std::string::npos) {
                    std::cout << "  " << name << " [0x" << std::hex << modules[i] << std::dec << "]" << std::endl;
                    std::cout << "    Path: " << fullPath << std::endl;
                }
            }
        }

        std::cout << "--------------------------------" << std::endl;
    }
    else {
        std::cout << "Failed to enumerate modules" << std::endl;
    }
}

// Improved version of GetRemoteModuleHandle for bin/win64 structure
HMODULE GetRemoteModuleHandleImproved(HANDLE process, const char* moduleName) {
    // Method 1: Try standard enumeration
    HMODULE modules[1024];
    DWORD needed;
    if (EnumProcessModules(process, modules, sizeof(modules), &needed)) {
        for (unsigned int i = 0; i < (needed / sizeof(HMODULE)); i++) {
            char modName[MAX_PATH];
            if (GetModuleFileNameExA(process, modules[i], modName, sizeof(modName))) {
                // First check if the full path contains bin/win64
                std::string fullPath = modName;
                if (fullPath.find("\\bin\\win64\\") != std::string::npos) {
                    // Extract just the filename
                    size_t pos = fullPath.find_last_of('\\');
                    std::string name = (pos != std::string::npos) ? fullPath.substr(pos + 1) : fullPath;

                    if (_stricmp(name.c_str(), moduleName) == 0) {
                        std::cout << "Found module " << moduleName << " at path: " << fullPath << std::endl;
                        return modules[i];
                    }
                }
            }
        }

        // If we didn't find in bin/win64 specifically, try anywhere
        for (unsigned int i = 0; i < (needed / sizeof(HMODULE)); i++) {
            char modName[MAX_PATH];
            if (GetModuleFileNameExA(process, modules[i], modName, sizeof(modName))) {
                std::string fullPath = modName;
                size_t pos = fullPath.find_last_of('\\');
                std::string name = (pos != std::string::npos) ? fullPath.substr(pos + 1) : fullPath;

                if (_stricmp(name.c_str(), moduleName) == 0) {
                    std::cout << "Found module " << moduleName << " at path: " << fullPath << std::endl;
                    return modules[i];
                }
            }
        }
    }

    // Module not found using standard method
    return NULL;
}

void PatchMonitorThread(DWORD pid, const std::vector<PatchInfo>& patches) {
    bool firstRun = true;
    bool modulesListed = false;
    int retryCount = 0;

    while (true) {
        // Open process with specific permissions to avoid handle issues
        HANDLE process = OpenProcess(PROCESS_ALL_ACCESS, FALSE, pid);

        if (!process) {
            DWORD error = GetLastError();
            std::cout << "Warning: Cannot open process (Error " << error << "). Retrying in 5 seconds..." << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(5));
            continue;
        }

        // Check if process is still alive more reliably
        DWORD exitCode = 0;
        if (!GetExitCodeProcess(process, &exitCode)) {
            DWORD error = GetLastError();
            std::cout << "Warning: GetExitCodeProcess failed (Error " << error << ")" << std::endl;
            CloseHandle(process);
            std::this_thread::sleep_for(std::chrono::seconds(5));
            continue;
        }

        if (exitCode != STILL_ACTIVE) {
            std::cout << "Game process has terminated with exit code: " << exitCode << std::endl;
            CloseHandle(process);
            break;
        }

        // Only on first run or after reconnecting
        if (firstRun) {
            std::cout << "Waiting for modules to load (initial wait)..." << std::endl;
            std::this_thread::sleep_for(std::chrono::seconds(5)); //  initial wait

            // List the modules to help diagnose issues
            std::cout << "Listing currently loaded modules:" << std::endl;
            ListAllModules(process);
            modulesListed = true;

            std::cout << "Starting patch application..." << std::endl;

            // Keep track of how many modules we found
            int modulesFound = 0;

            // Try to apply all patches
            for (const auto& patch : patches) {
                HMODULE moduleHandle = GetRemoteModuleHandleImproved(process, patch.moduleName.c_str());
                if (moduleHandle) {
                    modulesFound++;
                    if (ApplyPatch(process, moduleHandle, patch)) {
                        std::cout << "Successfully applied patch to " << patch.moduleName << std::endl;
                    }
                    else {
                        std::cout << "Failed to apply patch to " << patch.moduleName << std::endl;
                    }
                }
                else {
                    std::cout << "Module not found: " << patch.moduleName << std::endl;
                }
            }

            // If we didn't find any modules, we should retry after waiting
            if (modulesFound == 0) {
                std::cout << "No required modules found yet. Waiting longer..." << std::endl;
                CloseHandle(process);

                // Increment retry count and wait progressively longer
                retryCount++;
                int waitTime = 10 + (retryCount * 5); // Progressive backoff
                if (waitTime > 60) waitTime = 60; // Cap at 60 seconds

                std::cout << "Retry " << retryCount << ": Waiting " << waitTime << " seconds..." << std::endl;
                std::this_thread::sleep_for(std::chrono::seconds(waitTime));
                continue; // Try again
            }

            firstRun = false;
        }
        else {
            // Periodic check to reapply if needed
            std::cout << "Checking patch integrity..." << std::endl;

            // List modules periodically to help debug
            if (!modulesListed || (retryCount % 5 == 0)) {
                std::cout << "Refreshing module list:" << std::endl;
                ListAllModules(process);
                modulesListed = true;
            }

            // Reapply patches
            for (const auto& patch : patches) {
                HMODULE moduleHandle = GetRemoteModuleHandleImproved(process, patch.moduleName.c_str());
                if (moduleHandle) {
                    ApplyPatch(process, moduleHandle, patch);
                }
            }

            // Add visual confirmation that the monitoring is working
            std::cout << "Monitoring active - Game is running (PID: " << pid << ")" << std::endl;
        }

        // Always close the handle before sleeping to prevent issues
        CloseHandle(process);

        // Sleep between checks
        std::this_thread::sleep_for(std::chrono::seconds(10));
    }

    std::cout << "Monitoring thread ending" << std::endl;
}


// Get the directory of the current executable
std::string GetExecutableDirectory() {
    char path[MAX_PATH];
    GetModuleFileNameA(NULL, path, MAX_PATH);
    std::string strPath(path);
    size_t pos = strPath.find_last_of("\\/");
    return strPath.substr(0, pos + 1);
}

// Get command line arguments as a string
std::string GetCommandLineArgs() {
    std::string cmdLine = GetCommandLineA();

    // Find the first space after the executable path
    size_t pos = 0;
    if (cmdLine[0] == '"') {
        // Path is quoted
        pos = cmdLine.find('"', 1);
        if (pos != std::string::npos) {
            pos++; // Skip closing quote
        }
    }
    else {
        // Path is not quoted
        pos = cmdLine.find(' ');
    }

    // If we found a space, extract everything after it
    if (pos != std::string::npos && pos < cmdLine.length() - 1) {
        return cmdLine.substr(pos + 1);
    }

    return ""; // No arguments found
}



// Also update the launch code to use the correct working directory
int main(int argc, char* argv[]) {
    // Define the patches to apply
    std::vector<PatchInfo> patches = {
        // Engine DLL patches
        {"engine.dll", "753cf30f10", 0, "eb"},          // brush entity backfaces
        {"engine.dll", "7e5244", 0, "eb"},              // world backfaces
        {"engine.dll", "753c498b4204", 0, "eb"},        // world backfaces

        // Client DLL patches
        {"client.dll", "4883ec480f1022", 0, "31c0c3"},  // c_frustumcull
        {"client.dll", "0fb68154", 0, "b001c3"},        // r_forcenovis [getter]

        // Shader DLL patches
        {"shaderapidx9.dll", "480f4ec1c7", 0, "90909090"},  // four hardware lights
        {"shaderapidx9.dll", "4833cce8????03004881c448", 0, "85c0750466b80400"},  // zero sized buffer
        {"shaderapidx9.dll", "4883ec084c", 0, "31c0c3"},    // shader constants

        // Material System DLL patches
        {"materialsystem.dll", "f77c24683bc10f4fc1488b8c24300100004833cce8??bb04004881c448010000", 0,
         "448b4424684585c0740341f7f839c80f4fc14881c448010000c3"}  // zero sized buffer protection
    };

    // Get path to gmod.exe in the win64/bin subdirectory
    std::string exeDir = GetExecutableDirectory();
    std::string gmodPath = exeDir + "bin\\win64\\gmod.exe";
    std::string gmodWorkingDir = exeDir + "bin\\win64\\";

    // Check if file exists
    std::ifstream file(gmodPath);
    if (!file.good()) {
        std::cout << "Error: Could not find gmod.exe at " << gmodPath << std::endl;
        std::cout << "Make sure this patcher is in the Garry's Mod root directory" << std::endl;
        std::cout << "Press Enter to exit...";
        std::cin.get();
        return 1;
    }

    // Get command line arguments to pass to gmod.exe
    std::string args = GetCommandLineArgs();
    std::string cmdLine = "\"" + gmodPath + "\"";
    if (!args.empty()) {
        cmdLine += " " + args;
    }

    std::cout << "Starting Garry's Mod with command: " << cmdLine << std::endl;
    std::cout << "Working directory: " << gmodWorkingDir << std::endl;

    // Prepare startup info
    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));

    // Create a modifiable copy of the command line
    char* cmdLineCopy = new char[cmdLine.length() + 1];
    strcpy_s(cmdLineCopy, cmdLine.length() + 1, cmdLine.c_str());

    // Start the process with command line args and the proper working directory
    if (!CreateProcessA(NULL, cmdLineCopy, NULL, NULL, FALSE, 0, NULL,
        gmodWorkingDir.c_str(), &si, &pi)) {
        delete[] cmdLineCopy;
        std::cout << "Failed to start gmod.exe. Error: " << GetLastError() << std::endl;
        std::cout << "Press Enter to exit...";
        std::cin.get();
        return 1;
    }

    delete[] cmdLineCopy;

    std::cout << "Garry's Mod started successfully. Process ID: " << pi.dwProcessId << std::endl;

    // Start the monitoring thread
    std::thread monitorThread(PatchMonitorThread, pi.dwProcessId, patches);

    // Wait for user to press Enter to exit
    std::cout << "Patches will be continuously applied." << std::endl;
    std::cout << "Press Enter to stop monitoring and exit..." << std::endl;
    std::cin.get();

    // Clean up
    std::cout << "Exiting..." << std::endl;
    monitorThread.detach(); // Let thread clean up on its own
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    return 0;
}
