# Chitauri Project - Developer Instructions

This document provides technical instructions, coding standards, and build procedures for developing and maintaining the **Chitauri Audio Suite**.

---

## 1. Core Architectural Directives

1. **Zero External Backend Servers:** All operations (YouTube search, extraction, download, ID3 metadata embedding, storage, and audio playback) must execute directly on the client machine. No intermediary proxy servers, scrapers, or third-party cloud backends are permitted.
2. **Mandatory Storage Isolation (`.nomedia`):** The application must generate and maintain its media storage directory (`/Music/ChitauriMusic/` on Android, `%USERPROFILE%\Music\ChitauriMusic\` on Windows) and atomically guarantee the existence of a zero-byte `.nomedia` sentinel file. This prevents operating system media indexers (`MediaScanner`, Windows Media Player, Groove) from harvesting application tracks, while allowing users full access via native file managers.
3. **Decoupled Architecture Across Targets:**
   - `search`: YouTube search and live trending feed with card art, channel tags, and durations.
   - `library`: Local track scanner, offline playback, file removal, and `.nomedia` vault inspector.
   - `player`: Dual-queue state machine, unbiased Fisher-Yates shuffle with current track pinned, 3-state repeat, and turntable player with spectrum visualizer.
4. **Deterministic Concurrency:** Network streaming and disk I/O must execute asynchronously without blocking the user interface (Tokio channels in Rust, background worker threads in Python desktop, Foreground Services with `PARTIAL_WAKE_LOCK` in Android).

---

## 2. Repository Layout & Target Mapping

```
Chitauri/
├── ARCHITECTURE.md                     # Comprehensive system architecture specification
├── README.md                           # Main overview, badges, and quick start
├── AGENTS.md                           # Multi-agent role governance
├── INSTRUCTIONS.md                     # Developer directives and compilation guide
├── SECURITY.md                         # Security posture and storage isolation policy
├── SKILLS.md                           # Competency matrix and skill verification standards
├── LICENSE                             # GNU General Public License v3.0
├── chitauri.exe                        # Windows Desktop Executable (19.7 MB standalone)
├── install.bat                         # Windows one-click desktop & start menu installer
├── install.ps1                         # PowerShell desktop & start menu installer
├── desktop_app/                        # Windows Desktop Application Codebase
│   ├── app.py                          # Localhost REST server, extraction pipeline, & shortcuts
│   ├── index.html                      # Widescreen desktop UI, turntable studio, & visualizer
│   ├── logo.png                        # Official branding logo asset
│   └── logo.ico                        # Multi-resolution Windows application icon
├── chitauri_flutter/                   # Android Mobile Application Codebase
│   ├── android/                        # Android native platform project (Kotlin services)
│   └── lib/                            # Flutter Dart codebase (models, services, views)
├── src/                                # Native Rust Algorithmic Reference Core
│   ├── main.rs                         # Rust entrypoint
│   ├── app.rs                          # eframe state loop
│   ├── downloader.rs                   # Async chunk downloader
│   ├── innertube.rs                    # InnerTube client
│   ├── models.rs                       # Shared Rust data models
│   ├── player.rs                       # Rodio audio sink & dual-queue machine
│   ├── storage.rs                      # .nomedia sentinel & local storage engine
│   └── ui/                             # egui modular UI components
└── tests/                              # Rust Integration & Unit Tests
    ├── player_state_test.rs            # Shuffle, repeat, and queue unit tests
    └── storage_isolation_test.rs       # .nomedia sentinel enforcement tests
```

---

## 3. Strict Coding Standards

### 3.1 Memory Safety & Path Sanitization
- Forbid `unsafe` blocks in Rust code unless approved with safety invariant comments.
- Sanitize all track titles before writing to disk by replacing illegal characters (`/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) and stripping directory traversal tokens (`../`).
- Canonicalize all file paths before deletion or writing to ensure operations remain strictly within `ChitauriMusic/`.

### 3.2 Queue Invariance & Shuffle Logic
- When shuffle mode is toggled, the currently playing track must never be interrupted.
- `shuffle()` must pin the actively playing track to index `0` and randomize the remaining items using the unbiased Fisher-Yates algorithm.
- Disabling shuffle must restore `original_queue` instantly without interrupting playback.

### 3.3 Repeat Mode State Transitions
- `RepeatMode::Off`: Cease playback when the queue reaches the final track.
- `RepeatMode::All`: Wrap `current_index` back to `0` when queue finishes.
- `RepeatMode::One`: Loop the active track indefinitely (`currentTime = 0`).

---

## 4. Build, Run & Test Procedures

### 4.1 Windows Desktop Suite (`chitauri.exe`)

#### Running Pre-Built Binary
```powershell
.\chitauri.exe
```

#### Installing on Windows Laptop / Desktop
```powershell
.\install.bat
# Or via PowerShell
.\install.ps1
```
This registers shortcuts at `%USERPROFILE%\Desktop\Chitauri.lnk` and `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Chitauri.lnk`.

#### Running from Source
```powershell
python -m venv app_venv
.\app_venv\Scripts\activate
pip install pywebview pyinstaller yt-dlp pillow
python desktop_app\app.py
```

#### Compiling Standalone Executable with PyInstaller
```powershell
.\app_venv\Scripts\pyinstaller.exe --noconfirm --clean --onefile --windowed `
  --name "chitauri" `
  --icon "desktop_app\logo.ico" `
  --add-data "desktop_app\index.html;desktop_app" `
  --add-data "desktop_app\index.html;." `
  --add-data "desktop_app\logo.png;." `
  --add-data "desktop_app\logo.ico;." `
  desktop_app\app.py
```

---

### 4.2 Android Mobile Client (`com.chitauri.audio`)

#### Compiling Release APK
```powershell
powershell -ExecutionPolicy Bypass -File .\build_apk.ps1
```
Or build directly using the Flutter CLI:
```powershell
Set-Location chitauri_flutter
flutter build apk --release
```

#### Installing via ADB
```powershell
adb install -r chitauri_flutter\build\app\outputs\flutter-apk\app-release.apk
```

---

### 4.3 Native Rust Reference Core (`src/`)

#### Running Tests
```powershell
cargo test
```

#### Running Prototype Canvas
```powershell
cargo run
```

#### Compiling Optimized Release Binary
```powershell
cargo build --release
```
