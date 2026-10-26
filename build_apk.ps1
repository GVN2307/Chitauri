$ndk_bin = "C:\Users\veera\AppData\Local\Android\Sdk\ndk\27.1.12297006\toolchains\llvm\prebuilt\windows-x86_64\bin"
$llvm_bin = "C:\Users\veera\AppData\Local\Microsoft\WinGet\Packages\MartinStorsjo.LLVM-MinGW.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\llvm-mingw-20260908-ucrt-x86_64\bin"
$env:PATH = "$ndk_bin;$llvm_bin;C:\Users\veera\.cargo\bin;$env:PATH"
$env:ANDROID_HOME = "C:\Users\veera\AppData\Local\Android\Sdk"
$env:NDK_HOME = "C:\Users\veera\AppData\Local\Android\Sdk\ndk\27.1.12297006"

$env:CC_aarch64_linux_android = "$ndk_bin\aarch64-linux-android34-clang.cmd"
$env:CXX_aarch64_linux_android = "$ndk_bin\aarch64-linux-android34-clang++.cmd"
$env:AR_aarch64_linux_android = "$ndk_bin\llvm-ar.exe"

$env:CC_x86_64_linux_android = "$ndk_bin\x86_64-linux-android34-clang.cmd"
$env:CXX_x86_64_linux_android = "$ndk_bin\x86_64-linux-android34-clang++.cmd"
$env:AR_x86_64_linux_android = "$ndk_bin\llvm-ar.exe"

$env:RUSTFLAGS = "-C link-arg=-Wl,-z,max-page-size=16384 -C link-arg=-lc++_static -C link-arg=-lc++abi"

Write-Host "Building Chitauri Android Universal APK (arm64-v8a + x86_64 with 16KB Page Alignment)..."
cargo-apk apk build --lib --release

if ($LASTEXITCODE -eq 0) {
    New-Item -ItemType Directory -Force -Path '.\dist' | Out-Null
    Copy-Item '.\target\release\apk\ChitauriAudio.apk' -Destination '.\dist\ChitauriAudio.apk' -Force
    Write-Host "Successfully generated and copied APK to .\dist\ChitauriAudio.apk"
}
