Write-Host "Building Chitauri Android Universal Release APK (Flutter + 16KB Page Aligned Kotlin Services)..."
Push-Location "$PSScriptRoot\chitauri_flutter"
flutter build apk --release
if ($LASTEXITCODE -eq 0) {
    Pop-Location
    New-Item -ItemType Directory -Force -Path "$PSScriptRoot\dist" | Out-Null
    Copy-Item "$PSScriptRoot\chitauri_flutter\build\app\outputs\flutter-apk\app-release.apk" -Destination "$PSScriptRoot\dist\ChitauriAudio.apk" -Force
    Write-Host "Successfully generated and copied APK to .\dist\ChitauriAudio.apk"
} else {
    Pop-Location
    Write-Error "Flutter APK build failed with exit code $LASTEXITCODE"
}
