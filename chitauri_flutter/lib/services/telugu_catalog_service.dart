import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/telugu_song.dart';
import 'open_catalog_service.dart';

class TeluguCatalogService {
  static final TeluguCatalogService instance = TeluguCatalogService._internal();
  TeluguCatalogService._internal();

  /// Configurable base URL for sharded JSON catalog hosting (CDN / GitHub Pages / raw)
  String catalogBaseUrl = 'https://raw.githubusercontent.com/chitauri-music/telugu-catalog/main/';

  static const List<String> decades = [
    '1970s',
    '1980s',
    '1990s',
    '2000s',
    '2010s',
    '2020s',
  ];

  static const List<String> regionalLanguages = [
    'telugu',
    'tamil',
    'malayalam',
    'kannada',
    'hindi',
  ];

  final Map<String, List<TeluguSong>> _decadeShards = {};
  bool _isInitialized = false;

  /// In-memory all songs cached across all decades
  List<TeluguSong> _allSongs = [];

  List<TeluguSong> get allSongs => List.unmodifiable(_allSongs);

  /// Top 30+ iconic Telugu songs across 1970s–2020s (Fallback Seed)
  static const List<Map<String, dynamic>> fallbackSeedJson = [
    // 1970s
    {
      "id": "tel_1980_sankarabharanam_01",
      "title": "Omkaara Naadaanusandhaanamou",
      "movie": "Sankarabharanam",
      "year": 1980,
      "decade": "1970s",
      "composer": "K. V. Mahadevan",
      "singers": ["S. P. Balasubrahmanyam", "S. Janaki"],
      "mood": "Classical",
      "popularity": 98
    },
    {
      "id": "tel_1971_missamma_01",
      "title": "RaaVoyi Chandamama",
      "movie": "Missamma",
      "year": 1971,
      "decade": "1970s",
      "composer": "S. Rajeswara Rao",
      "singers": ["Ghantasala", "P. Susheela"],
      "mood": "Melody",
      "popularity": 94
    },
    {
      "id": "tel_1976_sirisirimuvva_01",
      "title": "Jhummandi Naadam",
      "movie": "Siri Siri Muvva",
      "year": 1976,
      "decade": "1970s",
      "composer": "K. V. Mahadevan",
      "singers": ["S. P. Balasubrahmanyam", "P. Susheela"],
      "mood": "Classical",
      "popularity": 96
    },
    {
      "id": "tel_1972_jagadekaveerunika_01",
      "title": "Siva Sankari",
      "movie": "Jagadeka Veeruni Katha",
      "year": 1972,
      "decade": "1970s",
      "composer": "Pendyala Nageswara Rao",
      "singers": ["Ghantasala"],
      "mood": "Classical",
      "popularity": 95
    },
    {
      "id": "tel_1979_meghasandesam_01",
      "title": "Aakulo Aakunai",
      "movie": "Megha Sandesam",
      "year": 1979,
      "decade": "1970s",
      "composer": "Ramesh Naidu",
      "singers": ["K. J. Yesudas", "P. Susheela"],
      "mood": "Melody",
      "popularity": 93
    },

    // 1980s
    {
      "id": "tel_1981_seethakokachilu_01",
      "title": "Maate Mantramu",
      "movie": "Seethakoka Chiluka",
      "year": 1981,
      "decade": "1980s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam", "S. P. Sailaja"],
      "mood": "Melody",
      "popularity": 97
    },
    {
      "id": "tel_1983_sagarasangamam_01",
      "title": "Takita Tadimi",
      "movie": "Sagara Sangamam",
      "year": 1983,
      "decade": "1980s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam"],
      "mood": "Classical",
      "popularity": 99
    },
    {
      "id": "tel_1986_swathimuthyam_01",
      "title": "Suvvi Suvvi Suvvalamma",
      "movie": "Swathi Muthyam",
      "year": 1986,
      "decade": "1980s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam", "S. Janaki"],
      "mood": "Melody",
      "popularity": 96
    },
    {
      "id": "tel_1989_geethanjali_01",
      "title": "Aamani Paadave",
      "movie": "Geethanjali",
      "year": 1989,
      "decade": "1980s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam"],
      "mood": "Melody",
      "popularity": 99
    },
    {
      "id": "tel_1985_anveshana_01",
      "title": "Keeravani Raagamlo",
      "movie": "Anveshana",
      "year": 1985,
      "decade": "1980s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam", "S. Janaki"],
      "mood": "Melody",
      "popularity": 97
    },

    // 1990s
    {
      "id": "tel_1991_aditya369_01",
      "title": "Jaanavule Nerajaanavule",
      "movie": "Aditya 369",
      "year": 1991,
      "decade": "1990s",
      "composer": "Ilaiyaraaja",
      "singers": ["S. P. Balasubrahmanyam", "Jikki"],
      "mood": "Melody",
      "popularity": 96
    },
    {
      "id": "tel_1991_kshanakhsanam_01",
      "title": "Jaamu Raathiri",
      "movie": "Kshana Kshanam",
      "year": 1991,
      "decade": "1990s",
      "composer": "M. M. Keeravani",
      "singers": ["S. P. Balasubrahmanyam", "K. S. Chithra"],
      "mood": "Melody",
      "popularity": 98
    },
    {
      "id": "tel_1995_criminal_01",
      "title": "Telusa Manasa",
      "movie": "Criminal",
      "year": 1995,
      "decade": "1990s",
      "composer": "M. M. Keeravani",
      "singers": ["S. P. Balasubrahmanyam", "K. S. Chithra"],
      "mood": "Romantic",
      "popularity": 97
    },
    {
      "id": "tel_1999_kushi_01",
      "title": "Premante Suluvukadura",
      "movie": "Kushi",
      "year": 1999,
      "decade": "1990s",
      "composer": "Mani Sharma",
      "singers": ["Devan Ekambaram", "Kalpana"],
      "mood": "Melody",
      "popularity": 95
    },
    {
      "id": "tel_1991_killer_01",
      "title": "Priya Priyathama",
      "movie": "Killer",
      "year": 1991,
      "decade": "1990s",
      "composer": "Ilaiyaraaja",
      "singers": ["Mano", "K. S. Chithra"],
      "mood": "Romantic",
      "popularity": 95
    },

    // 2000s
    {
      "id": "tel_2003_okkadu_01",
      "title": "Cheppave Chirugali",
      "movie": "Okkadu",
      "year": 2003,
      "decade": "2000s",
      "composer": "Mani Sharma",
      "singers": ["Udit Narayan", "Sujatha Mohan"],
      "mood": "Melody",
      "popularity": 99
    },
    {
      "id": "tel_2005_athadu_01",
      "title": "Pilichina Ranantava",
      "movie": "Athadu",
      "year": 2005,
      "decade": "2000s",
      "composer": "Mani Sharma",
      "singers": ["Karthik", "Kavita Krishnamurthy"],
      "mood": "Melody",
      "popularity": 98
    },
    {
      "id": "tel_2005_nuvvostananten_01",
      "title": "Nuvvostanante Nenoddantana",
      "movie": "Nuvvostanante Nenoddantana",
      "year": 2005,
      "decade": "2000s",
      "composer": "Devi Sri Prasad",
      "singers": ["Shankar Mahadevan", "Gopika Poornima"],
      "mood": "Melody",
      "popularity": 97
    },
    {
      "id": "tel_2008_jalsa_01",
      "title": "My Heart Is Beating",
      "movie": "Jalsa",
      "year": 2008,
      "decade": "2000s",
      "composer": "Devi Sri Prasad",
      "singers": ["KK"],
      "mood": "Romantic",
      "popularity": 99
    },
    {
      "id": "tel_2008_kothabangaru_01",
      "title": "Kotha Bangaru Lokam",
      "movie": "Kotha Bangaru Lokam",
      "year": 2008,
      "decade": "2000s",
      "composer": "Mickey J. Meyer",
      "singers": ["Karthik", "Shreya Ghoshal"],
      "mood": "Melody",
      "popularity": 96
    },

    // 2010s
    {
      "id": "tel_2012_endukanteprem_01",
      "title": "Nee Choopule",
      "movie": "Endukante Premanta",
      "year": 2012,
      "decade": "2010s",
      "composer": "G. V. Prakash Kumar",
      "singers": ["Haricharan", "K. S. Chithra"],
      "mood": "Romantic",
      "popularity": 96
    },
    {
      "id": "tel_2013_seethammavaki_01",
      "title": "Aaradugulauntada",
      "movie": "Seethamma Vakitlo Sirimalle Chettu",
      "year": 2013,
      "decade": "2010s",
      "composer": "Mickey J. Meyer",
      "singers": ["Karthik"],
      "mood": "Melody",
      "popularity": 96
    },
    {
      "id": "tel_2018_geethagovinda_01",
      "title": "Inkem Inkem Inkem Kaavaale",
      "movie": "Geetha Govindam",
      "year": 2018,
      "decade": "2010s",
      "composer": "Gopi Sundar",
      "singers": ["Sid Sriram"],
      "mood": "Romantic",
      "popularity": 99
    },
    {
      "id": "tel_2018_rx100_01",
      "title": "Pilla Raa",
      "movie": "RX 100",
      "year": 2018,
      "decade": "2010s",
      "composer": "Chaitan Bharadwaj",
      "singers": ["Anurag Kulkarni"],
      "mood": "Romantic",
      "popularity": 97
    },
    {
      "id": "tel_2019_majili_01",
      "title": "Priyathama Priyathama",
      "movie": "Majili",
      "year": 2019,
      "decade": "2010s",
      "composer": "Gopi Sundar",
      "singers": ["Chinmayi"],
      "mood": "Melody",
      "popularity": 96
    },

    // 2020s
    {
      "id": "tel_2020_alavaikunthap_01",
      "title": "Samajavaragamana",
      "movie": "Ala Vaikunthapurramuloo",
      "year": 2020,
      "decade": "2020s",
      "composer": "Thaman S",
      "singers": ["Sid Sriram"],
      "mood": "Melody",
      "popularity": 99
    },
    {
      "id": "tel_2020_alavaikunthap_02",
      "title": "Butta Bomma",
      "movie": "Ala Vaikunthapurramuloo",
      "year": 2020,
      "decade": "2020s",
      "composer": "Thaman S",
      "singers": ["Armaan Malik"],
      "mood": "Peppy",
      "popularity": 99
    },
    {
      "id": "tel_2021_pushpathe_01",
      "title": "Srivalli",
      "movie": "Pushpa: The Rise",
      "year": 2021,
      "decade": "2020s",
      "composer": "Devi Sri Prasad",
      "singers": ["Sid Sriram"],
      "mood": "Melody",
      "popularity": 98
    },
    {
      "id": "tel_2022_rrr_01",
      "title": "Naatu Naatu",
      "movie": "RRR",
      "year": 2022,
      "decade": "2020s",
      "composer": "M. M. Keeravani",
      "singers": ["Rahul Sipligunj", "Kaala Bhairava"],
      "mood": "Mass / Folk",
      "popularity": 99
    },
    {
      "id": "tel_2023_hinanna_01",
      "title": "Samayama",
      "movie": "Hi Nanna",
      "year": 2023,
      "decade": "2020s",
      "composer": "Hesham Abdul Wahab",
      "singers": ["Anurag Kulkarni", "Sithara Krishnakumar"],
      "mood": "Romantic",
      "popularity": 98
    },
    {
      "id": "tel_2024_gunturkaaram_01",
      "title": "Kurchi Madathapetti",
      "movie": "Guntur Kaaram",
      "year": 2024,
      "decade": "2020s",
      "composer": "Thaman S",
      "singers": ["Sri Krishna", "Sahithi Chaganti"],
      "mood": "Mass / Folk",
      "popularity": 98
    },
    {
      "id": "tel_2024_devarapart_01",
      "title": "Chuttamalle",
      "movie": "Devara: Part 1",
      "year": 2024,
      "decade": "2020s",
      "composer": "Anirudh Ravichander",
      "singers": ["Shilpa Rao"],
      "mood": "Romantic",
      "popularity": 99
    },
  ];

  /// Get or create local cache directory for catalog shards
  Future<Directory> _getCacheDirectory() async {
    Directory base;
    try {
      base = await getApplicationCacheDirectory();
    } catch (_) {
      base = await getTemporaryDirectory();
    }
    final catalogDir = Directory('${base.path}/telugu_catalog');
    if (!await catalogDir.exists()) {
      await catalogDir.create(recursive: true);
    }
    return catalogDir;
  }

  /// Initial load: reads from asset bundle and disk cache first, or populates with fallback seed
  Future<List<TeluguSong>> initializeCatalog() async {
    if (_isInitialized && _allSongs.isNotEmpty) {
      return _allSongs;
    }

    final cacheDir = await _getCacheDirectory();
    final combined = <TeluguSong>[];

    // 1. Try reading sharded catalogs across all regional languages and decades
    for (final lang in regionalLanguages) {
      for (final decade in decades) {
        final shardFileName = '${lang}_$decade.json';
        final cachedFile = File('${cacheDir.path}/$shardFileName');
        bool shardLoaded = false;

        // Try local disk cache
        if (await cachedFile.exists()) {
          try {
            final content = await cachedFile.readAsString();
            final list = jsonDecode(content) as List<dynamic>;
            final songs = list.map((e) => TeluguSong.fromJson(e as Map<String, dynamic>)).toList();
            if (songs.isNotEmpty) {
              _decadeShards.putIfAbsent(decade, () => []).addAll(songs);
              combined.addAll(songs);
              shardLoaded = true;
            }
          } catch (e) {
            debugPrint('Error reading cached shard $shardFileName: $e');
          }
        }

        // Try bundled flutter asset
        if (!shardLoaded) {
          try {
            final assetPath = 'assets/catalog/$shardFileName';
            final content = await rootBundle.loadString(assetPath);
            final list = jsonDecode(content) as List<dynamic>;
            final songs = list.map((e) => TeluguSong.fromJson(e as Map<String, dynamic>)).toList();
            if (songs.isNotEmpty) {
              _decadeShards.putIfAbsent(decade, () => []).addAll(songs);
              combined.addAll(songs);
              shardLoaded = true;
            }
          } catch (_) {
            // Asset might not exist or test environment without rootBundle
          }
        }
      }
    }

    // 2. If no assets or disk cache exists, seed with fallback list
    if (combined.isEmpty) {
      final seedSongs = fallbackSeedJson.map((e) => TeluguSong.fromJson(e)).toList();
      for (final song in seedSongs) {
        _decadeShards.putIfAbsent(song.decade, () => []).add(song);
      }
      combined.addAll(seedSongs);
    }

    // 3. Load cached songs from OpenCatalogService (Telugu & English)
    final openCached = await OpenCatalogService.instance.loadCatalog();
    if (openCached.isNotEmpty) {
      final existingIds = combined.map((s) => s.id).toSet();
      for (final s in openCached) {
        if (!existingIds.contains(s.id)) {
          combined.add(s);
          existingIds.add(s.id);
          _decadeShards.putIfAbsent(s.decade, () => []).add(s);
        }
      }
    }

    _allSongs = combined;
    _isInitialized = true;

    // 4. Trigger asynchronous background refresh from remote catalog & live API
    unawaited(refreshFromCloud());

    return _allSongs;
  }

  /// Asynchronously fetches sharded JSON files over HTTPS with ETag & Last-Modified caching
  Future<void> refreshFromCloud({String language = 'all'}) async {
    final cacheDir = await _getCacheDirectory();
    bool updatedAny = false;

    final client = http.Client();
    try {
      for (final decade in decades) {
        final filename = 'telugu_$decade.json';
        final urlStr = '$catalogBaseUrl$filename';
        final shardFile = File('${cacheDir.path}/$filename');
        final metaFile = File('${cacheDir.path}/meta_$decade.json');

        String? cachedEtag;
        String? cachedLastModified;

        if (await metaFile.exists()) {
          try {
            final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
            cachedEtag = meta['etag'] as String?;
            cachedLastModified = meta['last_modified'] as String?;
          } catch (_) {}
        }

        final headers = <String, String>{
          'User-Agent': 'Chitauri/3.0 OpenCatalog',
        };
        if (cachedEtag != null && cachedEtag.isNotEmpty) {
          headers['If-None-Match'] = cachedEtag;
        }
        if (cachedLastModified != null && cachedLastModified.isNotEmpty) {
          headers['If-Modified-Since'] = cachedLastModified;
        }

        try {
          final response = await client.get(Uri.parse(urlStr), headers: headers).timeout(
            const Duration(seconds: 8),
          );

          if (response.statusCode == 200 && response.body.isNotEmpty) {
            final list = jsonDecode(response.body) as List<dynamic>;
            final songs = list.map((e) => TeluguSong.fromJson(e as Map<String, dynamic>)).toList();

            if (songs.isNotEmpty) {
              await shardFile.writeAsString(response.body, flush: true);
              final newMeta = {
                'etag': response.headers['etag'] ?? '',
                'last_modified': response.headers['last-modified'] ?? '',
                'updated_at': DateTime.now().toIso8601String(),
              };
              await metaFile.writeAsString(jsonEncode(newMeta), flush: true);

              _decadeShards[decade] = songs;
              updatedAny = true;
            }
          } else if (response.statusCode == 304) {
            // Unchanged; cached version is still fresh
            continue;
          }
        } catch (_) {
          // Offline, timeout, or invalid CDN; keep local cache/seed without crashing
        }
      }
    } finally {
      client.close();
    }

    // Also fetch live slice from iTunes Public Search API (keyless, free)
    try {
      final liveSongs = await OpenCatalogService.instance.fetchLiveCatalogSlice(language: language);
      if (liveSongs.isNotEmpty) {
        final existingIds = _allSongs.map((s) => s.id).toSet();
        for (final s in liveSongs) {
          if (!existingIds.contains(s.id)) {
            _allSongs.add(s);
            existingIds.add(s.id);
            _decadeShards.putIfAbsent(s.decade, () => []).add(s);
          }
        }
        updatedAny = true;
      }
    } catch (_) {}

    if (updatedAny) {
      final combined = <TeluguSong>[];
      for (final d in decades) {
        if (_decadeShards.containsKey(d)) {
          combined.addAll(_decadeShards[d]!);
        }
      }
      // Add any open catalog tracks not in standard decade keys
      final seen = combined.map((s) => s.id).toSet();
      for (final s in _allSongs) {
        if (!seen.contains(s.id)) {
          combined.add(s);
          seen.add(s.id);
        }
      }
      _allSongs = combined;
    }
  }

  /// Load next page of live songs as the user scrolls
  Future<List<TeluguSong>> loadMoreLiveSongs({String language = 'all', int offset = 20}) async {
    final fresh = await OpenCatalogService.instance.fetchLiveCatalogSlice(
      language: language,
      offset: offset,
      limit: 30,
    );
    final existingIds = _allSongs.map((s) => s.id).toSet();
    for (final s in fresh) {
      if (!existingIds.contains(s.id)) {
        _allSongs.add(s);
        existingIds.add(s.id);
        _decadeShards.putIfAbsent(s.decade, () => []).add(s);
      }
    }
    return _allSongs;
  }

  /// Filter songs by language ('telugu', 'tamil', 'malayalam', 'kannada', 'hindi', 'english', or 'all')
  List<TeluguSong> getSongsByLanguage(String language) {
    final lang = language.toLowerCase().trim();
    if (lang == 'all' || lang.isEmpty) {
      return _allSongs;
    }
    return _allSongs.where((s) => s.language.toLowerCase() == lang).toList();
  }

  /// Get songs by specific decade
  List<TeluguSong> getSongsByDecade(String decade, {String language = 'all'}) {
    final list = _decadeShards[decade] ?? [];
    final lang = language.toLowerCase().trim();
    if (lang == 'all' || lang.isEmpty) return list;
    return list.where((s) => s.language.toLowerCase() == lang).toList();
  }

  /// Get all songs for retro era (70s & 80s)
  List<TeluguSong> getRetroSongs({String language = 'all'}) {
    return [
      ...getSongsByDecade('1970s', language: language),
      ...getSongsByDecade('1980s', language: language),
    ];
  }

  /// Get all songs for gold era (90s & 2000s)
  List<TeluguSong> getGoldSongs({String language = 'all'}) {
    return [
      ...getSongsByDecade('1990s', language: language),
      ...getSongsByDecade('2000s', language: language),
    ];
  }

  /// Get all songs for modern hits era (2010s & 2020s)
  List<TeluguSong> getModernHits({String language = 'all'}) {
    return [
      ...getSongsByDecade('2010s', language: language),
      ...getSongsByDecade('2020s', language: language),
    ];
  }

  /// Get songs by composer
  List<TeluguSong> getSongsByComposer(String composer, {String language = 'all'}) {
    final cLower = composer.toLowerCase();
    final list = _allSongs.where((s) => s.composer.toLowerCase().contains(cLower)).toList();
    final lang = language.toLowerCase().trim();
    if (lang == 'all' || lang.isEmpty) return list;
    return list.where((s) => s.language.toLowerCase() == lang).toList();
  }
}
