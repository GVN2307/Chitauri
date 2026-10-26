# Chitauri Project - Skills & Competency Matrix

This document codifies the technical competencies, domain protocols, and operational skills required to develop, maintain, and verify the **Chitauri Audio Suite** across its desktop, mobile, and core systems.

---

## 1. Domain Skills Inventory

### 1.1 Windows Desktop Engineering (`skill:desktop-engineering`)
* **Microsoft Edge WebView2 & Modern Desktop Layout:** Developing widescreen (1260x820) responsive desktop applications with navigation sidebars, exploration grids, tabular data vaults, and turntable studios.
* **Asynchronous Localhost REST Server:** Implementing low-overhead HTTP servers (`ThreadingHTTPServer`) supporting REST endpoints (`/api/search`, `/api/download`, `/api/library`, `/api/stream_url`) and HTTP 206 Partial Content range requests for seekable HTML5 audio streaming.
* **Web Audio API Spectrum Visualizer:** Binding `AudioContext`, `MediaElementAudioSourceNode`, and `AnalyserNode` to render real-time multi-band frequency spectrums onto HTML5 canvas elements.
* **PyInstaller Standalone Packaging:** Compiling single-file standalone Windows executables (`chitauri.exe`) bundling runtimes, static assets, and application icons under 25 MB.
* **Windows Laptop Integration:** Automating desktop shortcuts (`Chitauri.lnk`), Start Menu integration (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\`), Windows App Paths, and `SetCurrentProcessExplicitAppUserModelID`.

### 1.2 Android Mobile Engineering (`skill:android-engineering`)
* **Flutter Mobile Framework:** Building touch-optimized mobile interfaces with docked mini-players, expandable vinyl sheets, and real-time download progress drawers.
* **Native Android Foreground Services:** Constructing Kotlin background services (`ChitauriDownloadService`, `ChitauriPlaybackService`) with `DATA_SYNC` and `MEDIA_PLAYBACK` types.
* **Power Management & Wake Locks:** Acquiring and releasing CPU `PARTIAL_WAKE_LOCK` instances to guarantee background downloads finish uninterrupted when devices enter low-power sleep states.
* **MediaSession & Lock Screen Transport:** Integrating `MediaSessionCompat`, `NotificationCompat`, and lock screen playback actions.
* **Hardware Duration Verification:** Calling `MediaMetadataRetriever` to extract exact millisecond audio durations from downloaded file containers.
* **16 KB Memory Page Alignment:** Enforcing `0x4000` page alignment for Android 15/16 64-bit architecture compliance.

### 1.3 Storage Isolation & Security (`skill:storage-isolation`)
* **The `.nomedia` Sentinel Protocol:** Mandatory atomic generation of a zero-byte `.nomedia` file in target audio directories (`ChitauriMusic/`) to suppress operating system indexers (`MediaScanner`, Windows Media Player, Groove, Google Drive) while preserving native file manager accessibility.
* **Path Sanitization & Traversal Prevention:** Enforcing strict character filtering (`< > : " / \ | ? * \0`) and path traversal stripping (`../`) on all user- and network-derived track titles.
* **Canonical Path Verification:** Asserting that all file I/O operations are strictly bounded within trusted application directories.

### 1.4 Client-Side YouTube Stream Resolution (`skill:stream-resolution`)
* **Direct InnerTube Communication:** Constructing asynchronous HTTP requests targeting YouTube InnerTube endpoints (`youtubei/v1/search` and `youtubei/v1/player`) using anonymous client contexts.
* **Signature Deciphering:** Unscrambling protected signature cipher tokens and solving throttling parameters (`n` signature challenges).
* **Adaptive Format Extraction:** Resolving high-quality audio streams (AAC itag 140 and Opus itag 251) and converting to 320 kbps MP3 with embedded artwork and ID3v2 tags.

### 1.5 Audio Pipeline & State Machine Architecture (`skill:audio-pipeline`)
* **Deterministic Dual-Queue Architecture:** Maintaining `original_queue` alongside `playback_queue` for lossless shuffle toggling.
* **Fisher-Yates Shuffle Invariance:** Randomizing queue order while pinning the actively playing track to index `0`.
* **Three-State Repeat Machine:** Managing transitions across `RepeatMode::Off`, `RepeatMode::All`, and `RepeatMode::One`.
* **Native Audio Decoding:** Pure Rust reference implementation using `rodio` and `symphonia` for low-latency playback without external runtime dependencies.

---

## 2. Skill Verification Standards

| Skill ID | Verification Target | Verification Standard |
| :--- | :--- | :--- |
| `desktop-engineering` | `chitauri.exe` Standalone Execution | Binary launches, renders 1260x820 widescreen layout, resolves live streams, and saves MP3s locally. |
| `android-engineering` | Release APK Compilation | `build_apk.ps1` builds clean APK with 16 KB page alignment and functional foreground download service. |
| `storage-isolation` | `.nomedia` Enforcement | Sentinel file atomically generated in target directory; path traversal attacks rejected. |
| `stream-resolution` | Stream Extraction Test | InnerTube manifests parsed directly on client device; valid GoogleVideo audio stream URLs resolved. |
| `audio-pipeline` | Playback State Unit Tests | `cargo test` confirms shuffle maintains current track at index 0 and repeat cycles deterministically. |
