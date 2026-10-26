# Chitauri Project - Multi-Agent System Roles & Governance (Pure Rust)

This document establishes the multi-agent governance model for developing and auditing the **100% Pure Rust Chitauri Audio Suite**.

---

## 1. Agent Roles & Mandates

### 1.1 Lead Architect Agent (`agent:lead-architect`)
* **Mandate:** Guarantee pure Rust consistency and architectural separation across the entire application.
* **Responsibilities:**
  * Enforce pure Rust stack boundaries (`eframe`/`egui`, `tokio`, `rodio`, `reqwest`, `symphonia`).
  * Ensure zero JavaScript, zero WebViews, zero external backend servers.
  * Oversee thread boundaries between asynchronous background workers and the synchronous GUI render loop.

### 1.2 Storage Guard Agent (`agent:storage-guard`)
* **Mandate:** Enforce local media isolation via the `.nomedia` protocol and file path sanitization.
* **Responsibilities:**
  * Implement safe directory provisioning with `std::fs` and `dirs`.
  * Ensure atomic creation of the `.nomedia` sentinel file in the target media directory.
  * Guarantee that system media crawlers cannot index the application's tracks while file managers retain direct access.
  * Audit filesystem access to eliminate directory traversal (`../`) and illegal character vectors.

### 1.3 InnerTube & Stream Engineer Agent (`agent:stream-engineer`)
* **Mandate:** Deliver fast, resilient, zero-backend search and stream resolution directly from client devices.
* **Responsibilities:**
  * Construct client-side `reqwest` payloads targeting YouTube InnerTube endpoints.
  * Parse search result structures (`itemSectionRenderer`, `videoRenderer`) into strongly-typed Rust data models.
  * Resolve adaptive audio streams (AAC / itag 140 or Opus / itag 251).
  * Manage chunked downloading with real-time percentage events over `tokio::sync::mpsc`.

### 1.4 Audio Engine Agent (`agent:audio-engineer`)
* **Mandate:** Construct a high-performance, non-blocking native audio playback system.
* **Responsibilities:**
  * Manage audio device sinks via `rodio::Sink` and `rodio::OutputStream`.
  * Implement the dual-queue state machine (`original_queue` vs `playback_queue`).
  * Enforce the unbiased Fisher-Yates shuffle algorithm while pinning the current song.
  * Enforce the 3-state repeat machine (`Off`, `All`, `One`).

### 1.5 Pure Rust GUI Specialist Agent (`agent:gui-specialist`)
* **Mandate:** Build a sleek, mobile-optimized immediate-mode GUI with `egui`/`eframe`.
* **Responsibilities:**
  * Render the miniature YouTube search bar and video cards matching user blueprints.
  * Render the bottom active download drawer with live progress bars.
  * Render the sticky bottom mini-player and expandable full-screen vinyl player with time scrubbers.
  * Implement tab navigation between Search and Offline Library / Playlists.

---

## 2. Review & Approval Hierarchy

```
                      [ Lead Architect ]
                              │
         ┌────────────────────┼───────────────────┐
         ▼                    ▼                   ▼
  [ Storage Guard ]  [ Stream Engineer ]  [ Audio Engineer ]
         │                    │                   │
         └────────────────────┼───────────────────┘
                              ▼
                    [ GUI Specialist ]
```
