# Chitauri Audio Suite

<p align="center">
  <img alt="Project" src="https://img.shields.io/badge/project-Chitauri%20Audio-10b981?style=for-the-badge">
  <img alt="Status" src="https://img.shields.io/badge/status-App%20stage-orange?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=for-the-badge">
  <img alt="Rust" src="https://img.shields.io/badge/language-Rust%201.80+-DEA584?style=for-the-badge">
  <img alt="Flutter" src="https://img.shields.io/badge/framework-Flutter%203.x-02569B?style=for-the-badge">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-lightgrey?style=for-the-badge">
  <img alt="Architecture" src="https://img.shields.io/badge/architecture-Client--Side%20Zero--Backend-purple?style=for-the-badge">
</p>

---

## Executive Summary

Chitauri is an entirely client-side, privacy-focused audio suite engineered for Android and Windows desktop environments. It delivers search, extraction, and local playback of high-fidelity audio streams directly from network endpoints without relying on intermediate proxy servers, cloud storage backends, or third-party web scrapers.

The system features storage isolation via the `.nomedia` protocol, preventing operating system media crawlers from indexing downloaded tracks, while keeping files organized and directly manageable through device file managers.

The suite provides two deployment targets:
1. **Android Client (`com.chitauri.audio`)**: A high-performance Flutter mobile application backed by Kotlin foreground services, hardware-accelerated audio metadata extraction, and native stream resolution.
2. **Desktop Application (`chitauri.exe`)**: A pure Rust standalone binary built with `eframe`, `egui`, `tokio`, and `rodio`, delivering zero-dependency native playback and desktop audio management.

---

## Complete System Architecture

### Architectural Topology

```
+---------------------------------------------------------------------------------------+
|                               PRESENTATION LAYER                                      |
|                                                                                       |
|   +------------------------------------+   +--------------------------------------+   |
|   | Android Client (Flutter UI)        |   | Desktop Client (Rust egui/eframe)    |   |
|   | - Miniature Search & Filter Feed   |   | - Mobile Viewport Simulation         |   |
|   | - Vinyl Turntable Player Sheet     |   | - Low-Latency Immediate Mode Canvas  |   |
|   | - Offline Library & Playlists      |   | - Integrated Audio Waveform & State  |   |
|   | - Storage Allocation Monitor       |   | - Responsive Track Management        |   |
|   +-----------------+------------------+   +-------------------+------------------+   |
+---------------------|------------------------------------------|----------------------+
                      | Platform Channels                        | Tokio MPSC Channels
                      v                                          v
+---------------------------------------------------------------------------------------+
|                             CONTROL & SERVICE LAYER                                   |
|                                                                                       |
|   +------------------------------------+   +--------------------------------------+   |
|   | Android Platform Services (Kotlin) |   | Asynchronous Rust Core (Tokio)       |   |
|   | - ChitauriDownloadService          |   | - Multi-Threaded Task Coordinator    |   |
|   | - ChitauriPlaybackService          |   | - Dual-Queue State Machine           |   |
|   | - Hardware MediaMetadataRetriever  |   | - Fisher-Yates Pinned Shuffle        |   |
|   | - Notification & MediaSession API  |   | - Three-State Repeat Machine         |   |
|   +-----------------+------------------+   +-------------------+------------------+   |
+---------------------|------------------------------------------|----------------------+
                      | InnerTube Engine / QuickJS               | Reqwest HTTP Client
                      v                                          v
+---------------------------------------------------------------------------------------+
|                          EXTRACTION & STREAMING LAYER                                 |
|                                                                                       |
|   +-------------------------------------------------------------------------------+   |
|   | Direct Client-Side Stream Resolver                                            |   |
|   | - Anonymous Android Client Context Emulation                                  |   |
|   | - Multi-Client Fallback (Android -> Web -> TV)                                |   |
|   | - QuickJS JavaScript Signature Deciphering Engine                             |   |
|   | - Adaptive Audio Stream Extraction (AAC itag 140 / Opus itag 251)             |   |
|   | - Chunked Asynchronous Downloader with Dynamic Progress Telemetry             |   |
|   +---------------------------------------+---------------------------------------+   |
+-------------------------------------------|-------------------------------------------+
                                            v
+---------------------------------------------------------------------------------------+
|                           AUDIO ENGINE & HARDWARE OUTPUT                              |
|                                                                                       |
|   +------------------------------------+   +--------------------------------------+   |
|   | Android Audio Sink                 |   | Desktop Audio Sink                   |   |
|   | - Android AAudio / Oboe Native API |   | - Rodio Audio Pipeline               |   |
|   | - Hardware DSP Offload             |   | - Symphonia Hardware Audio Decoders  |   |
|   | - Low-Power Sleep-State Playback   |   | - CPAL Low-Latency Audio Stream      |   |
|   +------------------------------------+   +--------------------------------------+   |
+-------------------------------------------+-------------------------------------------+
                                            |
                                            v
+---------------------------------------------------------------------------------------+
|                           PERSISTENCE & STORAGE ISOLATION                             |
|                                                                                       |
|   +-------------------------------------------------------------------------------+   |
|   | Local Media Isolation Directory: /Music/ChitauriMusic/                        |   |
|   |                                                                               |   |
|   | |-- .nomedia             (Atomic sentinel preventing MediaScanner indexing)   |   |
|   | |-- tracks_catalog.json  (Synchronous metadata catalog and playback cache)    |   |
|   | |-- playlists.json       (Custom playlist structures and track ordering)      |   |
|   | |-- thumbnails/          (Locally cached album art and artwork assets)        |   |
|   | +-- *.m4a / *.mp3        (ID3v2 / MP4 atom tagged tracks, open for File Mgr)  |   |
|   +-------------------------------------------------------------------------------+   |
+---------------------------------------------------------------------------------------+
```

---

## End-to-End Operational Pipeline: Song Selection to Playback

The Chitauri audio pipeline operates entirely on the client device. Below is the technical breakdown of each phase from song search to offline playback.

```
[ User Search Input ]
         |
         v
[ Phase 1: InnerTube Query & Response Parsing ]
         |
         v
[ Phase 2: Selection & Duplicate Verification ]
         |
         v
[ Phase 3: Adaptive Stream Resolution & Deciphering ]
         |
         v
[ Phase 4: Chunked Download & Foreground Service ]
         |
         v
[ Phase 5: Hardware Metadata Extraction & ID3 Tagging ]
         |
         v
[ Phase 6: Storage Isolation (.nomedia) & Catalog Sync ]
         |
         v
[ Phase 7: Deterministic Playback & Queue Transitions ]
```

### Phase 1: InnerTube Query and Response Parsing
1. **Query Construction:** When the user enters a search string, the client forms an HTTP POST request targeting `https://www.youtube.com/youtubei/v1/search`.
2. **Context Masking:** The request payload uses an anonymous client context profile (`ANDROID_MUSIC` or `WEB`), including client version, system architecture, and locale headers.
3. **Stream Suppression:** Video playback manifests are discarded at this stage. Only metadata nodes (`itemSectionRenderer`, `videoRenderer`, `compactVideoRenderer`) are parsed.
4. **Data Normalization:** Extracted attributes (Video ID, Title, Artist/Channel, Duration Estimate, Thumbnail URL) are mapped into immutable track structs and rendered in the interface.

### Phase 2: Song Selection and Duplicate Verification
1. **User Interaction:** The user taps a song card or download trigger.
2. **Catalog Collision Check:** The application queries the local storage registry (`tracks_catalog.json`) using both the unique Video ID and sanitized title string.
3. **Conflict Handling:**
   - If the track is unrecorded, download starts immediately.
   - If a file with an identical title exists, the user is presented with a resolution dialog. If confirmed, an incrementing index (e.g., `Title (2).m4a`) is applied.
   - Placeholder and transitory states (e.g., "fetching title") are filtered to prevent false duplicate collisions.

### Phase 3: Adaptive Stream Resolution and Signature Deciphering
1. **Player Endpoint Resolution:** The client dispatches a request to `youtubei/v1/player` with the targeted Video ID.
2. **Stream Filtering:** The resolver parses `streamingData.adaptiveFormats` to identify optimal audio-only streams:
   - AAC (`audio/mp4`, itag 140, 128-160 kbps).
   - Opus (`audio/webm`, itag 251, 160 kbps).
3. **Deciphering Pipeline:** If the audio stream URL contains protected signature cipher tokens:
   - The cipher string is extracted (`s`, `sp`, `url`).
   - The embedded QuickJS runtime executes the signature unscrambling algorithm dynamically.
4. **Client Fallback:** If an endpoint returns HTTP 403 or bot challenges, the resolver falls back across client personas in sequence: `android` -> `web` -> `tv`.

### Phase 4: Chunked Download and Foreground Service Execution
1. **Service Promotion:** On Android, a foreground service (`ChitauriDownloadService`) is promoted with `DATA_SYNC` and `MEDIA_PLAYBACK` types, acquiring a CPU `PARTIAL_WAKE_LOCK`. This guarantees downloads complete even when the application is minimized or the screen is off.
2. **Byte Stream Buffering:** The client streams binary chunks through an HTTP range-request loop, preventing excessive RAM consumption.
3. **Telemetry Streaming:** Download progress (0% to 85%) streams in real time via thread-safe channels (`tokio::sync::mpsc` on desktop, platform MethodChannels on Android) to update:
   - In-app progress bars.
   - Pinned system notification drawer with cancellation actions.

### Phase 5: Hardware Metadata Extraction and Audio Tagging
1. **Hardware Duration Verification:** Relying on estimated network durations often causes time-scrubber drift. After the audio file finishes downloading, the native bridge initializes the Android `MediaMetadataRetriever` (or Symphonia hardware decoder on desktop):
   - The raw audio container is parsed at the hardware level.
   - Accurate duration in milliseconds is extracted and written to the metadata record.
2. **Artwork and Container Tagging:**
   - The high-resolution thumbnail is downloaded, resized, and cached locally.
   - Audio metadata tags (ID3v2 for MP3, MP4 user atoms for M4A) are injected into the file header: Title, Contributing Artist, Album Name, Track Duration, and Embedded Cover Art.

### Phase 6: Storage Isolation and Sentinel Enforcement
1. **Dedicated Directory:** All tracks are stored in `/Music/ChitauriMusic/` on Android, or the local user music folder on Windows.
2. **The `.nomedia` Protocol:**
   - An empty sentinel file named `.nomedia` is created within `ChitauriMusic/`.
   - The operating system `MediaScanner` crawler encounters the sentinel and excludes the directory from the global `MediaStore` index.
   - **Result:** Third-party players (Spotify, VLC, Samsung Music, Apple Music) cannot index or display Chitauri tracks.
   - **File Manager Access:** Native and third-party file managers navigate the raw filesystem directly, allowing users full visibility, backup, and manual transfer of their audio files.
3. **Catalog Synchronization:** The physical file is committed, and `tracks_catalog.json` is updated. Event buses notify the Library view, Profile statistics counters, and storage meters without requiring an application restart.

### Phase 7: Deterministic Playback and State Management
1. **Audio Hardware Offloading:** On Android, playback streams through `AAudio` or `Oboe` directly to the system Digital Signal Processor (DSP), minimizing CPU core wakeups. On Windows, audio buffers are processed by `rodio` via low-latency WASAPI/CPAL streams.
2. **Dual-Queue State Invariant:**
   - `original_queue`: Preserves the user's sequential playlist order.
   - `playback_queue`: Holds the active playback sequence.
3. **Fisher-Yates Shuffle with Current Track Pinning:**
   - When shuffle is activated, the currently playing track is pinned at index `0`, and all remaining songs are shuffled using the unbiased Fisher-Yates algorithm.
   - Disabling shuffle restores `original_queue` instantly without interrupting the active song.
4. **Three-State Repeat State Machine:**
   - `RepeatMode::Off`: Playback ceases when the queue concludes.
   - `RepeatMode::All`: The queue restarts from index `0` upon reaching the end.
   - `RepeatMode::One`: The current track repeats indefinitely.
5. **Persistent Notification Controls:** On Android, media playback notifications are registered with non-dismissible flags (`FLAG_ONGOING_EVENT`, `FLAG_NO_CLEAR`) and synced with Android `MediaSessionCompat` for lock screen and Bluetooth AVRCP controls.

---

## Desktop Application (`chitauri.exe`)

The desktop client is a standalone Windows executable engineered to provide identical visual design, audio features, and operational workflows as the Android mobile client.

### Executable Information
- **File Name:** `chitauri.exe`
- **Location:** Repository root (`./chitauri.exe`)
- **Binary Size:** ~12.9 MB (Standalone single-file executable)
- **GUI Engine:** Microsoft Edge Chromium WebView2 Runtime (Hardware Accelerated 60 FPS)
- **Audio Subsystem:** HTML5 Audio Engine with local HTTP 206 Partial Content range seeking
- **Backend Extractor:** Integrated yt-dlp & FFmpeg audio pipeline (100% reliable YouTube search & download)
- **Storage Directory:** `%USERPROFILE%\Music\ChitauriMusic\` protected by `.nomedia` sentinel

### Key Features of the Windows Desktop Application
1. **Search & One-Tap Grab:** Instantaneous YouTube search with high-resolution thumbnails, channel titles, durations, and quick filter chips.
2. **Real Audio Extraction:** Downloads genuine MP3 audio streams at highest bitrate with embedded artwork and ID3 metadata tags.
3. **Duplicate Resolution:** Automatically detects existing tracks and prompts whether to skip or create an indexed duplicate.
4. **Offline Library Management:** Real-time track catalog, duration tracking, instant playback, and disk removal.
5. **Interactive Vinyl Turntable Player:** Smooth rotating vinyl disc synchronized to playback state, turntable needle, time scrubber, volume bar, Fisher-Yates shuffle (current song pinned), and 3-state repeat mode.
6. **Device & Storage Profile:** Live storage tracking (total tracks and megabytes saved) and direct shortcut to open the isolated music directory in Windows File Explorer.

### Running the Desktop Application
To launch the pre-built desktop application directly on Windows:
```powershell
.\chitauri.exe
```

To run from source:
```powershell
python -m venv env
.\env\Scripts\activate
pip install pywebview pyinstaller
python desktop_app\app.py
```

---

## Android Mobile Application (`com.chitauri.audio`)

### Build Specifications
- **Package Name:** `com.chitauri.audio`
- **Minimum SDK:** Android 8.0 (API Level 26)
- **Target SDK:** Android 14+ (API Level 34, fully compatible with Android 15 & 16)
- **Memory Page Alignment:** 16 KB compliant (`0x4000`) for Android 15/16 64-bit architectures
- **ABIs Supported:** `arm64-v8a`, `armeabi-v7a`, `x86_64`

### Compiling the Release APK
```powershell
powershell -ExecutionPolicy Bypass -File .\build_apk.ps1
```
Or build via the Flutter CLI:
```powershell
Set-Location chitauri_flutter
flutter build apk --release
```

---

## Repository Structure

```
Chitauri/
|-- .cargo/
|   +-- config.toml                     # Cargo build flags and linker options
|-- .gitignore                          # Build artifact and secret exclusions
|-- AGENTS.md                           # Multi-agent architectural governance
|-- Cargo.lock                          # Locked dependency tree for Rust
|-- Cargo.toml                          # Pure Rust workspace configuration
|-- INSTRUCTIONS.md                     # Engineering directives and coding standards
|-- LICENSE                             # GNU General Public License v3.0
|-- README.md                           # Technical documentation and architecture
|-- SECURITY.md                         # Security posture and storage isolation policy
|-- SKILLS.md                           # Technical skills matrix and verification
|-- assets/
|   +-- logo.png                        # Application branding logo
|-- build_apk.ps1                       # Android APK compilation automation script
|-- chitauri.exe                        # Standalone Windows desktop application (12.9 MB)
|-- desktop_app/                        # Windows Desktop Application source
|   |-- app.py                          # Desktop controller & extraction bridge
|   +-- index.html                      # Desktop UI & interactive vinyl player
|-- chitauri_flutter/                   # Android Mobile Application codebase
|   |-- android/
|   |   |-- app/
|   |   |   |-- src/main/AndroidManifest.xml
|   |   |   +-- src/main/kotlin/com/chitauri/audio/
|   |   |       |-- ChitauriDownloadService.kt  # Background download service
|   |   |       |-- ChitauriPlaybackService.kt  # Notification & playback service
|   |   |       +-- MainActivity.kt             # Hardware retriever & method channels
|   |   +-- build.gradle
|   |-- lib/
|   |   |-- main.dart                           # Flutter initialization & navigation
|   |   |-- models/track.dart                   # Data definitions for audio tracks
|   |   |-- services/
|   |   |   |-- audio_player_service.dart       # State machine & queue coordinator
|   |   |   |-- storage_service.dart            # .nomedia protocol & catalog manager
|   |   |   +-- youtube_service.dart            # InnerTube resolver & stream parser
|   |   |-- views/
|   |   |   |-- library_view.dart               # Offline track library & playlists
|   |   |   |-- profile_view.dart               # Storage metrics & track count view
|   |   |   |-- queue_view.dart                 # Active playback queue view
|   |   |   |-- youtube_search_view.dart        # Search interface & stream trigger
|   |   |   +-- youtube_webview.dart            # Feed parser & duplicate detection
|   |   +-- widgets/
|   |       |-- mini_player.dart                # Docked persistent bottom player
|   |       +-- vinyl_player_sheet.dart         # Fullscreen turntable player sheet
|   +-- pubspec.yaml
|-- res/                                # Android launcher icon mipmaps
|-- src/                                # Pure Rust Desktop Core
|   |-- app.rs                          # eframe GUI state loop
|   |-- downloader.rs                   # Chunked network download pipeline
|   |-- innertube.rs                    # InnerTube search and player protocol
|   |-- lib.rs                          # Library exports
|   |-- main.rs                         # Desktop application entrypoint
|   |-- models.rs                       # Shared data structs and event enums
|   |-- player.rs                       # Rodio audio sink & dual-queue machine
|   |-- storage.rs                      # .nomedia sentinel & local storage engine
|   +-- ui/                             # Desktop egui modular interface components
+-- tests/
    |-- player_state_test.rs            # Shuffle, repeat, and queue unit tests
    +-- storage_isolation_test.rs       # .nomedia sentinel enforcement tests
```

---

## Technical Comparison Matrix

| Architectural Metric | Chitauri Audio Suite | Typical Streaming Clients | Typical Electron/PWA Wrappers |
| :--- | :--- | :--- | :--- |
| **Backend Dependency** | **Zero (Client-side direct)** | Proprietary cloud infrastructure | Intermediate proxy servers |
| **Storage Isolation** | **Strict (`.nomedia` protocol)** | Mixed in system media storage | Inaccessible or unmanaged |
| **Video Decoding Overhead** | **0% (Pure audio streams)** | Full video rendering pipeline | Chromium DOM video rendering |
| **Memory Consumption** | **~18 MB (Rust) / ~45 MB (Flutter)** | 120 MB - 250 MB | 300 MB - 600 MB |
| **Playback Queue Safety** | **Deterministic dual-queue** | Cloud session dependent | Volatile in-memory arrays |
| **Offline Availability** | **Complete (Zero network required)** | DRM cached or blocked | Unusable offline |

---

## License

This project is licensed under the **GNU General Public License v3.0**. See the [LICENSE](LICENSE) file for complete terms.
