# Chitauri Project - Security, Privacy & Isolation Policy (Pure Rust)

## 1. Threat Model & Security Posture

The **Chitauri Mobile Audio Suite** is built entirely in **Pure Rust**, leveraging Rust's compile-time memory safety, thread safety, and strong typing. The application operates without remote proxy servers, third-party analytics, or external telemetry.

---

## 2. Storage Isolation & Anti-Leakage Protocol

### 2.1 The Problem
Android and mobile operating systems run automated media crawler daemons (e.g., `MediaScanner` writing to `MediaStore`). Any audio file saved in conventional shared folders is scanned and added to the global media database, making the tracks immediately visible to third-party music apps (Spotify, VLC, Apple Music, Samsung Music).

### 2.2 The Solution in Rust
1. **Dedicated Application Folder:** Audio files are stored strictly inside a dedicated folder (e.g. `ChitauriMusic/` in the user's Music or App Data directory).
2. **Atomic `.nomedia` Sentinel File:**
   ```rust
   pub fn ensure_nomedia_sentinel(dir: &std::path::Path) -> std::io::Result<()> {
       let nomedia_path = dir.join(".nomedia");
       if !nomedia_path.exists() {
           std::fs::File::create(nomedia_path)?;
       }
       Ok(())
   }
   ```
3. **Isolation Guarantees:**
   * **Hidden from Third-Party Media Players:** Any folder containing a `.nomedia` file is skipped by `MediaScanner`. No tracks will be indexed in global media databases.
   * **Accessible via File Manager:** File managers directly traverse the filesystem hierarchy, allowing users to browse, copy, and open tracks at will.

---

## 3. Path Sanitization & Defense-in-Depth

### 3.1 Filename Sanitization
Titles fetched from YouTube may contain characters illegal on local filesystems (`:`, `\`, `/`, `?`, `*`) or directory traversal attacks (`../`). All filenames must pass through strict regex filtering:
```rust
pub fn sanitize_filename(name: &str) -> String {
    let sanitized: String = name
        .chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '\0' => '_',
            _ => c,
        })
        .collect();

    // Prevent directory traversal and cap length
    sanitized.replace("..", "_").trim().chars().take(120).collect()
}
```

### 3.2 Canonical Path Checks
Before any write operation, canonicalize the path with `std::fs::canonicalize` and assert that the target file is strictly a child of the trusted app storage root.

---

## 4. Privacy & Zero-Backend Invariants

1. **Direct InnerTube Queries:** All search and stream resolution queries are dispatched directly from the client to YouTube endpoints via `reqwest`. Zero intermediate proxy or recording servers are utilized.
2. **No Tracking or Telemetry:** No analytical or crash-reporting dependencies are permitted in `Cargo.toml`.
3. **Anonymous Client Identity:** Requests spoof generic anonymous client contexts (`ANDROID` / `WEB`). No Google authentication, cookies, or user tokens are requested or stored.

---

## 5. Memory & Thread Safety

1. **Strictly Safe Rust:** `#![deny(unsafe_code)]` is enforced at the root crate level.
2. **Channel-Based Concurrency:** Communication between the async Tokio worker threads and the GUI rendering loop is strictly mediated via thread-safe message channels (`std::sync::mpsc` / `tokio::sync::mpsc`).
