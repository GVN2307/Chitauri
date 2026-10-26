@echo off
setlocal enabledelayedexpansion
title Chitauri Audio Suite Installer

echo ===================================================
echo Chitauri Audio Suite - Desktop Installation
echo ===================================================
echo.

set "INSTALL_DIR=%~dp0"
set "EXE_PATH=%INSTALL_DIR%chitauri.exe"
set "ICO_PATH=%INSTALL_DIR%desktop_app\logo.ico"

if not exist "%ICO_PATH%" (
    set "ICO_PATH=%INSTALL_DIR%assets\logo.ico"
)

if not exist "%EXE_PATH%" (
    echo [ERROR] chitauri.exe not found in %INSTALL_DIR%
    pause
    exit /b 1
)

echo Registering Chitauri in Windows Start Menu and Desktop...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ws = New-Object -ComObject WScript.Shell; " ^
    "$desktopLnk = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('Desktop'), 'Chitauri.lnk'); " ^
    "$s1 = $ws.CreateShortcut($desktopLnk); " ^
    "$s1.TargetPath = '%EXE_PATH%'; " ^
    "$s1.IconLocation = '%ICO_PATH%,0'; " ^
    "$s1.Description = 'Chitauri Desktop Audio Suite'; " ^
    "$s1.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$s1.Save(); " ^
    "$startDir = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('ApplicationData'), 'Microsoft\Windows\Start Menu\Programs'); " ^
    "$startLnk = [System.IO.Path]::Combine($startDir, 'Chitauri.lnk'); " ^
    "$s2 = $ws.CreateShortcut($startLnk); " ^
    "$s2.TargetPath = '%EXE_PATH%'; " ^
    "$s2.IconLocation = '%ICO_PATH%,0'; " ^
    "$s2.Description = 'Chitauri Desktop Audio Suite'; " ^
    "$s2.WorkingDirectory = '%INSTALL_DIR%'; " ^
    "$s2.Save();"

echo Registering App Path in Windows Registry...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\chitauri.exe" /ve /t REG_SZ /d "%EXE_PATH%" /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\chitauri.exe" /v Path /t REG_SZ /d "%INSTALL_DIR%" /f >nul 2>&1

echo.
echo ===================================================
echo Installation Complete!
echo - Desktop Shortcut created: Chitauri
echo - Start Menu App added: Chitauri
echo - Run command available: Press Win+R and type 'chitauri'
echo ===================================================
echo.
