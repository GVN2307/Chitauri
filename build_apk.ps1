if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    if (Test-Path "C:\Projects\flutter\bin\flutter.bat") {
        $env:PATH = "C:\Projects\flutter\bin;$env:PATH"
    }
}
Write-Host "Building Chitauri Android Split-per-ABI Release APKs (arm64-v8a, armeabi-v7a, x86_64)..."
Push-Location "$PSScriptRoot\chitauri_flutter"
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -eq 0) {
    Pop-Location
    New-Item -ItemType Directory -Force -Path "$PSScriptRoot\dist" | Out-Null
    $apkDir = "$PSScriptRoot\chitauri_flutter\build\app\outputs\flutter-apk"
    
    # Copy split APKs with clean human-readable names
    if (Test-Path "$apkDir\app-arm64-v8a-release.apk") {
        Copy-Item "$apkDir\app-arm64-v8a-release.apk" -Destination "$PSScriptRoot\dist\ChitauriAudio-arm64-v8a.apk" -Force
        Copy-Item "$apkDir\app-arm64-v8a-release.apk" -Destination "$PSScriptRoot\dist\ChitauriAudio.apk" -Force
    }
    if (Test-Path "$apkDir\app-armeabi-v7a-release.apk") {
        Copy-Item "$apkDir\app-armeabi-v7a-release.apk" -Destination "$PSScriptRoot\dist\ChitauriAudio-armeabi-v7a.apk" -Force
    }
    if (Test-Path "$apkDir\app-x86_64-release.apk") {
        Copy-Item "$apkDir\app-x86_64-release.apk" -Destination "$PSScriptRoot\dist\ChitauriAudio-x86_64.apk" -Force
    }
    
    Write-Host "Successfully generated and copied Split APKs to .\dist\:"
    Get-ChildItem -Path "$PSScriptRoot\dist\*.apk" | Select-Object Name, @{N="Size (MB)"; E={"{0:N1} MB" -f ($_.Length / 1MB)}} | Format-Table -AutoSize
} else {
    Pop-Location
    Write-Error "Flutter APK build failed with exit code $LASTEXITCODE"
}
