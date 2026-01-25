#!/usr/bin/env bash

# Remote clean script for Garry's Mod RTX Remixed
# Cleans build artifacts using MSBuild on Windows VM over SSH

set -e

# SSH connection details
SSH_HOST="cr@localhost"
SSH_PORT="2222"
WINDOWS_REPO_PATH="C:\Users\cr\proj\garrys-mod-rtx-remixed"
SOLUTION_FILE="RTXFixesBinary.sln"

echo "Starting remote clean on Windows VM..."
echo "Repository path: $WINDOWS_REPO_PATH"
echo "Solution: $SOLUTION_FILE"
echo ""

# Execute MSBuild clean on the Windows VM
ssh -p "$SSH_PORT" "$SSH_HOST" -t "powershell -ExecutionPolicy Bypass -Command \"Set-Location '$WINDOWS_REPO_PATH'; & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe' '$SOLUTION_FILE' /t:Clean /p:Configuration=Debug /p:Platform=x64; & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe' '$SOLUTION_FILE' /t:Clean /p:Configuration=Release /p:Platform=x64; & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Current\Bin\MSBuild.exe' '$SOLUTION_FILE' /t:Clean /p:Configuration=ReleaseWithSymbols /p:Platform=x64; Write-Host 'Clean completed for all configurations'\""

SSH_EXIT_CODE=$?

if [ $SSH_EXIT_CODE -eq 0 ]; then
    echo ""
    echo "Remote clean completed successfully!"
else
    echo ""
    echo "Remote clean failed with exit code: $SSH_EXIT_CODE"
    exit $SSH_EXIT_CODE
fi
