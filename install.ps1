# Chitauri Audio Suite - Windows Laptop & Desktop Installer
$ErrorActionPreference = "Stop"

$InstallDir = $PSScriptRoot
$ExePath = Join-Path $InstallDir "chitauri.exe"
$IcoPath = Join-Path $InstallDir "desktop_app\logo.ico"
if (-not (Test-Path $IcoPath)) {
    $IcoPath = Join-Path $InstallDir "assets\logo.ico"
}

if (-not (Test-Path $ExePath)) {
    Write-Error "chitauri.exe not found in $InstallDir"
    exit 1
}

Write-Host "Registering Chitauri Audio Suite in Windows Desktop and Start Menu..." -ForegroundColor Green

$WshShell = New-Object -ComObject WScript.Shell

# 1. Desktop Shortcut
$DesktopPath = [System.Environment]::GetFolderPath('Desktop')
$DesktopLnk = Join-Path $DesktopPath "Chitauri.lnk"
$Shortcut1 = $WshShell.CreateShortcut($DesktopLnk)
$Shortcut1.TargetPath = $ExePath
$Shortcut1.IconLocation = "$IcoPath,0"
$Shortcut1.Description = "Chitauri Desktop Audio Suite"
$Shortcut1.WorkingDirectory = $InstallDir
$Shortcut1.Save()

# 2. Start Menu / All Apps Shortcut
$StartMenuPath = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('ApplicationData'), 'Microsoft\Windows\Start Menu\Programs')
$StartLnk = Join-Path $StartMenuPath "Chitauri.lnk"
$Shortcut2 = $WshShell.CreateShortcut($StartLnk)
$Shortcut2.TargetPath = $ExePath
$Shortcut2.IconLocation = "$IcoPath,0"
$Shortcut2.Description = "Chitauri Desktop Audio Suite"
$Shortcut2.WorkingDirectory = $InstallDir
$Shortcut2.Save()

# 3. Windows App Paths Registration (Allows Win+R -> chitauri)
try {
    $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chitauri.exe"
    if (-not (Test-Path $RegKey)) {
        New-Item -Path $RegKey -Force | Out-Null
    }
    Set-ItemProperty -Path $RegKey -Name "(Default)" -Value $ExePath
    Set-ItemProperty -Path $RegKey -Name "Path" -Value $InstallDir
} catch {
    Write-Warning "Registry registration note: $_"
}

Write-Host "Chitauri Audio Suite has been successfully registered on this laptop." -ForegroundColor Cyan
Write-Host " - Desktop Shortcut: $DesktopLnk"
Write-Host " - Start Menu App: $StartLnk"
Write-Host " - You can now search for 'Chitauri' in Windows Start Menu or press Win+R and type 'chitauri'."
