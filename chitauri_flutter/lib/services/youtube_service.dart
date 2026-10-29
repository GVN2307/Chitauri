import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/telugu_song.dart';
import '../models/track.dart';
import 'audio_player_service.dart';
import 'storage_service.dart';
import 'taste_profiler.dart';

class DownloadProgressEvent {
  final String songId;
  final String title;
  final double progress;
  final String statusText;
  final bool isCompleted;
  final bool isFailed;

  const DownloadProgressEvent({
    required this.songId,
    required this.title,
    required this.progress,
    required this.statusText,
    this.isCompleted = false,
    this.isFailed = false,
  });
}

class ResolvedYouTubeVideo {
  final String videoId;
  final String watchUrl;
  final String title;
  final String channel;
  final int durationSecs;
  final String thumbnailUrl;

  const ResolvedYouTubeVideo({
    required this.videoId,
    required this.watchUrl,
    required this.title,
    required this.channel,
    required this.durationSecs,
    required this.thumbnailUrl,
  });
}

class AuthenticatedYoutubeHttpClient extends YoutubeHttpClient {
  static const String modernUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  String? _sessionCookies;

  AuthenticatedYoutubeHttpClient([http.Client? inner, this._sessionCookies])
      : super(inner ?? http.Client());

  void updateCookies(String cookies) {
    if (cookies.isNotEmpty) {
      _sessionCookies = cookies;
    }
  }

  @override
  Map<String, String> get headers => {
        'user-agent': modernUserAgent,
        'accept-language': 'en-US,en;q=0.9',
        'accept': '*/*',
        if (_sessionCookies != null && _sessionCookies!.isNotEmpty)
          'cookie': _sessionCookies!,
      };
}

class YouTubeService {
  static final YouTubeService instance = YouTubeService._internal();
  
  static const String modernUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UD1A.230803.041) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  String? _cachedCookies;
  bool isFastMode = false;

  Future<String> getSessionCookies([String? videoId]) async {
    if (_cachedCookies != null && _cachedCookies!.isNotEmpty) {
      return _cachedCookies!;
    }
    // 1. Try querying native Android CookieManager
    if (Platform.isAndroid) {
      try {
        final c = await _nativeYtDlp.invokeMethod<String>('getYoutubeCookies');
        if (c != null && c.isNotEmpty) {
          _cachedCookies = c;
          return c;
        }
      } catch (_) {}
    }

    // 2. Automated handshake fetch
    try {
      final target = videoId != null
          ? 'https://www.youtube.com/watch?v=$videoId'
          : 'https://www.youtube.com';
      final resp = await http.get(
        Uri.parse(target),
        headers: {'user-agent': modernUserAgent},
      ).timeout(const Duration(seconds: 4));

      final setCookies = resp.headers['set-cookie'] ?? '';
      if (setCookies.isNotEmpty) {
        final cookiePairs = <String>[];
        for (final part in setCookies.split(',')) {
          final sub = part.split(';').first.trim();
          if (sub.contains('=')) {
            cookiePairs.add(sub);
          }
        }
        _cachedCookies = cookiePairs.join('; ');
        return _cachedCookies!;
      }
    } catch (_) {}

    return '';
  }

  Future<YoutubeExplode> getAuthenticatedYt([String? videoId]) async {
    final cookies = await getSessionCookies(videoId);
    final client = AuthenticatedYoutubeHttpClient(null, cookies);
    return YoutubeExplode(client);
  }

  /// Fast (<400ms) InnerTube search pre-resolver in Dart.
  /// Bypasses Python yt-dlp search scanning, extracts direct videoId & duration,
  /// and guards against Shorts (<90s) and full movie jukeboxes (>540s).
  Future<ResolvedYouTubeVideo?> preResolveYouTubeVideo(String rawQuery) async {
    final query = rawQuery.replaceFirst(RegExp(r'^ytsearch\d*:'), '').trim();
    if (query.isEmpty) return null;

    // 1. Try lightweight InnerTube search API in pure Dart (<400ms)
    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/search');
      final payload = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20240101.00.00',
            'hl': 'en',
            'gl': 'IN',
          }
        },
        'query': query,
      });

      final resp = await http.post(
        uri,
        headers: {
          'content-type': 'application/json',
          'user-agent': modernUserAgent,
          'accept': '*/*',
        },
        body: payload,
      ).timeout(const Duration(milliseconds: 3500));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final contents = decoded['contents']?['twoColumnSearchResultsRenderer']?['primaryContents']?['sectionListRenderer']?['contents'];
        if (contents is List) {
          for (final section in contents) {
            final itemSection = section['itemSectionRenderer']?['contents'];
            if (itemSection is List) {
              for (final item in itemSection) {
                final vid = item['videoRenderer'];
                if (vid is Map) {
                  final vId = vid['videoId'] as String?;
                  if (vId == null || vId.length != 11) continue;

                  int durSecs = 215;
                  final lenSimple = vid['lengthText']?['simpleText'] as String?;
                  if (lenSimple != null) {
                    final parts = lenSimple.split(':');
                    if (parts.length == 2) {
                      durSecs = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
                    } else if (parts.length == 3) {
                      durSecs = (int.tryParse(parts[0]) ?? 0) * 3600 + (int.tryParse(parts[1]) ?? 0) * 60 + (int.tryParse(parts[2]) ?? 0);
                    }
                  }

                  // Filter out shorts (<90s) and full movie jukeboxes (>540s)
                  if (durSecs > 0 && (durSecs < 90 || durSecs > 540)) {
                    continue;
                  }

                  final titleRun = (vid['title']?['runs'] as List?)?.firstOrNull?['text'] as String? ?? query;
                  final channelRun = (vid['ownerText']?['runs'] as List?)?.firstOrNull?['text'] as String? ?? 'Artist';
                  final thumbUrl = 'https://i.ytimg.com/vi/$vId/hqdefault.jpg';

                  return ResolvedYouTubeVideo(
                    videoId: vId,
                    watchUrl: 'https://www.youtube.com/watch?v=$vId',
                    title: titleRun,
                    channel: channelRun,
                    durationSecs: durSecs,
                    thumbnailUrl: thumbUrl,
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('InnerTube pre-resolve exception: $e');
    }

    // 2. YoutubeExplode search fallback
    try {
      final ytClient = await getAuthenticatedYt();
      try {
        final searchBatch = await ytClient.search.search(query).timeout(const Duration(seconds: 4));
        for (final v in searchBatch) {
          final dur = v.duration?.inSeconds ?? 215;
          if (dur > 0 && (dur < 90 || dur > 540)) {
            continue;
          }
          return ResolvedYouTubeVideo(
            videoId: v.id.value,
            watchUrl: 'https://www.youtube.com/watch?v=${v.id.value}',
            title: v.title,
            channel: v.author,
            durationSecs: dur,
            thumbnailUrl: 'https://i.ytimg.com/vi/${v.id.value}/hqdefault.jpg',
          );
        }
      } finally {
        ytClient.close();
      }
    } catch (_) {}

    return null;
  }
  
  void Function(double progress, String statusText)? _activeNativeProgressCallback;
  String? _activeNativeVideoId;

  final StreamController<DownloadProgressEvent> _downloadProgressController =
      StreamController<DownloadProgressEvent>.broadcast();
  Stream<DownloadProgressEvent> get downloadProgressStream => _downloadProgressController.stream;

  DownloadProgressEvent? _activeDownloadEvent;
  DownloadProgressEvent? get activeDownloadEvent => _activeDownloadEvent;

  void _emitDownloadProgress(DownloadProgressEvent event) {
    _activeDownloadEvent = event;
    _downloadProgressController.add(event);
  }

  YouTubeService._internal() {
    if (Platform.isAndroid) {
      _nativeYtDlp.setMethodCallHandler((call) async {
        if (call.method == 'onProgress') {
          final args = call.arguments as Map?;
          if (args != null) {
            final vId = args['videoId'] as String?;
            if (vId == _activeNativeVideoId && _activeNativeProgressCallback != null) {
              final p = (args['progress'] as num?)?.toDouble() ?? 0.0;
              final txt = args['statusText'] as String? ?? '${(p * 100).toInt()}%';
              _activeNativeProgressCallback!(p, txt);
            }
          }
        }
      });
    }
  }

  final YoutubeExplode _yt = YoutubeExplode();
  static const MethodChannel _nativeYtDlp = MethodChannel('com.chitauri.audio/ytdlp');

  String? extractVideoId(String input) {
    input = input.trim();
    if (input.isEmpty) return null;

    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(input)) {
      return input;
    }

    try {
      final uri = Uri.parse(input);
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
      if (uri.pathSegments.contains('watch')) {
        final idx = uri.pathSegments.indexOf('watch');
        if (idx + 1 < uri.pathSegments.length) {
          return uri.pathSegments[idx + 1];
        }
      }
      if (uri.pathSegments.contains('shorts')) {
        final idx = uri.pathSegments.indexOf('shorts');
        if (idx + 1 < uri.pathSegments.length) {
          return uri.pathSegments[idx + 1];
        }
      }
    } catch (_) {}
    return null;
  }

  String? extractPlaylistId(String input) {
    input = input.trim();
    if (input.isEmpty) return null;

    if (RegExp(r'^(PL|UU|LL|RD|OLAK)[a-zA-Z0-9_-]+$').hasMatch(input)) {
      return input;
    }

    try {
      final uri = Uri.parse(input);
      if (uri.queryParameters.containsKey('list')) {
        return uri.queryParameters['list'];
      }
      final match = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)').firstMatch(input);
      if (match != null) {
        return match.group(1);
      }
    } catch (_) {}
    return null;
  }

  Future<List<YouTubeVideoItem>> getPlaylistTracks(String playlistIdOrUrl) async {
    final playlistId = extractPlaylistId(playlistIdOrUrl) ?? playlistIdOrUrl;
    final canonicalPlaylistUrl = 'https://www.youtube.com/playlist?list=$playlistId';

    // 1. Native yt-dlp flat playlist extraction (fastest, robust client-side bypass)
    if (Platform.isAndroid) {
      try {
        final jsonStr = await _nativeYtDlp.invokeMethod<String>('getPlaylistVideos', {
          'url': canonicalPlaylistUrl,
        }).timeout(const Duration(seconds: 45));

        if (jsonStr != null && jsonStr.isNotEmpty) {
          final items = parsePlaylistJson(jsonStr);
          if (items.isNotEmpty) return items;
        }
      } catch (e) {
        debugPrint('Native playlist extraction error: $e');
      }
    }

    // 2. YoutubeExplode authenticated fallback
    try {
      final yt = await getAuthenticatedYt();
      try {
        final items = <YouTubeVideoItem>[];
        await for (final v in yt.playlists.getVideos(playlistId).take(100)) {
          final dur = v.duration?.inSeconds ?? 215;
          if (dur > 0 && (dur < 90 || dur > 540)) {
            continue;
          }
          items.add(YouTubeVideoItem(
            id: v.id.value,
            title: _cleanSongTitle(v.title),
            channel: v.author,
            duration: v.duration != null
                ? '${v.duration!.inMinutes}:${(v.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
                : '03:45',
            views: 'Playlist',
            thumbnailUrl: v.thumbnails.mediumResUrl,
            url: v.url,
          ));
        }
        if (items.isNotEmpty) return items;
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('YoutubeExplode playlist extraction error: $e');
    }

    return [];
  }

  /// Parses yt-dlp `--flat-playlist --dump-single-json` output with Safeguard 2 duration filtering.
  List<YouTubeVideoItem> parsePlaylistJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      final List rawEntries;
      if (decoded is List) {
        rawEntries = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['entries'] is List) {
        rawEntries = decoded['entries'] as List;
      } else if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        rawEntries = decoded['items'] as List;
      } else {
        return [];
      }

      final items = <YouTubeVideoItem>[];
      for (final raw in rawEntries) {
        if (raw is! Map) continue;
        final e = raw as Map<String, dynamic>;
        final id = (e['id'] as String?) ?? extractVideoId(e['url'] as String? ?? '') ?? '';
        if (id.isEmpty) continue;

        final rawDuration = (e['duration'] as num?)?.toInt();
        // Safeguard 2: Filter out shorts (<90s) and multi-hour mixes/jukeboxes (>540s),
        // but preserve nullable duration (duration: null or <= 0) to avoid false drops.
        if (rawDuration != null && rawDuration > 0 && (rawDuration < 90 || rawDuration > 540)) {
          continue;
        }
        final durSecs = (rawDuration != null && rawDuration > 0) ? rawDuration : 215;
        final minutes = durSecs ~/ 60;
        final seconds = durSecs % 60;
        final durFormatted = '$minutes:${seconds.toString().padLeft(2, '0')}';

        final rawTitle = (e['title'] as String?) ?? 'Song';
        final channel = (e['uploader'] as String?) ?? (e['channel'] as String?) ?? (e['artist'] as String?) ?? 'Music Artist';

        String? thumb = e['thumbnail'] as String?;
        if (thumb == null && e['thumbnails'] is List && (e['thumbnails'] as List).isNotEmpty) {
          final thumbs = e['thumbnails'] as List;
          final last = thumbs.last;
          if (last is Map && last['url'] is String) {
            thumb = last['url'] as String;
          }
        }
        thumb ??= 'https://img.youtube.com/vi/$id/hqdefault.jpg';

        items.add(YouTubeVideoItem(
          id: id,
          title: _cleanSongTitle(rawTitle),
          channel: channel,
          duration: durFormatted,
          views: 'Playlist',
          thumbnailUrl: thumb,
          url: 'https://www.youtube.com/watch?v=$id',
        ));
      }
      return items;
    } catch (e) {
      debugPrint('Error parsing playlist JSON: $e');
      return [];
    }
  }

  Future<Map<String, String>> fetchVideoMetadata(String videoId) async {
    String? title;
    String? artist;
    String? description;
    String? thumbnail;

    // 1. YouTube official unauthenticated oEmbed endpoint (lightning fast, accurate titles)
    try {
      final uri = Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
      final res = await http.get(uri, headers: {'user-agent': modernUserAgent}).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rawTitle = (data['title'] as String?)?.trim() ?? '';
        final author = (data['author_name'] as String?)?.trim() ?? '';
        if (rawTitle.isNotEmpty) {
          final parsed = parseTitleAndArtist(rawTitle, defaultArtist: author);
          title = parsed['title'];
          artist = parsed['artist'];
          thumbnail = (data['thumbnail_url'] as String?) ?? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
        }
      }
    } catch (_) {}

    // 2. Fallback to YoutubeExplode metadata client only if oEmbed didn't provide title
    if (title == null || title.isEmpty || title.startsWith('Track ') || title.startsWith('Song ')) {
      final metaYt = YoutubeExplode();
      try {
        final vid = await metaYt.videos.get(videoId).timeout(const Duration(seconds: 5));
        final parsed = parseTitleAndArtist(vid.title, defaultArtist: vid.author);
        title = parsed['title'];
        artist = parsed['artist'];
        thumbnail ??= vid.thumbnails.highResUrl;
        if (vid.description.isNotEmpty) {
          description = vid.description;
        }
      } catch (_) {} finally {
        metaYt.close();
      }
    }

    title ??= 'Song';
    artist ??= 'Music Artist';
    thumbnail ??= 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

    return {
      'title': title,
      'artist': artist,
      'thumbnail': thumbnail,
      if (description != null && description.isNotEmpty) 'description': description,
    };
  }

  Map<String, String> parseTitleAndArtist(String rawTitle, {String defaultArtist = ''}) {
    // 1. Clean boilerplate suffixes like (Official Music Video), (4K Remaster), [HD], etc.
    var cleaned = rawTitle
        .replaceAll(RegExp(r'[\(\[]\s*(official\s*(music\s*)?video|video\s*song|full\s*video|4k\s*remaster|4k|hd|hq|lyric\s*video|lyrics|official\s*audio|audio|visualizer)\s*[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\|\s*(official\s*(music\s*)?video|video\s*song|full\s*video|lyric\s*video).*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    String songTitle = cleaned;
    String songArtist = defaultArtist.trim();

    // 2. Check for "Artist - Title" format
    if (cleaned.contains(' - ') || cleaned.contains(' – ')) {
      final parts = cleaned.split(RegExp(r'\s+[-–]\s+'));
      if (parts.length >= 2) {
        final p0 = parts[0].trim();
        final p1 = parts.sublist(1).join(' - ').trim();
        if (p1.isNotEmpty) {
          songTitle = p1;
          songArtist = p0;
        }
      }
    } else if (cleaned.contains(' | ')) {
      final parts = cleaned.split(RegExp(r'\s+\|\s+'));
      if (parts.length >= 2) {
        songTitle = parts[0].trim();
      }
    }

    if (songArtist.isEmpty || songArtist.toLowerCase().contains('youtube')) {
      songArtist = defaultArtist.isNotEmpty ? defaultArtist : 'Music Artist';
    }

    // Clean VEVO or Channel suffix from artist
    songArtist = songArtist.replaceAll(RegExp(r'VEVO|Official|Topic', caseSensitive: false), '').trim();
    if (songArtist.isEmpty) songArtist = 'Music Artist';

    return {
      'title': songTitle.isNotEmpty ? songTitle : cleaned,
      'artist': songArtist,
    };
  }

  String _cleanSongTitle(String title) {
    return parseTitleAndArtist(title)['title'] ?? title;
  }

  Future<List<YouTubeVideoItem>> search(String query) async {
    query = query.trim();
    if (query.isEmpty) return [];

    try {
      final searchList = await _yt.search.search(query).timeout(const Duration(seconds: 8));
      final results = <YouTubeVideoItem>[];
      for (final v in searchList.take(25)) {
        results.add(YouTubeVideoItem(
          id: v.id.value,
          title: _cleanSongTitle(v.title),
          channel: v.author,
          duration: v.duration != null
              ? '${v.duration!.inMinutes}:${(v.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
              : '03:45',
          views: '${(v.engagement.viewCount / 1000000).toStringAsFixed(1)}M',
          thumbnailUrl: v.thumbnails.mediumResUrl,
          url: v.url,
        ));
      }
      if (results.isNotEmpty) {
        return results;
      }
    } catch (_) {}

    // Dynamic offline fallback: search matching tracks from the local downloaded vault
    final localTracks = await StorageService.instance.loadTracks();
    final qLower = query.toLowerCase();
    final matched = localTracks.where((t) =>
      t.title.toLowerCase().contains(qLower) || t.artist.toLowerCase().contains(qLower)
    ).toList();

    return matched.map((t) => YouTubeVideoItem(
      id: t.id,
      title: t.title,
      channel: t.artist,
      duration: t.durationFormatted,
      views: 'Offline',
      thumbnailUrl: t.thumbnailUrl ?? 'https://img.youtube.com/vi/${t.id}/hqdefault.jpg',
      url: 'https://www.youtube.com/watch?v=${t.id}',
    )).toList();
  }

  Future<Video?> getVideo(String videoId) async {
    try {
      return await _yt.videos.get(videoId);
    } catch (_) {
      return null;
    }
  }

  Future<int> getAudioDuration(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final dur = await _nativeYtDlp.invokeMethod<int>('getAudioDuration', {'path': filePath});
        return dur ?? 0;
      } catch (_) {}
    }
    return 0;
  }

  Future<void> upgradeLegacyTrackNames() async {
    final storage = StorageService.instance;
    final tracks = await storage.loadTracks();
    bool changed = false;

    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];

      // Purge any old synthesized fake beep .wav files from previous versions
      if (t.filePath.endsWith('.wav')) {
        try {
          final oldFile = File(t.filePath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        } catch (_) {}
      }

      final needsUpgrade = t.title.startsWith('YouTube Audio') ||
          t.title.startsWith('YouTube_Audio') ||
          t.title.startsWith('Track ') ||
          t.title.startsWith('Track_') ||
          t.title.startsWith('Song ') ||
          t.title.startsWith('Song_') ||
          t.title == 'Audio Track' ||
          t.title == 'Song' ||
          t.title == 'Fetching title...' ||
          t.title.contains('_') ||
          t.durationSecs <= 0 ||
          RegExp(r'^[a-zA-Z0-9_-]{10,12}$').hasMatch(t.title) ||
          t.artist == 'Chitauri Audio' ||
          t.artist == 'YouTube' ||
          t.artist == 'YouTube Channel' ||
          t.artist == 'YouTube Artist' ||
          t.artist.startsWith('YouTube') ||
          t.artist == 'Local Music' ||
          t.filePath.contains('YouTube_Audio_');

      if (needsUpgrade) {
        try {
          var realDuration = t.durationSecs;
          if (realDuration <= 0) {
            realDuration = await getAudioDuration(t.filePath);
          }
          final cleanVidId = RegExp(r'[a-zA-Z0-9_-]{11}').firstMatch(t.id)?.group(0) ??
                             RegExp(r'_([a-zA-Z0-9_-]{11})\.').firstMatch(t.filePath)?.group(1) ??
                             t.id;
          final meta = await fetchVideoMetadata(cleanVidId);
          final newTitle = meta['title'];
          final newArtist = meta['artist'];
          final newDesc = meta['description'] ?? t.description;
          var newPath = t.filePath;

          // Rename physical file if it has YouTube_Audio_ in its name
          final file = File(t.filePath);
          if (await file.exists() && file.path.contains('YouTube_Audio_')) {
            final cleanName = (newTitle ?? t.title)
                .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
                .replaceAll(' ', '_')
                .trim();
            final ext = file.path.split('.').last;
            final targetPath = '${file.parent.path}/${cleanName}_$cleanVidId.$ext';
            try {
              final targetFile = File(targetPath);
              if (await targetFile.exists()) {
                await targetFile.delete();
              }
              final renamed = await file.rename(targetPath);
              newPath = renamed.path;
            } catch (_) {}
          }

          if ((newTitle != null && newTitle.isNotEmpty) || realDuration > 0) {
            tracks[i] = Track(
              id: cleanVidId,
              title: (newTitle != null && newTitle.isNotEmpty && newTitle != 'Song') ? newTitle : t.title.replaceAll('_', ' '),
              artist: (newArtist != null && newArtist.isNotEmpty && !newArtist.startsWith('YouTube') && newArtist != 'Local Music') ? newArtist : t.artist,
              filePath: newPath,
              durationSecs: realDuration > 0 ? realDuration : t.durationSecs,
              fileSize: await File(newPath).exists() ? await File(newPath).length() : t.fileSize,
              thumbnailUrl: meta['thumbnail'] ?? t.thumbnailUrl,
              description: newDesc,
            );
            changed = true;
            AudioPlayerService.instance.updateTrackMetadata(tracks[i]);
          }
        } catch (_) {}
      }
    }

    if (changed) {
      await storage.saveTracks(tracks);
    }
  }

  Future<File> _safeMoveFile(File source, File destination) async {
    try {
      if (await destination.exists()) {
        await destination.delete();
      }
      return await source.rename(destination.path);
    } catch (_) {
      await source.copy(destination.path);
      try {
        await source.delete();
      } catch (_) {}
      return destination;
    }
  }

  Future<bool> killProcess(String processId) async {
    try {
      if (Platform.isAndroid) {
        final res = await _nativeYtDlp.invokeMethod<bool>('killProcess', {'processId': processId});
        return res ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Track> downloadAudio(
    String videoId, {
    int? pid,
    String? processId,
    String? title,
    String? channel,
    void Function(String title, String artist)? onMetadataResolved,
    required void Function(double progress, String statusText) onProgress,
  }) async {
    final storage = StorageService.instance;
    final musicDir = await storage.getMusicDir();
    final rawVideoId = RegExp(r'[a-zA-Z0-9_-]{11}').firstMatch(videoId)?.group(0) ?? videoId;
    final procId = processId ?? (pid != null ? 'PID_${pid}_$rawVideoId' : '${rawVideoId}_${DateTime.now().millisecondsSinceEpoch}');

    // 1. Fetch accurate metadata if missing or placeholder
    String? description;
    if (title == null ||
        title.isEmpty ||
        title == 'Fetching title...' ||
        title.startsWith('YouTube Audio') ||
        title.startsWith('Track ') ||
        title.startsWith('Song ') ||
        title.startsWith('Song_') ||
        channel == null ||
        channel.isEmpty ||
        channel.startsWith('YouTube') ||
        channel == 'Chitauri Audio') {
      onProgress(0.03, 'Fetching song details...');
      final meta = await fetchVideoMetadata(rawVideoId);
      if (meta['title'] != null && meta['title']!.isNotEmpty && meta['title'] != 'Song') {
        title = meta['title'];
      }
      if (meta['artist'] != null && meta['artist']!.isNotEmpty && meta['artist'] != 'Music Artist') {
        channel = meta['artist'];
      }
      description = meta['description'];
      onMetadataResolved?.call(title ?? 'Audio Track', channel ?? 'Music Artist');
    }

    String safeBase = (title ?? 'Song')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (safeBase.length > 50) {
      safeBase = safeBase.substring(0, 50).trim();
    }
    safeBase = safeBase.replaceAll(RegExp(r'[.\s_]+$'), '').trim();
    if (safeBase.isEmpty) safeBase = 'Song';

    final fileBaseName = '${safeBase}_$rawVideoId';
    final targetM4a = File('${musicDir.path}/$fileBaseName.m4a');

    int durationSecs = 0;
    try {
      final quickYt = YoutubeExplode();
      try {
        final vid = await quickYt.videos.get(rawVideoId).timeout(const Duration(seconds: 4));
        if (vid.duration != null && vid.duration!.inSeconds > 0) {
          durationSecs = vid.duration!.inSeconds;
        }
        if (description == null || description.isEmpty) {
          description = vid.description;
        }
      } finally {
        quickYt.close();
      }
    } catch (_) {}

    onProgress(0.06, '6%');

    // Notify Android Foreground Service to hold WakeLock and show ongoing notification
    if (Platform.isAndroid) {
      try {
        await _nativeYtDlp.invokeMethod('startDownloadService', {
          'title': title ?? 'Downloading Audio',
        });
      } catch (_) {}
    }

    void reportProgress(double p, String txt) {
      onProgress(p, txt);
      if (Platform.isAndroid) {
        try {
          _nativeYtDlp.invokeMethod('updateDownloadProgress', {
            'title': title ?? 'Downloading Audio',
            'progress': (p * 100).toInt(),
          });
        } catch (_) {}
      }
    }

    try {
      // Permanently download and store thumbnail image on disk alongside songs
      String? localThumbPath;
      try {
        final thumbsDir = Directory('${musicDir.path}/thumbnails');
        if (!await thumbsDir.exists()) {
          await thumbsDir.create(recursive: true);
        }
        final targetThumb = File('${thumbsDir.path}/$rawVideoId.jpg');
        if (await targetThumb.exists() && await targetThumb.length() > 1000) {
          localThumbPath = targetThumb.path;
        } else {
          final urls = [
            'https://img.youtube.com/vi/$rawVideoId/maxresdefault.jpg',
            'https://img.youtube.com/vi/$rawVideoId/hqdefault.jpg',
            'https://img.youtube.com/vi/$rawVideoId/mqdefault.jpg',
          ];
          for (final u in urls) {
            try {
              final res = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 4));
              if (res.statusCode == 200 && res.bodyBytes.length > 1000) {
                await targetThumb.writeAsBytes(res.bodyBytes, flush: true);
                localThumbPath = targetThumb.path;
                if (videoId != rawVideoId) {
                  try {
                    await File('${thumbsDir.path}/$videoId.jpg').writeAsBytes(res.bodyBytes, flush: true);
                  } catch (_) {}
                }
                break;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}

      // Helper for verifying and registering any successfully downloaded file
      Future<Track?> verifyAndRegister(String filePath, String formatName) async {
        final file = File(filePath);
        if (await file.exists() && await file.length() >= 50000) {
          reportProgress(0.98, '98%');

          var finalDuration = durationSecs;
          if (finalDuration <= 0) {
            try {
              final dur = await getAudioDuration(file.path);
              if (dur > 0) finalDuration = dur;
            } catch (_) {}
          }

          final track = Track(
            id: videoId,
            title: title ?? safeBase.replaceAll('_', ' '),
            artist: (channel != null && channel.isNotEmpty && !channel.startsWith('YouTube')) ? channel : 'Music Artist',
            filePath: file.path,
            durationSecs: finalDuration,
            fileSize: await file.length(),
            thumbnailUrl: localThumbPath ?? 'https://img.youtube.com/vi/$rawVideoId/hqdefault.jpg',
            description: description,
          );
          await storage.addTrack(track);
          reportProgress(1.0, '100%');
          return track;
        }
        return null;
      }

      // =========================================================================
      // METHOD 1 (FIRST): Authenticated Direct Stream Engine (~3.2MB AAC / itag 140)
      // High-speed direct client stream: downloads in 3-4 seconds!
      // =========================================================================
      final tempDownloading1 = File('${musicDir.path}/.dl1_${rawVideoId}_${DateTime.now().microsecondsSinceEpoch}.tmp');
      YoutubeExplode? localYt;
      try {
        reportProgress(0.12, '12%');
        localYt = await getAuthenticatedYt(rawVideoId);
        StreamManifest? manifest;
        try {
          manifest = await localYt.videos.streamsClient.getManifest(
            rawVideoId,
            ytClients: [
              YoutubeApiClient.androidMusic,
              YoutubeApiClient.tv,
              YoutubeApiClient.ios,
            ],
            requireWatchPage: false,
          ).timeout(const Duration(seconds: 15));
        } catch (_) {
          manifest = await localYt.videos.streamsClient.getManifest(rawVideoId).timeout(
            const Duration(seconds: 20),
          );
        }
        if (manifest.audioOnly.isNotEmpty) {
          final audioStreams = manifest.audioOnly;
          final streamInfo = audioStreams.firstWhere(
            (s) => s.tag == 140, // 128kbps AAC (~3.2MB)
            orElse: () => audioStreams.firstWhere(
              (s) => s.container.name.toLowerCase() == 'mp4' || s.container.name.toLowerCase() == 'm4a',
              orElse: () => audioStreams.withHighestBitrate(),
            ),
          );

          reportProgress(0.20, '20%');
          final stream = localYt.videos.streamsClient.get(streamInfo);
          final timedStream = stream.timeout(
            const Duration(seconds: 25),
            onTimeout: (sink) => sink.addError(TimeoutException('Stream stalled')),
          );

          IOSink? sink;
          try {
            sink = tempDownloading1.openWrite();
            int received = 0;
            final total = streamInfo.size.totalBytes;
            int lastProgressUpdate = DateTime.now().millisecondsSinceEpoch;

            await Future.sync(() async {
              await for (final chunk in timedStream) {
                sink!.add(chunk);
                received += chunk.length;
                final now = DateTime.now().millisecondsSinceEpoch;
                if (total > 0 && (now - lastProgressUpdate > 100)) {
                  lastProgressUpdate = now;
                  final ratio = (0.20 + (received / total) * 0.75).clamp(0.20, 0.95);
                  reportProgress(ratio, '${(ratio * 100).toInt()}%');
                }
              }
              await sink!.flush();
            }).timeout(const Duration(seconds: 60));
          } finally {
            await sink?.close();
          }

          if (await tempDownloading1.exists() && await tempDownloading1.length() >= 50000) {
            final destFile = streamInfo.container.name.toLowerCase() == 'webm'
                ? File('${musicDir.path}/$fileBaseName.webm')
                : targetM4a;
            final finalFile = await _safeMoveFile(tempDownloading1, destFile);
            final track = await verifyAndRegister(finalFile.path, 'AAC');
            if (track != null) return track;
          }
        }
      } catch (e1) {
        debugPrint('Method 1 fallback: $e1 -> Trying Method 2 (Bounded Chunked HTTP Range Stream)');
        try {
          if (await tempDownloading1.exists()) {
            await tempDownloading1.delete();
          }
        } catch (_) {}
      } finally {
        localYt?.close();
      }

      // =========================================================================
      // METHOD 2 (SECOND): Authenticated Bounded Chunked HTTP Range Stream (~3.2MB)
      // =========================================================================
      final tempDownloading2 = File('${musicDir.path}/.dl2_${rawVideoId}_${DateTime.now().microsecondsSinceEpoch}.tmp');
      YoutubeExplode? clientYt;
      try {
        reportProgress(0.25, '25%');
        clientYt = await getAuthenticatedYt(rawVideoId);
        StreamManifest? manifest2;
        try {
          manifest2 = await clientYt.videos.streamsClient.getManifest(
            rawVideoId,
            ytClients: [
              YoutubeApiClient.tv,
              YoutubeApiClient.androidMusic,
            ],
            requireWatchPage: false,
          ).timeout(const Duration(seconds: 15));
        } catch (_) {
          manifest2 = await clientYt.videos.streamsClient.getManifest(rawVideoId).timeout(
            const Duration(seconds: 20),
          );
        }
        if (manifest2.audioOnly.isEmpty) {
          throw Exception('No audio streams in manifest 2');
        }
        final audioStreams2 = manifest2.audioOnly;
        final bestAudio = audioStreams2.firstWhere(
          (s) => s.tag == 140,
          orElse: () => audioStreams2.withHighestBitrate(),
        );

        final totalBytes = bestAudio.size.totalBytes;
        final cookies = await getSessionCookies(rawVideoId);
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        const chunkSize = 512 * 1024; // 512KB bounded chunks (guarantees HTTP 206 Partial Content)
        int downloaded = 0;

        IOSink? sink;
        try {
          sink = tempDownloading2.openWrite();
          int lastProgressUpdate = DateTime.now().millisecondsSinceEpoch;

          while (downloaded < totalBytes) {
            final end = (downloaded + chunkSize - 1) < totalBytes
                ? (downloaded + chunkSize - 1)
                : (totalBytes - 1);
            final req = await client.getUrl(bestAudio.url).timeout(const Duration(seconds: 10));
            req.headers.set('User-Agent', modernUserAgent);
            req.headers.set('Range', 'bytes=$downloaded-$end');
            if (cookies.isNotEmpty) {
              req.headers.set('Cookie', cookies);
            }

            final resp = await req.close().timeout(const Duration(seconds: 10));
            if (resp.statusCode != 200 && resp.statusCode != 206) {
              break;
            }

            await for (final chunk in resp) {
              sink.add(chunk);
              downloaded += chunk.length;
            }

            final now = DateTime.now().millisecondsSinceEpoch;
            if (totalBytes > 0 && (now - lastProgressUpdate > 100)) {
              lastProgressUpdate = now;
              final ratio = (0.25 + (downloaded / totalBytes) * 0.70).clamp(0.25, 0.95);
              reportProgress(ratio, '${(ratio * 100).toInt()}%');
            }
          }
          await sink.flush();
        } finally {
          await sink?.close();
          client.close();
        }

        if (await tempDownloading2.exists() && await tempDownloading2.length() >= 50000) {
          final finalFile = await _safeMoveFile(tempDownloading2, targetM4a);
          final track = await verifyAndRegister(finalFile.path, 'CDN AAC');
          if (track != null) return track;
        }
      } catch (e2) {
        debugPrint('Method 2 fallback error: $e2 -> Trying Method 3 (Native yt-dlp Engine)');
        try {
          if (await tempDownloading2.exists()) {
            await tempDownloading2.delete();
          }
        } catch (_) {}
      } finally {
        clientYt?.close();
      }

      // =========================================================================
      // METHOD 3 (THIRD): Native yt-dlp Audio Engine
      // =========================================================================
      if (Platform.isAndroid) {
        try {
          _activeNativeVideoId = videoId;
          _activeNativeProgressCallback = reportProgress;
          reportProgress(0.08, '8%');
          final res3 = await _nativeYtDlp.invokeMapMethod<String, dynamic>('downloadMp3', {
            'processId': procId,
            'videoId': rawVideoId,
            'title': fileBaseName,
            'url': 'https://www.youtube.com/watch?v=$rawVideoId',
            'outputDir': musicDir.path,
            'convertToMp3': !isFastMode,
            'fastMode': isFastMode,
          }).timeout(const Duration(seconds: 180));

          if (res3 != null && res3['success'] == true) {
            final filePath = res3['filePath'] as String;
            final nativeDur = (res3['durationSecs'] as num?)?.toInt() ?? 0;
            if (nativeDur > 0) {
              durationSecs = nativeDur;
            }
            final track = await verifyAndRegister(filePath, 'FFmpeg MP3');
            if (track != null) return track;
          }
        } catch (e3) {
          debugPrint('Method 3 (Native yt-dlp) error: $e3');
        } finally {
          _activeNativeVideoId = null;
          _activeNativeProgressCallback = null;
        }
      }

      throw Exception('Download failed across all methods for "$title". Please check network connection.');
    } finally {
      if (Platform.isAndroid) {
        try {
          await _nativeYtDlp.invokeMethod('stopDownloadService');
        } catch (_) {}
      }
    }
  }

  /// One-Tap ytsearch1: background MP3 extraction hook for Telugu catalog recommendations
  Future<Track> downloadTeluguRecommendation(
    TeluguSong song, {
    void Function(double progress, String statusText)? onProgress,
  }) async {
    final storage = StorageService.instance;
    final musicDir = await storage.getMusicDir();
    final procId = '${song.id}_${DateTime.now().millisecondsSinceEpoch}';

    void reportProgress(double p, String txt) {
      onProgress?.call(p, txt);
      _emitDownloadProgress(DownloadProgressEvent(
        songId: song.id,
        title: '${song.title} - ${song.movie}',
        progress: p,
        statusText: txt,
      ));
      if (Platform.isAndroid) {
        try {
          _nativeYtDlp.invokeMethod('updateDownloadProgress', {
            'title': '${song.title} (${song.movie})',
            'progress': (p * 100).toInt(),
          });
        } catch (_) {}
      }
    }

    reportProgress(0.05, 'Starting...');

    if (Platform.isAndroid) {
      try {
        await _nativeYtDlp.invokeMethod('startDownloadService', {
          'title': '${song.title} (${song.movie})',
        });
      } catch (_) {}
    }

    try {
      if (Platform.isAndroid) {
        try {
          _activeNativeVideoId = song.id;
          _activeNativeProgressCallback = reportProgress;

          reportProgress(0.08, 'Pre-resolving YouTube stream...');
          final resolved = await preResolveYouTubeVideo(song.searchQuery);
          final targetUrl = resolved?.watchUrl ?? (song.id.length == 11 ? 'https://www.youtube.com/watch?v=${song.id}' : song.searchQuery);
          final targetVideoId = resolved?.videoId ?? song.id;
          final resolvedThumb = resolved?.thumbnailUrl ?? song.bannerUrl ?? 'https://i.ytimg.com/vi/$targetVideoId/hqdefault.jpg';

          reportProgress(0.15, 'Starting native audio stream...');

          final res = await _nativeYtDlp.invokeMapMethod<String, dynamic>('downloadMp3', {
            'processId': procId,
            'videoId': targetVideoId,
            'title': song.cleanTitle,
            'outputFileName': song.outputFileName,
            'url': targetUrl,
            'outputDir': musicDir.path,
            'convertToMp3': false,
            'fastMode': true,
            'matchFilter': 'duration > 90 & duration < 540',
            'embedMetadata': true,
          }).timeout(const Duration(seconds: 180));

          if (res != null && res['success'] == true) {
            final filePath = res['filePath'] as String;
            final nativeDur = (res['durationSecs'] as num?)?.toInt() ?? (resolved?.durationSecs ?? 240);
            final file = File(filePath);

            reportProgress(0.95, 'Saving cover & metadata...');

            final localCover = await storage.cacheCoverImageLocally(song.id, resolvedThumb);
            await storage.saveLibraryMetadataEntry(song.id, {
              'id': song.id,
              'title': song.title,
              'movie': song.movie,
              'composer': song.composer,
              'singers': song.singers,
              'year': song.year,
              'decade': song.decade,
              'mood': song.mood,
              'language': song.language,
              'bannerUrl': resolvedThumb,
              'localCoverPath': localCover,
            });

            reportProgress(0.98, '98%');

            final track = Track(
              id: song.id,
              title: song.title,
              artist: song.subtitle,
              filePath: file.path,
              durationSecs: nativeDur > 0 ? nativeDur : 240,
              fileSize: await file.exists() ? await file.length() : 0,
              thumbnailUrl: localCover ?? resolvedThumb,
              description: '${song.movie} (${song.year}) • Composer: ${song.composer} • Mood: ${song.mood}',
            );

            await storage.addTrack(track);
            await TasteProfiler.instance.recordDownload(song);

            reportProgress(1.0, '100%');
            _emitDownloadProgress(DownloadProgressEvent(
              songId: song.id,
              title: '${song.title} - ${song.movie}',
              progress: 1.0,
              statusText: 'Saved',
              isCompleted: true,
            ));

            return track;
          }
        } catch (nativeErr) {
          debugPrint('Native yt-dlp error: $nativeErr -> Falling back to pure audio stream pipeline');
        }
      }

      // Cross-platform fallback: search query via YoutubeExplode and download audio
      reportProgress(0.15, 'Searching track...');
      final searchResults = await search('${song.title} ${song.movie} ${song.composer} Telugu official audio song');
      if (searchResults.isNotEmpty) {
        // Apply duration filter guardrail: between 120s (2m) and 480s (8m)
        YouTubeVideoItem? selectedVid;
        for (final vid in searchResults) {
          final parts = vid.duration.split(':');
          int secs = 0;
          if (parts.length == 2) {
            secs = (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
          } else if (parts.length == 3) {
            secs = (int.tryParse(parts[0]) ?? 0) * 3600 + (int.tryParse(parts[1]) ?? 0) * 60 + (int.tryParse(parts[2]) ?? 0);
          }
          if (secs >= 120 && secs <= 480) {
            selectedVid = vid;
            break;
          }
        }
        selectedVid ??= searchResults.first;

        final track = await downloadAudio(
          selectedVid.id,
          title: song.title,
          channel: song.subtitle,
          onProgress: reportProgress,
        );

        await TasteProfiler.instance.recordDownload(song);
        _emitDownloadProgress(DownloadProgressEvent(
          songId: song.id,
          title: '${song.title} - ${song.movie}',
          progress: 1.0,
          statusText: 'Saved',
          isCompleted: true,
        ));
        return track;
      }

      throw Exception('Could not find matching audio for "${song.title} - ${song.movie}"');
    } catch (e) {
      _emitDownloadProgress(DownloadProgressEvent(
        songId: song.id,
        title: '${song.title} - ${song.movie}',
        progress: 0.0,
        statusText: 'Failed',
        isFailed: true,
      ));
      rethrow;
    } finally {
      _activeNativeVideoId = null;
      _activeNativeProgressCallback = null;
      if (Platform.isAndroid) {
        try {
          await _nativeYtDlp.invokeMethod('stopDownloadService');
        } catch (_) {}
      }
    }
  }
}
