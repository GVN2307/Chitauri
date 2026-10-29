import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';

class StorageService {
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  Directory? _musicDir;
  List<Track>? _cachedTracks;
  List<Playlist>? _cachedPlaylists;

  List<Track> getCachedTracks() => _cachedTracks ?? [];

  Future<Directory> getMusicDir() async {
    if (_musicDir != null && await _musicDir!.exists()) {
      return _musicDir!;
    }

    Directory? base;
    try {
      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
      if (extDirs != null && extDirs.isNotEmpty) {
        base = extDirs.first;
      }
    } catch (_) {}

    base ??= await getApplicationDocumentsDirectory();

    final dir = Directory('${base.path}/ChitauriMusic');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Ensure .nomedia sentinel file exists
    final noMedia = File('${dir.path}/.nomedia');
    if (!await noMedia.exists()) {
      await noMedia.writeAsString('');
    }

    _musicDir = dir;
    return dir;
  }

  Future<bool> isNomediaActive() async {
    final dir = await getMusicDir();
    final noMedia = File('${dir.path}/.nomedia');
    return await noMedia.exists();
  }

  Future<void> ensureNomedia() async {
    final dir = await getMusicDir();
    final noMedia = File('${dir.path}/.nomedia');
    if (!await noMedia.exists()) {
      await noMedia.writeAsString('');
    }
  }

  File _getCatalogFile(Directory dir) {
    return File('${dir.path}/tracks_catalog.json');
  }

  Future<Directory> getCoversDir() async {
    final musicDir = await getMusicDir();
    final coversDir = Directory('${musicDir.path}/.covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    return coversDir;
  }

  Future<File> getLibraryMetadataFile() async {
    final musicDir = await getMusicDir();
    return File('${musicDir.path}/library_metadata.json');
  }

  Future<Map<String, dynamic>> loadLibraryMetadata() async {
    try {
      final file = await getLibraryMetadataFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          return jsonDecode(content) as Map<String, dynamic>;
        }
      }
    } catch (e) {
      // Return empty map on error
    }
    return {};
  }

  Future<void> saveLibraryMetadataEntry(String trackId, Map<String, dynamic> metadata) async {
    try {
      final file = await getLibraryMetadataFile();
      final allMeta = await loadLibraryMetadata();
      allMeta[trackId] = metadata;
      await file.writeAsString(jsonEncode(allMeta), flush: true);
    } catch (_) {}
  }

  Future<String?> cacheCoverImageLocally(String id, String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return null;
    try {
      final coversDir = await getCoversDir();
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File('${coversDir.path}/$safeId.jpg');
      if (await targetFile.exists() && await targetFile.length() > 500) {
        return targetFile.path;
      }
      final res = await http.get(Uri.parse(imageUrl)).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200 && res.bodyBytes.length > 500) {
        await targetFile.writeAsBytes(res.bodyBytes, flush: true);
        return targetFile.path;
      }
    } catch (_) {}
    return null;
  }

  String getTrackCanonicalKey(Track track) {
    // 1. Detect if intentional user copy e.g. "(2)", "(3)"
    final copyMatch = RegExp(r'\s*\((\d+)\)$').firstMatch(track.title);
    final copySuffix = copyMatch != null ? '_copy${copyMatch.group(1)}' : '';

    // 2. Extract genuine 11-char YouTube ID from id
    final id11 = RegExp(r'([a-zA-Z0-9_-]{11})').firstMatch(track.id);
    if (id11 != null) {
      return 'yt_${id11.group(1)}$copySuffix';
    }

    // 3. Extract YouTube ID from filePath
    final path11 = RegExp(r'_([a-zA-Z0-9_-]{10,12})\.(mp3|m4a|aac|opus)$', caseSensitive: false).firstMatch(track.filePath) ??
                   RegExp(r'Song_([a-zA-Z0-9_-]{10,12})').firstMatch(track.filePath);
    if (path11 != null) {
      return 'yt_${path11.group(1)}$copySuffix';
    }

    // 4. Extract YouTube ID from thumbnailUrl
    if (track.thumbnailUrl != null) {
      final thumb11 = RegExp(r'vi/([a-zA-Z0-9_-]{10,12})').firstMatch(track.thumbnailUrl!);
      if (thumb11 != null) {
        return 'yt_${thumb11.group(1)}$copySuffix';
      }
    }

    // 5. Normalized clean title
    final cleanTitle = track.title
        .toLowerCase()
        .replaceAll(RegExp(r'\s*\(\d+\)$'), '')
        .replaceAll(RegExp(r'^(song_|track_|youtube_audio_)'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
    if (cleanTitle.isNotEmpty) {
      return 'title_$cleanTitle$copySuffix';
    }

    // 6. Base file name
    final fileName = File(track.filePath).uri.pathSegments.isNotEmpty
        ? File(track.filePath).uri.pathSegments.last.replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase()
        : track.id.toLowerCase();
    return 'file_$fileName$copySuffix';
  }

  Future<String?> resolveThumbnailPath(Directory dir, String id, String? candidateThumb, [String? filePath]) async {
    // 0. Check local .covers cache
    final coversDir = Directory('${dir.path}/.covers');
    if (await coversDir.exists()) {
      final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final cFile = File('${coversDir.path}/$safeId.jpg');
      if (await cFile.exists() && await cFile.length() > 500) {
        return cFile.path;
      }
    }

    final thumbsDir = Directory('${dir.path}/thumbnails');
    if (!await thumbsDir.exists()) return candidateThumb;

    // 1. Direct candidateThumb if it is an existing local file
    if (candidateThumb != null && !candidateThumb.startsWith('http')) {
      final f = File(candidateThumb);
      if (await f.exists() && await f.length() > 500) {
        return f.path;
      }
    }

    // 2. Exact match with ID
    final f1 = File('${thumbsDir.path}/$id.jpg');
    if (await f1.exists() && await f1.length() > 500) {
      return f1.path;
    }

    // 3. 11-char YouTube ID extracted from id
    final id11 = RegExp(r'[a-zA-Z0-9_-]{11}').firstMatch(id)?.group(0);
    if (id11 != null) {
      final f2 = File('${thumbsDir.path}/$id11.jpg');
      if (await f2.exists() && await f2.length() > 500) {
        return f2.path;
      }
    }

    // 4. 11-char YouTube ID extracted from filePath
    if (filePath != null) {
      final path11 = RegExp(r'_([a-zA-Z0-9_-]{11})\.(mp3|m4a|aac|opus)$', caseSensitive: false).firstMatch(filePath)?.group(1);
      if (path11 != null) {
        final f3 = File('${thumbsDir.path}/$path11.jpg');
        if (await f3.exists() && await f3.length() > 500) {
          return f3.path;
        }
      }
    }

    // 5. 11-char YouTube ID extracted from candidateThumb URL
    if (candidateThumb != null) {
      final urlMatch = RegExp(r'vi/([a-zA-Z0-9_-]{11})').firstMatch(candidateThumb)?.group(1);
      if (urlMatch != null) {
        final f4 = File('${thumbsDir.path}/$urlMatch.jpg');
        if (await f4.exists() && await f4.length() > 500) {
          return f4.path;
        }
      }
    }

    return candidateThumb;
  }

  Future<void> ensureLocalThumbnail(Track track) async {
    try {
      final dir = await getMusicDir();
      final thumbsDir = Directory('${dir.path}/thumbnails');
      if (!await thumbsDir.exists()) {
        await thumbsDir.create(recursive: true);
      }

      final id11 = RegExp(r'[a-zA-Z0-9_-]{11}').firstMatch(track.id)?.group(0) ??
                   RegExp(r'_([a-zA-Z0-9_-]{11})').firstMatch(track.filePath)?.group(1);

      if (id11 == null) return;

      final targetFile = File('${thumbsDir.path}/$id11.jpg');
      if (await targetFile.exists() && await targetFile.length() > 500) return;

      final urls = [
        'https://img.youtube.com/vi/$id11/maxresdefault.jpg',
        'https://img.youtube.com/vi/$id11/hqdefault.jpg',
        'https://img.youtube.com/vi/$id11/mqdefault.jpg',
      ];
      for (final u in urls) {
        try {
          final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200 && res.bodyBytes.length > 500) {
            await targetFile.writeAsBytes(res.bodyBytes, flush: true);
            final copyById = File('${thumbsDir.path}/${track.id}.jpg');
            try {
              if (copyById.path != targetFile.path) {
                await targetFile.copy(copyById.path);
              }
            } catch (_) {}
            break;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<List<Track>> loadTracks({bool forceDiskSync = false}) async {
    final dir = await getMusicDir();
    final cat = _getCatalogFile(dir);
    List<Track> catalogTracks = [];

    if (await cat.exists()) {
      try {
        final content = await cat.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List;
          catalogTracks = list.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
        }
      } catch (_) {}
    }

    final allCandidates = <Track>[];
    final catalogPaths = <String>{};

    // 1. Verify catalog entries exist on disk and are not corrupted (< 50KB)
    for (final t in catalogTracks) {
      final f = File(t.filePath);
      if (await f.exists()) {
        final len = await f.length();
        if (len >= 50000 && !t.filePath.toLowerCase().endsWith('.wav')) {
          final resolvedThumb = await resolveThumbnailPath(dir, t.id, t.thumbnailUrl, t.filePath);
          catalogPaths.add(t.filePath);

          var trackDuration = t.durationSecs;
          if (trackDuration <= 0 || trackDuration == 213 || trackDuration == 215 || trackDuration == 228) {
            try {
              final dur = await const MethodChannel('com.chitauri.audio/ytdlp')
                  .invokeMethod<int>('getAudioDuration', {'path': t.filePath});
              if (dur != null && dur > 0) {
                trackDuration = dur;
              }
            } catch (_) {}
          }

          allCandidates.add(Track(
            id: t.id,
            title: t.title,
            artist: t.artist,
            filePath: t.filePath,
            durationSecs: trackDuration,
            fileSize: len,
            thumbnailUrl: resolvedThumb,
            description: t.description,
          ));
        } else if (len < 50000) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }

    // 2. Discover newly downloaded tracks or external tracks on disk
    try {
      final diskEntities = await dir.list().toList();
      for (final entity in diskEntities) {
        if (entity is! File) continue;
        final filename = entity.uri.pathSegments.last;
        final lower = filename.toLowerCase();

        // Delete temporary / interrupted files
        if (filename.startsWith('.') ||
            lower.endsWith('.part') ||
            lower.endsWith('.tmp') ||
            lower.endsWith('.ytdl') ||
            lower.endsWith('.wav')) {
          if (filename != '.nomedia') {
            try {
              await entity.delete();
            } catch (_) {}
          }
          continue;
        }

        final len = await entity.length();
        if (len < 50000) {
          try {
            await entity.delete();
          } catch (_) {}
          continue;
        }

        final isAudio = lower.endsWith('.mp3') || lower.endsWith('.m4a') || lower.endsWith('.aac') || lower.endsWith('.opus');
        if (isAudio) {
          if (catalogPaths.contains(entity.path)) {
            continue; // Already verified and loaded from catalog with authentic metadata
          }

          final baseName = filename.replaceAll(RegExp(r'\.(mp3|m4a|aac|opus)$', caseSensitive: false), '');
          final match = RegExp(r'_([a-zA-Z0-9_-]{10,12})(?:_\d+)?$').firstMatch(baseName) ??
                        RegExp(r'Song_([a-zA-Z0-9_-]{10,12})').firstMatch(filename);
          final vidId = match != null ? match.group(1)! : (RegExp(r'^[a-zA-Z0-9_-]{10,12}$').hasMatch(baseName) ? baseName : filename);

          final cleanTitle = baseName
              .replaceAll(RegExp(r'^(Song_|YouTube_Audio_)'), '')
              .replaceAll(RegExp(r'_[a-zA-Z0-9_-]{10,12}$'), '')
              .replaceAll('_', ' ')
              .trim();

          final resolvedThumb = await resolveThumbnailPath(dir, vidId, 'https://img.youtube.com/vi/$vidId/hqdefault.jpg', entity.path);

          var diskDuration = 0;
          try {
            final dur = await const MethodChannel('com.chitauri.audio/ytdlp')
                .invokeMethod<int>('getAudioDuration', {'path': entity.path});
            if (dur != null && dur > 0) {
              diskDuration = dur;
            }
          } catch (_) {}

          allCandidates.add(Track(
            id: vidId,
            title: cleanTitle.isNotEmpty ? cleanTitle : 'Audio Track',
            artist: 'Music Artist',
            filePath: entity.path,
            durationSecs: diskDuration,
            fileSize: len,
            thumbnailUrl: resolvedThumb,
          ));
        }
      }
    } catch (_) {}

    // 3. UNBIASED DEEP DEDUPLICATION & DISK CLEANUP
    final Map<String, List<Track>> grouped = {};
    for (final cand in allCandidates) {
      final key = getTrackCanonicalKey(cand);
      grouped.putIfAbsent(key, () => []).add(cand);
    }

    final validTracks = <Track>[];
    final processedPaths = <String>{};

    for (final entry in grouped.entries) {
      final candidates = entry.value;

      // Select the single best representative for this track
      candidates.sort((a, b) {
        // Prioritize .mp3 over .m4a / .aac
        final aIsMp3 = a.filePath.toLowerCase().endsWith('.mp3') ? 1 : 0;
        final bIsMp3 = b.filePath.toLowerCase().endsWith('.mp3') ? 1 : 0;
        if (aIsMp3 != bIsMp3) return bIsMp3.compareTo(aIsMp3);

        // Prioritize genuine title over generic "Audio Track" or "Song_..."
        final aHasTitle = (!a.title.startsWith('Audio Track') && !a.title.startsWith('Song_')) ? 1 : 0;
        final bHasTitle = (!b.title.startsWith('Audio Track') && !b.title.startsWith('Song_')) ? 1 : 0;
        if (aHasTitle != bHasTitle) return bHasTitle.compareTo(aHasTitle);

        // Prioritize presence of duration
        if ((a.durationSecs > 0) != (b.durationSecs > 0)) {
          return b.durationSecs.compareTo(a.durationSecs);
        }

        // Prioritize file size (higher quality)
        return b.fileSize.compareTo(a.fileSize);
      });

      final best = candidates.first;
      final bestNormPath = best.filePath.replaceAll('\\', '/').toLowerCase();

      // Delete any duplicate physical files from disk that belonged to other candidates in this group!
      for (int i = 1; i < candidates.length; i++) {
        final dup = candidates[i];
        final dupNormPath = dup.filePath.replaceAll('\\', '/').toLowerCase();
        if (dupNormPath != bestNormPath) {
          try {
            final f = File(dup.filePath);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        }
      }

      if (!processedPaths.contains(bestNormPath)) {
        validTracks.add(best);
        processedPaths.add(bestNormPath);
        if (best.thumbnailUrl == null || best.thumbnailUrl!.startsWith('http')) {
          unawaited(ensureLocalThumbnail(best));
        }
      }
    }

    _cachedTracks = validTracks;
    await _writeCatalogDirect(validTracks);
    return List.from(validTracks);
  }

  Future<void> _writeCatalogDirect(List<Track> tracks) async {
    try {
      final dir = await getMusicDir();
      final cat = _getCatalogFile(dir);
      final jsonStr = jsonEncode(tracks.map((t) => t.toJson()).toList());
      final tmp = File('${dir.path}/tracks_catalog.json.tmp');
      await tmp.writeAsString(jsonStr, flush: true);
      if (await tmp.exists() && await tmp.length() > 0) {
        try {
          if (await cat.exists()) {
            await cat.delete();
          }
          await tmp.rename(cat.path);
        } catch (_) {
          await tmp.copy(cat.path);
          try {
            await tmp.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> saveTracks(List<Track> tracks) async {
    _cachedTracks = List.from(tracks);
    await _writeCatalogDirect(tracks);
  }

  Future<void> updateTrack(Track track) async {
    final tracks = _cachedTracks ?? await loadTracks();
    final idx = tracks.indexWhere((t) => t.id == track.id);
    if (idx != -1) {
      tracks[idx] = track;
      _cachedTracks = tracks;
      await _writeCatalogDirect(tracks);
    }
  }

  Future<void> addTrack(Track track) async {
    final tracks = _cachedTracks ?? await loadTracks();
    // Strictly deduplicate by ID and path
    final normNewPath = track.filePath.replaceAll('\\', '/').toLowerCase();
    tracks.removeWhere((t) => t.id == track.id || t.filePath.replaceAll('\\', '/').toLowerCase() == normNewPath);
    tracks.insert(0, track);
    _cachedTracks = tracks;
    await _writeCatalogDirect(tracks);
  }

  Future<Track?> renameTrack(String trackId, String newTitle, {String? newArtist}) async {
    final tracks = _cachedTracks ?? await loadTracks();
    final idx = tracks.indexWhere((t) => t.id == trackId);
    if (idx == -1) return null;

    final oldTrack = tracks[idx];
    final cleanTitle = newTitle.trim().isEmpty ? oldTrack.title : newTitle.trim();
    final cleanArtist = (newArtist != null && newArtist.trim().isNotEmpty) ? newArtist.trim() : oldTrack.artist;

    var updatedFilePath = oldTrack.filePath;
    try {
      final oldFile = File(oldTrack.filePath);
      if (await oldFile.exists()) {
        final ext = oldTrack.filePath.split('.').last;
        final safeName = cleanTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
        final targetPath = '${oldFile.parent.path}/$safeName.$ext';
        if (targetPath != oldFile.path) {
          final targetFile = File(targetPath);
          try {
            if (await targetFile.exists()) {
              await targetFile.delete();
            }
            final renamed = await oldFile.rename(targetPath);
            updatedFilePath = renamed.path;
          } catch (_) {
            await oldFile.copy(targetPath);
            try {
              await oldFile.delete();
            } catch (_) {}
            updatedFilePath = targetPath;
          }
        }
      }
    } catch (_) {}

    final updated = Track(
      id: oldTrack.id,
      title: cleanTitle,
      artist: cleanArtist,
      filePath: updatedFilePath,
      durationSecs: oldTrack.durationSecs,
      fileSize: oldTrack.fileSize,
      thumbnailUrl: oldTrack.thumbnailUrl,
      description: oldTrack.description,
    );

    tracks[idx] = updated;
    _cachedTracks = tracks;
    await _writeCatalogDirect(tracks);
    return updated;
  }

  Future<void> deleteTrack(String trackId) => deleteTracks([trackId]);

  Future<void> deleteTracks(List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    final idSet = trackIds.toSet();
    final dir = await getMusicDir();
    final tracks = _cachedTracks ?? await loadTracks();

    // 1. Delete physical audio files and thumbnails from disk
    for (final id in idSet) {
      final matches = tracks.where((t) => t.id == id).toList();
      for (final track in matches) {
        if (track.filePath.isNotEmpty) {
          try {
            final f = File(track.filePath);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        }
      }
      try {
        final thumb = File('${dir.path}/thumbnails/$id.jpg');
        if (await thumb.exists()) {
          await thumb.delete();
        }
      } catch (_) {}
    }

    // 2. Remove from cached catalog and persist immediately
    tracks.removeWhere((t) => idSet.contains(t.id));
    _cachedTracks = List.from(tracks);
    await _writeCatalogDirect(tracks);

    // 3. Remove from all playlists and favorites safely without nested locks
    try {
      final f = _getPlaylistsFile(dir);
      if (await f.exists()) {
        final content = await f.readAsString();
        final list = jsonDecode(content) as List;
        final pls = list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
        for (final p in pls) {
          p.trackIds.removeWhere((id) => idSet.contains(id));
        }
        _cachedPlaylists = List.from(pls);
        await f.writeAsString(jsonEncode(pls.map((p) => p.toJson()).toList()), flush: true);
      }
    } catch (_) {}
  }

  // Playlists & Favorites (Clean atomic file read/write)
  File _getPlaylistsFile(Directory dir) {
    return File('${dir.path}/playlists.json');
  }

  Future<List<Playlist>> loadPlaylists() async {
    if (_cachedPlaylists != null) {
      return List.from(_cachedPlaylists!);
    }
    try {
      final dir = await getMusicDir();
      final f = _getPlaylistsFile(dir);
      if (await f.exists()) {
        final content = await f.readAsString();
        final list = jsonDecode(content) as List;
        final pls = list.map((e) => Playlist.fromJson(e as Map<String, dynamic>)).toList();
        if (!pls.any((p) => p.id == 'favorites')) {
          pls.insert(0, Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), trackIds: []));
        }
        _cachedPlaylists = pls;
        return List.from(pls);
      }
    } catch (_) {}

    final defaultPls = [
      Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), trackIds: [])
    ];
    _cachedPlaylists = defaultPls;
    return List.from(defaultPls);
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    _cachedPlaylists = List.from(playlists);
    try {
      final dir = await getMusicDir();
      final f = _getPlaylistsFile(dir);
      final jsonStr = jsonEncode(playlists.map((p) => p.toJson()).toList());
      await f.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }

  Future<bool> isTrackFavorite(String trackId) async {
    final playlists = await loadPlaylists();
    final fav = playlists.firstWhere(
      (p) => p.id == 'favorites',
      orElse: () => Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), trackIds: []),
    );
    return fav.trackIds.contains(trackId);
  }

  Future<bool> toggleFavorite(String trackId) async {
    final playlists = await loadPlaylists();
    var favIndex = playlists.indexWhere((p) => p.id == 'favorites');
    if (favIndex == -1) {
      playlists.insert(0, Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), trackIds: []));
      favIndex = 0;
    }
    final fav = playlists[favIndex];
    final isFav = fav.trackIds.contains(trackId);
    if (isFav) {
      fav.trackIds.remove(trackId);
    } else {
      fav.trackIds.add(trackId);
    }
    await savePlaylists(playlists);
    return !isFav;
  }

  Future<List<Track>> getFavoriteTracks() async {
    final tracks = await loadTracks();
    final playlists = await loadPlaylists();
    final fav = playlists.firstWhere(
      (p) => p.id == 'favorites',
      orElse: () => Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), trackIds: []),
    );
    return tracks.where((t) => fav.trackIds.contains(t.id)).toList();
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlists = await loadPlaylists();
    final newPlaylist = Playlist(
      id: 'pl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'New Playlist' : name.trim(),
      createdAt: DateTime.now(),
      trackIds: [],
    );
    playlists.add(newPlaylist);
    await savePlaylists(playlists);
    return newPlaylist;
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      if (!playlists[index].trackIds.contains(trackId)) {
        playlists[index].trackIds.add(trackId);
        await savePlaylists(playlists);
      }
    }
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlists = await loadPlaylists();
    final index = playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      playlists[index].trackIds.remove(trackId);
      await savePlaylists(playlists);
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    final playlists = await loadPlaylists();
    playlists.removeWhere((p) => p.id == playlistId);
    await savePlaylists(playlists);
  }

  Future<List<FileSystemEntity>> listFiles() async {
    final dir = await getMusicDir();
    return dir.list().toList();
  }

  Future<int> getTotalDiskUsedBytes() async {
    final dir = await getMusicDir();
    int total = 0;
    try {
      final list = await dir.list().toList();
      for (final f in list) {
        if (f is File) {
          total += await f.length();
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> clearTempCache() async {
    try {
      final base = await getTemporaryDirectory();
      if (await base.exists()) {
        final list = await base.list(recursive: true).toList();
        for (final item in list) {
          if (item is File) {
            try { await item.delete(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
