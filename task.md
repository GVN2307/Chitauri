# Tasks: Chitauri Audio Suite v4 Upgrade

- [ ] **Fix 8: Multi-Regional Rhythm-DNA Catalog Harvesting (`scripts/build_regional_dna_catalog.py`)** <!-- id: 8 -->
  - [ ] Write Python harvesting script for Telugu, Tamil, Malayalam, Kannada, Hindi (1970s–2020s) with Rhythm-DNA attributes <!-- id: 8.1 -->
  - [ ] Run script and output `catalog/<lang>_<decade>.json` and `catalog/manifest.json` <!-- id: 8.2 -->

- [ ] **Fix 7: Multi-Regional Rhythm-DNA Engine & Models (`telugu_song.dart`)** <!-- id: 7 -->
  - [ ] Expand `TeluguSong` to `SongItem` with `bpm`, `rhythmPulse`, `harmonicMood`, `energyLevel` <!-- id: 7.1 -->
  - [ ] Implement Gaussian Rarity Scoring centered at popularity = 62 <!-- id: 7.2 -->
  - [ ] Implement canonical fingerprint deduplication and `normalizedDedupeKey` <!-- id: 7.3 -->

- [ ] **Fix 1: Sub-7s Pre-Resolved Downloads & Fast Native Audio Mode** <!-- id: 1 -->
  - [ ] In `youtube_service.dart`: implement InnerTube/lightweight search pre-resolver in Dart (<400ms) with duration guard (90s–540s) <!-- id: 1.1 -->
  - [ ] In `youtube_service.dart`: pass direct `https://www.youtube.com/watch?v=$videoId` to native channel <!-- id: 1.2 -->
  - [ ] In `MainActivity.kt`: enable Fast Native Audio mode (`-f 140/ba[ext=m4a]/ba`, `--concurrent-fragments 4`, no ffmpeg re-encode) <!-- id: 1.3 -->

- [ ] **Fix 2: Unified Queue Routing & Banner Persistence** <!-- id: 2 -->
  - [ ] Route all "For You" & Dynamic Playlist downloads into `DownloadQueueManager` (Tab 3 "Queue") <!-- id: 2.1 -->
  - [ ] Download and cache cover images to `Music/ChitauriMusic/.covers/<id>.jpg` <!-- id: 2.2 -->
  - [ ] Save full song metadata to `Music/ChitauriMusic/library_metadata.json` <!-- id: 2.3 -->

- [ ] **Fix 3: Repeat Play Blank/Silent Audio Bug** <!-- id: 3 -->
  - [ ] In `audio_player_service.dart`: on repeat completion, execute `await _player.stop(); await _player.play(...)` <!-- id: 3.1 -->
  - [ ] Verify audio buffer resets cleanly on repeat <!-- id: 3.2 -->

- [ ] **Fix 4: Persistent Square Grid UI, Scroll-Jump Fix & Era Lazy Loading** <!-- id: 4 -->
  - [ ] Default `ViewMode` to `squareGrid` / `iconGrid` and persist in `SharedPreferences` <!-- id: 4.1 -->
  - [ ] Use `PageStorageKey` and maintain `ScrollController` in `initState()` to fix scroll jump <!-- id: 4.2 -->
  - [ ] Add `AutomaticKeepAliveClientMixin` to preserve tab scroll state <!-- id: 4.3 -->
  - [ ] Make era chips lazy-loaded (20 songs per page on scroll) <!-- id: 4.4 -->

- [ ] **Fix 5: Tab 3 ("My MP3 Library") Square Tile View Toggle & Sort Bar** <!-- id: 5 -->
  - [ ] Add Square Grid / List View toggle button with `SharedPreferences` persistence <!-- id: 5.1 -->
  - [ ] Add 5-option Sort Bar (Date Newest/Oldest, Song A-Z, Z-A, Year/Duration) <!-- id: 5.2 -->
  - [ ] Render local cached banners from `.covers/` / `library_metadata.json` <!-- id: 5.3 -->

- [ ] **Fix 6: Multi-Regional Catalog Integration & Permanent Fingerprint Exclusion** <!-- id: 6 -->
  - [ ] Add language pills: `[ All, Telugu, Tamil, Malayalam, Kannada, Hindi, English ]` <!-- id: 6.1 -->
  - [ ] Add Global English API integration with randomized deep offset (20–180) <!-- id: 6.2 -->
  - [ ] Implement `downloadedFingerprints` + `seenFingerprintsRingBuffer` (size 200) <!-- id: 6.3 -->
  - [ ] Add dynamic mix refresh button (🔄) and infinite lazy loading inside playlist modals <!-- id: 6.4 -->

- [ ] **Fix 9: Verification Deliverables & Release Deployment** <!-- id: 9 -->
  - [ ] Update and execute Dart unit test suite (`flutter test`) <!-- id: 9.1 -->
  - [ ] Execute `flutter analyze` with 0 errors <!-- id: 9.2 -->
  - [ ] Build release split APK (`build_apk.ps1`) <!-- id: 9.3 -->
  - [ ] Install on `emulator-5554` via ADB and perform live verification <!-- id: 9.4 -->
  - [ ] Commit and push to `https://github.com/GVN2307/Chitauri` <!-- id: 9.5 -->
