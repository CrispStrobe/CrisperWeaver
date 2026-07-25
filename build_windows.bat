@echo off
REM build_windows.bat
REM
REM Convenience wrapper for scripts\build_windows.ps1 — lets users
REM with no PowerShell muscle memory run the full Windows build flow
REM by double-clicking or via cmd.exe.
REM
REM Usage:
REM   build_windows.bat                        REM = release build
REM   build_windows.bat debug
REM   build_windows.bat release -RebuildCmake
REM   build_windows.bat release -P100
REM
REM Prefers PowerShell 7+ (pwsh.exe) when available, falls back to
REM Windows PowerShell 5.1 (powershell.exe).

setlocal

set "SCRIPT=%~dp0scripts\build_windows.ps1"

where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
)

exit /b %errorlevel%
