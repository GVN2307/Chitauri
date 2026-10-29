import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/telugu_song.dart';

class OpenCatalogService {
  static final OpenCatalogService instance = OpenCatalogService._internal();
  OpenCatalogService._internal();

  static const String _cacheFileName = 'open_catalog_v3_cache.json';
  final List<TeluguSong> _cachedSongs = [];
  bool _isLoaded = false;
  bool _isFetching = false;

  List<TeluguSong> get cachedSongs => List.unmodifiable(_cachedSongs);

  Future<File> _getCacheFile() async {
    Directory dir;
    try {
      dir = await getApplicationCacheDirectory();
    } catch (_) {
      dir = await getTemporaryDirectory();
    }
    return File('${dir.path}/$_cacheFileName');
  }

  /// Initialize and load cached open catalog from disk
  Future<List<TeluguSong>> loadCatalog() async {
    if (_isLoaded && _cachedSongs.isNotEmpty) {
      return _cachedSongs;
    }

    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          final parsed = list
              .map((e) => TeluguSong.fromJson(e as Map<String, dynamic>))
              .where((s) => s.id.isNotEmpty && s.title.isNotEmpty)
              .toList();
          if (parsed.isNotEmpty) {
            _cachedSongs.clear();
            _cachedSongs.addAll(parsed);
            _isLoaded = true;
          }
        }
      }
    } catch (e) {
      debugPrint('OpenCatalogService disk load error: $e');
    }

    _isLoaded = true;
    return _cachedSongs;
  }

  /// Fetch fresh songs from Apple iTunes Public Search API (Free, Keyless, 600x600 HD banners)
  Future<List<TeluguSong>> fetchLiveCatalogSlice({
    String language = 'all',
    int offset = 0,
    int limit = 50,
  }) async {
    if (_isFetching) return _cachedSongs;
    _isFetching = true;

    final client = http.Client();
    final newSongs = <TeluguSong>[];

    try {
      final endpoints = <Map<String, String>>[];

      if (language == 'telugu' || language == 'all') {
        endpoints.addAll([
          {'country': 'IN', 'term': 'Telugu Hits', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'Telugu Cinema 2024', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'Ilaiyaraaja Telugu', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'M.M. Keeravani Telugu', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'Thaman S Telugu', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'Devi Sri Prasad Telugu', 'lang': 'telugu'},
          {'country': 'IN', 'term': 'Sid Sriram Telugu', 'lang': 'telugu'},
        ]);
      }

      if (language == 'tamil' || language == 'all') {
        endpoints.addAll([
          {'country': 'IN', 'term': 'Tamil Hits', 'lang': 'tamil'},
          {'country': 'IN', 'term': 'Anirudh Tamil', 'lang': 'tamil'},
          {'country': 'IN', 'term': 'A.R. Rahman Tamil', 'lang': 'tamil'},
        ]);
      }

      if (language == 'malayalam' || language == 'all') {
        endpoints.addAll([
          {'country': 'IN', 'term': 'Malayalam Hits', 'lang': 'malayalam'},
          {'country': 'IN', 'term': 'Sushin Shyam Malayalam', 'lang': 'malayalam'},
          {'country': 'IN', 'term': 'Hesham Abdul Wahab Malayalam', 'lang': 'malayalam'},
        ]);
      }

      if (language == 'kannada' || language == 'all') {
        endpoints.addAll([
          {'country': 'IN', 'term': 'Kannada Hits', 'lang': 'kannada'},
          {'country': 'IN', 'term': 'KGF Kannada', 'lang': 'kannada'},
          {'country': 'IN', 'term': 'Ajaneesh Loknath Kannada', 'lang': 'kannada'},
        ]);
      }

      if (language == 'hindi' || language == 'all') {
        endpoints.addAll([
          {'country': 'IN', 'term': 'Bollywood Hits', 'lang': 'hindi'},
          {'country': 'IN', 'term': 'Arijit Singh Hindi', 'lang': 'hindi'},
          {'country': 'IN', 'term': 'Pritam Hindi', 'lang': 'hindi'},
        ]);
      }

      if (language == 'english' || language == 'all') {
        endpoints.addAll([
          {'country': 'US', 'term': 'Pop Hits', 'lang': 'english'},
          {'country': 'US', 'term': 'Synthwave', 'lang': 'english'},
          {'country': 'US', 'term': 'Acoustic Chill', 'lang': 'english'},
          {'country': 'US', 'term': 'Classic Rock 80s', 'lang': 'english'},
          {'country': 'US', 'term': 'R&B Hits', 'lang': 'english'},
        ]);
      }

      for (final ep in endpoints) {
        final country = ep['country']!;
        final term = Uri.encodeComponent(ep['term']!);
        final lang = ep['lang']!;

        // For English anti-crowd discovery: randomize deep offset (20–180) to avoid repeating same Billboard top 10
        final queryOffset = (lang == 'english' && offset == 0)
            ? (20 + (DateTime.now().millisecond % 160))
            : offset;

        final url = Uri.parse(
          'https://itunes.apple.com/search?term=$term&country=$country&media=music&entity=song&limit=30&offset=$queryOffset',
        );

        try {
          final res = await client.get(url, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          }).timeout(const Duration(seconds: 6));

          if (res.statusCode == 200) {
            final decodedBody = utf8.decode(res.bodyBytes);
            final data = jsonDecode(decodedBody) as Map<String, dynamic>;
            final results = data['results'] as List<dynamic>?;
            if (results != null) {
              for (final r in results) {
                if (r is Map) {
                  final song = parseItunesTrack(r, lang);
                  if (song != null) {
                    newSongs.add(song);
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      if (newSongs.isNotEmpty) {
        // Merge without duplicates using normalized dedupe key (${title}_${movie})
        final existingKeys = _cachedSongs.map((s) => s.normalizedDedupeKey).toSet();
        final existingIds = _cachedSongs.map((s) => s.id).toSet();
        for (final s in newSongs) {
          final key = s.normalizedDedupeKey;
          if (!existingIds.contains(s.id) && !existingKeys.contains(key)) {
            _cachedSongs.add(s);
            existingIds.add(s.id);
            existingKeys.add(key);
          }
        }

        // Persist to disk cache
        unawaited(_saveToCache());
      }
    } finally {
      client.close();
      _isFetching = false;
    }

    return _cachedSongs;
  }

  TeluguSong? parseItunesTrack(Map<dynamic, dynamic> item, String lang) {
    final trackId = item['trackId']?.toString().trim();
    final trackName = item['trackName']?.toString().trim();
    final artistName = item['artistName']?.toString().trim() ?? 'Music Artist';
    if (trackId == null || trackName == null || trackName.isEmpty) return null;

    final rawCollection = item['collectionName']?.toString() ?? '';
    final cleanCollection = rawCollection
        .replaceAll(RegExp(r'\s*\((original motion picture soundtrack|soundtrack|single|ep|deluxe)\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*(single|ep|deluxe)$', caseSensitive: false), '')
        .trim();

    final releaseDate = item['releaseDate']?.toString() ?? '2020';
    int year = 2020;
    try {
      year = DateTime.parse(releaseDate).year;
    } catch (_) {
      final yMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(releaseDate);
      if (yMatch != null) {
        year = int.tryParse(yMatch.group(1)!) ?? 2020;
      }
    }

    final decade = year < 1980
        ? '1970s'
        : (year < 1990
            ? '1980s'
            : (year < 2000
                ? '1990s'
                : (year < 2010
                    ? '2000s'
                    : (year < 2020 ? '2010s' : '2020s'))));

    final artwork100 = item['artworkUrl100']?.toString() ?? '';
    final highResBanner = artwork100.isNotEmpty
        ? artwork100.replaceAll('100x100bb', '600x600bb')
        : 'https://img.youtube.com/vi/$trackId/hqdefault.jpg';

    final genre = item['primaryGenreName']?.toString() ?? 'Soundtrack';

    // Infer mood and Tune DNA
    String mood = 'Melody';
    final gLower = genre.toLowerCase();
    if (gLower.contains('pop') || gLower.contains('dance')) {
      mood = 'Peppy';
    } else if (gLower.contains('rock') || gLower.contains('metal')) {
      mood = 'High-Energy Mass / Folk';
    } else if (gLower.contains('soundtrack') || gLower.contains('indian')) {
      mood = 'Melody';
    } else if (gLower.contains('r&b') || gLower.contains('soul')) {
      mood = 'Romantic';
    }

    final tuneDna = TuneDna.infer(mood, genre: genre, year: year);

    // Calculate initial popularity based on trackCount / price / rank
    final pop = 60 + (trackName.hashCode % 35); // 60 to 94 range

    final singers = artistName.split(RegExp(r'[,•&/]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return TeluguSong(
      id: 'itunes_${lang}_$trackId',
      title: trackName,
      movie: cleanCollection.isNotEmpty ? cleanCollection : (lang == 'english' ? 'Global Single' : 'Telugu Track'),
      year: year,
      decade: decade,
      composer: singers.isNotEmpty ? singers.first : artistName,
      singers: singers,
      mood: mood,
      popularity: pop.clamp(50, 95),
      language: lang,
      bannerUrl: highResBanner,
      tempoBucket: tuneDna.tempoBucket,
      vibeCategory: tuneDna.vibeCategory,
      instrumentation: tuneDna.instrumentation,
    );
  }

  Future<void> _saveToCache() async {
    try {
      final file = await _getCacheFile();
      final jsonList = _cachedSongs.map((s) => s.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList), flush: true);
    } catch (e) {
      debugPrint('OpenCatalogService cache write error: $e');
    }
  }
}
