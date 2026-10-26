# Chitauri Project - Skills & Competency Matrix (Pure Rust)

This document codifies the technical competencies, domain protocols, and operational skills required to develop, maintain, and verify the **100% Pure Rust Chitauri Audio Suite**.

---

## 1. Domain Skills Inventory

### 1.1 Pure Rust Mobile/Desktop GUI (`skill:rust-gui-engineering`)
* **Immediate-Mode UI with `egui` / `eframe`:** Developing 100% Rust native user interfaces with zero JavaScript, zero HTML/CSS, and zero WebView overhead.
* **Mobile-Responsive Frame Architecture:** Handling virtual mobile viewports (380x800), high-DPI scaling, smooth 60fps animations (spinning vinyl, pulsating download indicators).
* **Async-to-Sync UI Bridging:** Interfacing non-blocking Tokio background runtimes with `eframe`'s frame loop using `std::sync::mpsc` channels and `Arc<Mutex<T>>`.

### 1.2 Storage Isolation & OS Sandboxing in Rust (`skill:rust-storage-isolation`)
* **Standard Library Filesystem & Scoped Isolation:** Managing directory structures using `std::fs`, `std::path::PathBuf`, and `dirs`/`directories` crates.
* **The `.nomedia` Sentinel Protocol:** Mandatory atomic generation of a zero-byte `.nomedia` file (`File::create(".nomedia")`) in all target audio directories to suppress Android `MediaScanner` crawler daemon indexing while preserving file-manager accessibility.
* **Canonical Path Verification:** Enforcing strict path bounds using `std::fs::canonicalize` to eliminate directory traversal (`../`) vulnerabilities.

### 1.3 InnerTube Scraping & Stream Resolution (`skill:rust-innertube`)
* **Client-Side InnerTube Client:** Direct async HTTP requests using `reqwest` (with connection pooling) to `https://www.youtube.com/youtubei/v1/search` and `youtubei/v1/player`.
* **Zero-Backend Architecture:** 100% client-side query execution with anonymous Android client profile payloads. Zero remote server dependency.
* **Adaptive Stream Filtering:** Extracting `streamingData.adaptiveFormats` to identify high-quality audio streams (itag 140 AAC ~128kbps, itag 251 Opus ~160kbps).
* **Chunked Streaming & Reactive Progress:** Streaming HTTP response byte chunks via `futures_util::StreamExt`, calculating download progress percentages, and transmitting events over `tokio::sync::mpsc`.

### 1.4 Pure Rust Audio Pipeline & Engine (`skill:rust-audio-engine`)
* **Native Playback with `rodio`:** Cross-platform audio device output using `rodio::OutputStream` and `rodio::Sink`.
* **Audio Decoding with `symphonia`:** Pure Rust decoding of AAC, MP3, Vorbis, and FLAC without native C/C++ dependencies.
* **ID3 Tagging & Metadata Embedding:** Parsing and writing ID3v2 tags (Title, Artist, Album, Year, Embedded Cover Art) via the `id3` crate.
* **Deterministic Dual-Queue Architecture:** Maintaining `original_queue` alongside `playback_queue` for lossless shuffle toggling.
* **Fisher-Yates Shuffle Invariance:** Randomizing queue order while pinning the actively playing track to index `0`.
* **Three-State Repeat Machine:** Handling transitions across `RepeatMode::Off`, `RepeatMode::All`, and `RepeatMode::One`.

---

## 2. Skill Verification Standards

| Skill ID | Verification Target | Verification Standard |
| :--- | :--- | :--- |
| `rust-gui-engineering` | `eframe` App Render | Pure Rust binary compilation, zero WebViews or JS dependencies |
| `rust-storage-isolation` | `.nomedia` Verification | File exists in target directory; path traversal blocked |
| `rust-innertube` | Network & Parser Test | InnerTube JSON parsed directly into Rust structs with zero backend proxies |
| `rust-audio-engine` | Playback & State Test | `rodio` output active, pause/resume/seek functional, shuffle maintains current track |
