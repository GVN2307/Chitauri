# Workspace Rules: PulseMP3 v2 Constraints
1. **Zero Asset Bloat:** Never bundle large JSON catalogs, audio files, or static databases inside `assets/` or `res/raw/`. Only a tiny fallback seed JSON (max 30 items) is permitted locally; full catalogs must be fetched over HTTPS and cached in the device cache directory.
2. **Preserve Native Extraction Binaries:** Do not remove `useLegacyPackaging = true` in `build.gradle` if `youtubedl-android` is present, as Android requires uncompressed/extracted `.so` binaries to execute `libpython`, `libffmpeg`, and `yt-dlp`.
3. **Strict Color Tokens:** All new UI components must strictly use `#0B0B0E` (background), `#16161A` (card surface), `#4ADE80` (mint green primary accent), `#FFFFFF` (primary text), and `#A1A1AA` (secondary text).
4. **Duration Guardrails on Search Extraction:** Every automated `ytsearch1:` call must include `--match-filter "duration > 120 & duration < 480"` to prevent downloading YouTube Shorts or full-movie jukeboxes.
