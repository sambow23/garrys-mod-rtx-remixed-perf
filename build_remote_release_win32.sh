#!/usr/bin/env bash

# Remote build script for Garry's Mod RTX Remixed (Release Win32)
# Builds RTXFixesBinary.sln using MSBuild on Windows VM over SSH

set -e

# SSH connection details
SSH_HOST="cr@localhost"
SSH_PORT="2222"
WINDOWS_REPO_PATH="C:\Users\cr\proj\garrys-mod-rtx-remixed"
SOLUTION_FILE="RTXFixesBinary.sln"
CONFIGURATION="Release"
PLATFORM="Win32"

echo "Starting remote Release|Win32 build on Windows VM..."
echo "Repository path: $WINDOWS_REPO_PATH"
echo "Solution: $SOLUTION_FILE"
echo "Configuration: $CONFIGURATION|$PLATFORM"
echo ""

# Execute MSBuild on the Windows VM
ssh -p "$SSH_PORT" "$SSH_HOST" -t "powershell -ExecutionPolicy Bypass -Command \"Set-Location '$WINDOWS_REPO_PATH'; & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe' '$SOLUTION_FILE' /p:Configuration=$CONFIGURATION /p:Platform=$PLATFORM /m /v:minimal\""

SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Remote build completed successfully!"
    echo "Output DLL: $WINDOWS_REPO_PATH\\x86\\$CONFIGURATION\\gmcl_RTXFixesBinary_win32.dll"
else
    echo ""
    echo "Remote build failed with exit code: $SSH_EXIT_CODE"
    exit $SSH_EXIT_CODE
fi
