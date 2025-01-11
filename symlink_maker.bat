@echo off
echo Enter the full path to your gmod install (where gmod.exe is) (no trailing backslash)
echo Make sure you've built the debug build atleast once before running this
set /p gmodpath="Game Path: "
mklink /j %gmodpath%\garrysmod\addons\rtxfixes2 .\addon
echo Addon Linked.
mklink %gmodpath%\garrysmod\lua\bin\gmcl_RTXFixesBinary_win64.dll .\x86_64\Debug\gmcl_RTXFixesBinary_win64.dll
echo Binary Linked.
pause
