# Chitauri Android Mobile Client

<p align="center">
  <img alt="Project" src="https://img.shields.io/badge/project-Chitauri%20Mobile-10b981?style=for-the-badge">
  <img alt="Target" src="https://img.shields.io/badge/target-Android%208.0+-02569B?style=for-the-badge">
  <img alt="Package" src="https://img.shields.io/badge/package-com.chitauri.audio-brightgreen?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=for-the-badge">
</p>

---

## Executive Summary

The Chitauri Android Mobile Client (`com.chitauri.audio`) is a client-side audio streaming and offline playback application built with Flutter 3.x and native Android Kotlin services. It provides YouTube search and audio stream extraction, background downloads with CPU partial wake locks, lock screen notification controls, and offline storage isolation via the `.nomedia` protocol.

---

## Key Features

1. **Touch-Optimized YouTube Search Feed**: Instantaneous search and category exploration with high-resolution album artwork, channel tags, and durations.
2. **Background Foreground Download Service**: Powered by `ChitauriDownloadService` with `DATA_SYNC` and `MEDIA_PLAYBACK` foreground service types and CPU `PARTIAL_WAKE_LOCK` to ensure downloads finish when the phone is locked.
3. **Lock Screen & Media Notification Controls**: Powered by `ChitauriPlaybackService` using `MediaSessionCompat` and Android `NotificationCompat` for lock screen transport controls and Bluetooth AVRCP support.
4. **Hardware Duration Verification**: Hardware-accelerated duration decoding via Android `MediaMetadataRetriever` to eliminate time-scrubber drift.
5. **Storage Isolation Protocol**: All downloaded tracks are saved to `/Music/ChitauriMusic/` with an atomic `.nomedia` sentinel file, preventing third-party media crawlers (`MediaScanner`, Spotify, VLC) from indexing tracks while keeping them accessible in file managers.
6. **16 KB Memory Page Alignment**: Built with `0x4000` page alignment for Android 15 and Android 16 64-bit architecture compatibility.

---

## Build Specifications

- **Package Name:** `com.chitauri.audio`
- **Minimum SDK:** Android 8.0 (API Level 26)
- **Target SDK:** Android 14+ (API Level 34, fully compatible with Android 15 & 16)
- **ABIs Supported:** `arm64-v8a`, `armeabi-v7a`, `x86_64`
- **Memory Page Alignment:** 16 KB compliant (`0x4000`)

---

## Compiling the Release APK

### Automation Script
```powershell
powershell -ExecutionPolicy Bypass -File ..\build_apk.ps1
```

### Flutter CLI
```powershell
flutter build apk --release
```

The compiled release APK is generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## Project Structure

```
chitauri_flutter/
├── android/
│   ├── app/
│   │   ├── src/main/AndroidManifest.xml
│   │   └── src/main/kotlin/com/chitauri/audio/
│   │       ├── ChitauriDownloadService.kt  # Background download service with wake lock
│   │       ├── ChitauriPlaybackService.kt  # Media notification & playback service
│   │       └── MainActivity.kt             # Hardware retriever & platform channels
│   └── build.gradle
├── lib/
│   ├── main.dart                           # Application initialization & navigation
│   ├── models/
│   │   └── track.dart                      # Audio track and playlist data models
│   ├── services/
│   │   ├── audio_player_service.dart       # State machine & queue coordinator
│   │   ├── storage_service.dart            # .nomedia protocol & catalog manager
│   │   └── youtube_service.dart            # InnerTube resolver & stream parser
│   ├── theme/
│   │   └── pulse_theme.dart                # Visual design system and color tokens
│   ├── views/
│   │   ├── library_view.dart               # Offline track library & playlists
│   │   ├── profile_view.dart               # Storage metrics & track count view
│   │   ├── queue_view.dart                 # Active playback queue view
│   │   ├── youtube_search_view.dart        # Search interface & stream trigger
│   │   └── youtube_webview.dart            # Direct feed parser & duplicate detection
│   └── widgets/
│       ├── mini_player.dart                # Docked persistent bottom player
│       └── vinyl_player_sheet.dart         # Fullscreen turntable player sheet
└── pubspec.yaml                            # Flutter dependency manifest
```

---

## License

This mobile application is licensed under the **GNU General Public License v3.0**. See the root [LICENSE](../LICENSE) file for complete terms.
