# Chitauri Project - Developer Instructions (Pure Rust Architecture)

## 1. Core Directives

1. **100% Pure Rust Implementation:** The entire system—including the GUI, storage layer, network extraction, audio decoding, and playback engine—must be written in idiomatic Rust. No WebViews, JavaScript, or external web runtimes.
2. **Zero External Backend Servers:** All operations (YouTube search, extraction, download, ID3 tag insertion, storage, and audio playback) must execute directly on the client machine using native Rust crates.
3. **Mandatory Storage Isolation (`.nomedia`):** The app must generate and manage its own media storage directory (e.g. `ChitauriMusic/`) and atomically guarantee the existence of a `.nomedia` sentinel file. This prevents other media players from scanning and displaying the app's tracks, while allowing users to inspect and play them via file managers.
4. **Decoupled Architecture:**
   * `search`: Miniature YouTube search, results feed, and download trigger.
   * `library`: Local track scanner, playlist creation, track deletion, and `.nomedia` storage inspector.
   * `player`: Native audio output via `rodio`, dual-queue state machine, shuffle, repeat, and bottom sticky mini-player / full player.
5. **Robust Concurrency:** Heavy networking and disk I/O must run asynchronously inside a Tokio runtime thread pool, communicating with the GUI thread via non-blocking channels (`std::sync::mpsc` / `tokio::sync::mpsc`).

---

## 2. Cargo Project Structure

```
c:\Users\veera\Desktop\Codes for fun\Chitauri\
 ├── Cargo.toml                    # Cargo manifest with pure Rust dependencies
 ├── SKILLS.md                     # Skill competencies and verification standards
 ├── INSTRUCTIONS.md               # Developer rules and technical instructions
 ├── AGENTS.md                     # Multi-agent role governance
 ├── SECURITY.md                   # Security and storage isolation policies
 └── src/
      ├── main.rs                  # Application entry point & eframe window setup
      ├── app.rs                   # Main eframe::App implementation & tab router
      ├── models.rs                # Shared data models (Track, Playlist, DownloadItem, PlayerState)
      ├── storage.rs               # Directory creation, .nomedia sentinel, track indexing
      ├── innertube.rs             # Client-side InnerTube search & audio stream extractor
      ├── downloader.rs            # Async chunk downloader & progress event dispatcher
      ├── player.rs                # rodio audio engine, dual-queue, shuffle & repeat logic
      └── ui/
           ├── mod.rs              # UI module exports & shared styling
           ├── search_view.rs      # Miniature YouTube search header & video cards
           ├── library_view.rs     # Offline tracks, playlists manager & storage inspector
           ├── player_view.rs      # Bottom mini-player & expandable full-screen player
           └── components.rs       # Reusable UI widgets (cards, badges, progress bars)
```

---

## 3. Strict Coding Standards

### 3.1 Memory Safety & Error Handling
* Forbid `unsafe` blocks unless explicitly approved by the Lead Architect.
* Use `thiserror` and `anyhow` for structured error handling.
* Sanitize all filenames before writing to disk using standard character filtering to prevent path traversal (`../`) attacks.

### 3.2 Queue Invariance & Shuffle Logic
* The active playing track must never be interrupted when toggling shuffle.
* `shuffle()` must retain the current track at index 0 and randomize remaining items.
* `unshuffle()` must restore the original queue order without altering playback state.

### 3.3 Repeat Mode State Machine
* `RepeatMode::Off`: Stop when the final track in the queue finishes.
* `RepeatMode::All`: Wrap `current_index` back to `0` when queue ends.
* `RepeatMode::One`: Replay the active track indefinitely.

---

## 4. Run & Test Instructions

```powershell
# Run the application in development mode
cargo run

# Build optimized release binary
cargo run --release

# Run unit tests
cargo test
```
