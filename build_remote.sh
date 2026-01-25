#!/usr/bin/env bash

# Remote build script for Garry's Mod RTX Remixed (Custom)
# Builds RTXFixesBinary.sln with custom configuration on Windows VM over SSH

set -e

# SSH connection details
SSH_HOST="cr@localhost"
SSH_PORT="2222"
WINDOWS_REPO_PATH="C:\Users\cr\proj\garrys-mod-rtx-remixed"
SOLUTION_FILE="RTXFixesBinary.sln"

# Default values
CONFIGURATION="${1:-Release}"
PLATFORM="${2:-x64}"

# Validate configuration
case "$CONFIGURATION" in
    Debug|Release|ReleaseWithSymbols)
        ;;
    *)
        echo "Error: Invalid configuration '$CONFIGURATION'"
        echo ""
        echo "Usage: $0 [Configuration] [Platform]"
        echo ""
        echo "Valid Configurations:"
        echo "  Debug                - Debug build with full debugging information"
        echo "  Release              - Optimized release build"
        echo "  ReleaseWithSymbols   - Optimized build with debugging symbols"
        echo ""
        echo "Valid Platforms:"
        echo "  x64                  - 64-bit build (default)"
        echo "  Win32                - 32-bit build"
        echo ""
        echo "Examples:"
        echo "  $0 Release x64"
        echo "  $0 Debug Win32"
        echo "  $0 ReleaseWithSymbols x64"
        echo ""
        echo "For common builds, use:"
        echo "  ./build_remote_release.sh       - Release x64"
        echo "  ./build_remote_release_win32.sh - Release Win32"
        echo "  ./build_remote_debug.sh         - Debug x64"
        exit 1
        ;;
esac

# Validate platform
case "$PLATFORM" in
    x64|Win32)
        ;;
    *)
        echo "Error: Invalid platform '$PLATFORM'"
        echo "Valid platforms: x64, Win32"
        exit 1
        ;;
esac

echo "Starting remote $CONFIGURATION|$PLATFORM build on Windows VM..."
echo "Repository path: $WINDOWS_REPO_PATH"
echo "Solution: $SOLUTION_FILE"
echo ""

# Execute MSBuild on the Windows VM
ssh -p "$SSH_PORT" "$SSH_HOST" -t "powershell -ExecutionPolicy Bypass -Command \"Set-Location '$WINDOWS_REPO_PATH'; & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe' '$SOLUTION_FILE' /p:Configuration=$CONFIGURATION /p:Platform=$PLATFORM /m /v:minimal\""

SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Remote build completed successfully!"
    
    # Determine output path based on platform
    if [ "$PLATFORM" = "x64" ]; then
        OUTPUT_DIR="x86_64"
        OUTPUT_NAME="gmcl_RTXFixesBinary_win64.dll"
    else
        OUTPUT_DIR="x86"
        OUTPUT_NAME="gmcl_RTXFixesBinary_win32.dll"
    fi
    
    echo "Output DLL: $WINDOWS_REPO_PATH\\$OUTPUT_DIR\\$CONFIGURATION\\$OUTPUT_NAME"
else
    echo ""
    echo "Remote build failed with exit code: $SSH_EXIT_CODE"
    exit $SSH_EXIT_CODE
fi
