# Chitauri Project - Multi-Agent System Roles & Governance

This document establishes the multi-agent governance model for developing, auditing, and maintaining the **Chitauri Audio Suite** across its multi-platform targets.

---

## 1. Agent Roles & Mandates

### 1.1 Lead Architect Agent (`agent:lead-architect`)
* **Mandate:** Guarantee architectural integrity, zero-backend invariants, and cross-platform consistency across the entire project.
* **Responsibilities:**
  * Enforce zero external proxy servers and zero cloud dependencies across all codebases.
  * Oversee architectural boundaries between presentation layers and backend services.
  * Audit data models and ensure state machine parity between Android, Windows Desktop, and Rust Core implementations.
  * Coordinate release builds, documentation accuracy, and license compliance (GPL-3.0).

### 1.2 Windows Desktop Specialist Agent (`agent:desktop-specialist`)
* **Mandate:** Build, maintain, and audit the full-fledged Windows Desktop Application (`chitauri.exe`).
* **Responsibilities:**
  * Maintain the 1260x820 widescreen desktop interface (`desktop_app/index.html`) and responsive desktop layouts.
  * Maintain the asynchronous localhost REST HTTP server (`desktop_app/app.py`) with HTTP 206 Partial Content range streaming.
  * Optimize the real-time Web Audio API 36-band frequency spectrum visualizer and turntable studio animations.
  * Manage PyInstaller single-file standalone executable compilation (`chitauri.exe`), ensuring binary size remains under 25 MB.
  * Guarantee Windows laptop integration via `install.bat`, `install.ps1`, Desktop/Start Menu shortcuts, and Windows `AppUserModelID`.

### 1.3 Android Mobile Engineer Agent (`agent:mobile-engineer`)
* **Mandate:** Deliver high-performance, battery-efficient mobile execution on Android devices (`com.chitauri.audio`).
* **Responsibilities:**
  * Maintain the Flutter Dart mobile interface (`chitauri_flutter/lib/`).
  * Implement and audit native Android Kotlin Foreground Services (`ChitauriDownloadService`, `ChitauriPlaybackService`).
  * Enforce CPU `PARTIAL_WAKE_LOCK` management during downloads to prevent network dropouts when the screen is locked.
  * Integrate Android `MediaSessionCompat` and lock screen notification transport controls.
  * Manage 16 KB memory page alignment (`0x4000`) for Android 15/16 64-bit architecture compliance.

### 1.4 Storage & Security Guard Agent (`agent:storage-guard`)
* **Mandate:** Enforce local media isolation via the `.nomedia` protocol, filename sanitization, and privacy invariants.
* **Responsibilities:**
  * Implement safe directory provisioning in `/Music/ChitauriMusic/` across Windows and Android.
  * Ensure atomic creation of the `.nomedia` sentinel file in the target media directory.
  * Guarantee that operating system media crawlers (`MediaScanner`, Windows Media Player, Groove, Google Drive) cannot index application tracks while user file managers retain complete direct access.
  * Audit all filesystem operations to eliminate directory traversal (`../`) and illegal character vectors.
  * Guarantee zero analytical tracking, zero telemetry, and anonymous YouTube client emulation.

### 1.5 Core Systems & Audio Engineer Agent (`agent:audio-systems-engineer`)
* **Mandate:** Maintain the deterministic audio engine, state machine algorithms, and pure Rust reference core.
* **Responsibilities:**
  * Maintain the dual-queue state machine (`original_queue` vs `playback_queue`) ensuring lossless shuffle toggling.
  * Enforce the unbiased Fisher-Yates shuffle algorithm while pinning the actively playing track to index `0`.
  * Enforce the three-state repeat state machine (`Off`, `All`, `One`).
  * Maintain the native Rust reference core (`src/`, `Cargo.toml`) using `rodio`, `symphonia`, and `tokio`.
  * Maintain unit and integration test suites (`tests/player_state_test.rs`, `tests/storage_isolation_test.rs`).

---

## 2. Review & Approval Hierarchy

```
                             [ Lead Architect ]
                                      │
         ┌────────────────────────────┼───────────────────────────┐
         ▼                            ▼                           ▼
  [ Storage Guard ]         [ Desktop Specialist ]        [ Mobile Engineer ]
         │                            │                           │
         └────────────────────────────┼───────────────────────────┘
                                      ▼
                        [ Audio Systems Engineer ]
```
