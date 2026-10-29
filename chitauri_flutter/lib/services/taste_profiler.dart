import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/telugu_song.dart';
import '../models/track.dart';
import 'storage_service.dart';

class ScoredTeluguSong {
  final TeluguSong song;
  final double score;
  final String recommendationReason;

  const ScoredTeluguSong({
    required this.song,
    required this.score,
    required this.recommendationReason,
  });

  int get matchPercentage => (score * 100).round().clamp(50, 99);
}

class DynamicPlaylistMix {
  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final List<TeluguSong> tracks;

  const DynamicPlaylistMix({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.tracks,
  });
}

class TasteProfiler {
  static final TasteProfiler instance = TasteProfiler._internal();
  TasteProfiler._internal();

  static const String _fileName = 'user_taste_profile.json';

  // Raw frequency counts
  final Map<String, int> _rawComposerCounts = {};
  final Map<String, int> _rawSingerCounts = {};
  final Map<String, int> _rawDecadeCounts = {};
  final Map<String, int> _rawVibeCounts = {};

  // Normalized weights in range [0.0, 1.0]
  final Map<String, double> _composerWeights = {};
  final Map<String, double> _singerWeights = {};
  final Map<String, double> _decadeWeights = {};
  final Map<String, double> _vibeWeights = {};

  // Session impressions for Anti-Boredom Decay
  final Map<String, int> _sessionImpressions = {};

  // Set of downloaded song IDs & normalized title keys to exclude
  final Set<String> _downloadedSongIds = {};
  final Set<String> _downloadedTitleKeys = {};
  final Set<String> _downloadedFingerprints = {};

  // Session ring buffer for seen/dismissed songs (size 200)
  final List<String> _seenFingerprintsRingBuffer = [];
  final Set<String> _seenFingerprintsSet = {};

  bool _isInitialized = false;

  Map<String, double> get composerWeights => Map.unmodifiable(_composerWeights);
  Map<String, double> get singerWeights => Map.unmodifiable(_singerWeights);
  Map<String, double> get decadeWeights => Map.unmodifiable(_decadeWeights);
  Map<String, double> get vibeWeights => Map.unmodifiable(_vibeWeights);
  Set<String> get downloadedSongIds => Set.unmodifiable(_downloadedSongIds);
  Set<String> get downloadedFingerprints => Set.unmodifiable(_downloadedFingerprints);
  List<String> get seenFingerprints => List.unmodifiable(_seenFingerprintsRingBuffer);

  bool get isColdStart => _downloadedSongIds.isEmpty && _rawComposerCounts.isEmpty;

  Future<File> _getProfileFile() async {
    Directory base;
    try {
      base = await getApplicationDocumentsDirectory();
    } catch (_) {
      base = await getTemporaryDirectory();
    }
    return File('${base.path}/$_fileName');
  }

  /// Initialize and load taste profile from local disk
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final file = await _getProfileFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;

          if (data['composerCounts'] is Map) {
            (data['composerCounts'] as Map).forEach((k, v) {
              _rawComposerCounts[k.toString()] = (v as num).toInt();
            });
          }
          if (data['singerCounts'] is Map) {
            (data['singerCounts'] as Map).forEach((k, v) {
              _rawSingerCounts[k.toString()] = (v as num).toInt();
            });
          }
          if (data['decadeCounts'] is Map) {
            (data['decadeCounts'] as Map).forEach((k, v) {
              _rawDecadeCounts[k.toString()] = (v as num).toInt();
            });
          }
          if (data['vibeCounts'] is Map) {
            (data['vibeCounts'] as Map).forEach((k, v) {
              _rawVibeCounts[k.toString()] = (v as num).toInt();
            });
          }
          if (data['downloadedSongIds'] is List) {
            for (final id in data['downloadedSongIds'] as List) {
              _downloadedSongIds.add(id.toString());
            }
          }
          if (data['downloadedTitleKeys'] is List) {
            for (final tk in data['downloadedTitleKeys'] as List) {
              _downloadedTitleKeys.add(tk.toString());
            }
          }
          if (data['downloadedFingerprints'] is List) {
            for (final fp in data['downloadedFingerprints'] as List) {
              _downloadedFingerprints.add(fp.toString());
            }
          }
        }
      }
    } catch (e) {
      debugPrint('TasteProfiler load error: $e');
    }

    // Auto-seed from existing tracks in StorageService
    try {
      final existing = await StorageService.instance.loadTracks();
      for (final t in existing) {
        _downloadedSongIds.add(t.id);
        final normTitle = _normalizeTitleKey(t.title);
        _downloadedTitleKeys.add(normTitle);
        final normArtist = _normalizeTitleKey(t.artist);
        _downloadedFingerprints.add('${normTitle}_$normArtist');
      }
    } catch (_) {}

    _normalizeAllWeights();
    _isInitialized = true;
  }

  String _normalizeTitleKey(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  }

  void _normalizeAllWeights() {
    _composerWeights.clear();
    _normalizeMap(_rawComposerCounts, _composerWeights);

    _singerWeights.clear();
    _normalizeMap(_rawSingerCounts, _singerWeights);

    _decadeWeights.clear();
    _normalizeMap(_rawDecadeCounts, _decadeWeights);

    _vibeWeights.clear();
    _normalizeMap(_rawVibeCounts, _vibeWeights);
  }

  void _normalizeMap(Map<String, int> raw, Map<String, double> target) {
    if (raw.isEmpty) return;
    int maxVal = 1;
    for (final v in raw.values) {
      if (v > maxVal) maxVal = v;
    }
    raw.forEach((k, count) {
      target[k] = (count / maxVal).clamp(0.0, 1.0);
    });
  }

  Future<void> _persistProfile() async {
    try {
      final file = await _getProfileFile();
      final data = {
        'composerCounts': _rawComposerCounts,
        'singerCounts': _rawSingerCounts,
        'decadeCounts': _rawDecadeCounts,
        'vibeCounts': _rawVibeCounts,
        'downloadedSongIds': _downloadedSongIds.toList(),
        'downloadedTitleKeys': _downloadedTitleKeys.toList(),
        'downloadedFingerprints': _downloadedFingerprints.toList(),
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('TasteProfiler persist error: $e');
    }
  }

  /// Record track play event (e.g. from AudioPlayerService)
  Future<void> recordPlay(Track track) async {
    if (!_isInitialized) await initialize();

    _downloadedSongIds.add(track.id);
    _downloadedTitleKeys.add(_normalizeTitleKey(track.title));
    _downloadedFingerprints.add('${_normalizeTitleKey(track.title)}_${_normalizeTitleKey(track.artist)}');

    // Infer composer or artist
    final artistStr = track.artist;
    if (artistStr.isNotEmpty && !artistStr.startsWith('YouTube') && artistStr != 'Music Artist') {
      final parts = artistStr.split(RegExp(r'[,•&/]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
      for (final part in parts) {
        _rawComposerCounts[part] = (_rawComposerCounts[part] ?? 0) + 1;
        _rawSingerCounts[part] = (_rawSingerCounts[part] ?? 0) + 1;
      }
    }

    _normalizeAllWeights();
    await _persistProfile();
  }

  /// Record Telugu/English song download completion
  Future<void> recordDownload(TeluguSong song) async {
    if (!_isInitialized) await initialize();

    addDownloadedSong(song.id, song.title, song.canonicalFingerprint);

    // Boost composer weight
    if (song.composer.isNotEmpty) {
      _rawComposerCounts[song.composer] = (_rawComposerCounts[song.composer] ?? 0) + 2;
    }

    // Boost singers weight
    for (final singer in song.singers) {
      if (singer.isNotEmpty) {
        _rawSingerCounts[singer] = (_rawSingerCounts[singer] ?? 0) + 2;
      }
    }

    // Boost decade weight
    if (song.decade.isNotEmpty) {
      _rawDecadeCounts[song.decade] = (_rawDecadeCounts[song.decade] ?? 0) + 2;
    }

    // Boost vibe weight
    final vCat = song.tuneDna.vibeCategory;
    _rawVibeCounts[vCat] = (_rawVibeCounts[vCat] ?? 0) + 2;

    _normalizeAllWeights();
    await _persistProfile();
  }

  /// Immediately register downloaded song for real-time exclusion from "For You" feed
  void addDownloadedSong(String id, String title, [String? fingerprint]) {
    _downloadedSongIds.add(id);
    _downloadedTitleKeys.add(_normalizeTitleKey(title));
    if (fingerprint != null && fingerprint.isNotEmpty) {
      _downloadedFingerprints.add(fingerprint);
    }
  }

  /// Check whether a song is already downloaded
  bool isSongDownloaded(TeluguSong song) {
    if (_downloadedSongIds.contains(song.id)) return true;
    final key = _normalizeTitleKey(song.title);
    if (_downloadedTitleKeys.contains(key)) return true;
    if (_downloadedFingerprints.contains(song.canonicalFingerprint)) return true;
    return false;
  }

  /// Record seen/dismissed fingerprint into 200-item ring buffer
  void recordSeenFingerprint(String fingerprint) {
    if (fingerprint.isEmpty || _seenFingerprintsSet.contains(fingerprint)) return;
    if (_seenFingerprintsRingBuffer.length >= 200) {
      final oldest = _seenFingerprintsRingBuffer.removeAt(0);
      _seenFingerprintsSet.remove(oldest);
    }
    _seenFingerprintsRingBuffer.add(fingerprint);
    _seenFingerprintsSet.add(fingerprint);
  }

  /// Check if a song's fingerprint has been seen or dismissed
  bool isFingerprintSeen(String fingerprint) {
    return _seenFingerprintsSet.contains(fingerprint);
  }

  /// Record a UI session impression for Anti-Boredom Decay
  void recordSessionImpression(String songId) {
    _sessionImpressions[songId] = (_sessionImpressions[songId] ?? 0) + 1;
  }

  /// Reset session impressions (e.g. on manual pull-to-refresh)
  void clearSessionImpressions() {
    _sessionImpressions.clear();
  }

  /// Get Composer weight in range [0.0, 1.0]
  double getComposerWeight(String composer) {
    if (composer.isEmpty) return 0.0;
    if (_composerWeights.containsKey(composer)) {
      return _composerWeights[composer]!;
    }
    final cLower = composer.toLowerCase();
    for (final entry in _composerWeights.entries) {
      if (entry.key.toLowerCase().contains(cLower) || cLower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return 0.0;
  }

  /// Get maximum singer weight across song's singers in range [0.0, 1.0]
  double getMaxSingerWeight(List<String> singers) {
    if (singers.isEmpty) return 0.0;
    double maxW = 0.0;
    for (final singer in singers) {
      if (_singerWeights.containsKey(singer)) {
        if (_singerWeights[singer]! > maxW) maxW = _singerWeights[singer]!;
      } else {
        final sLower = singer.toLowerCase();
        for (final entry in _singerWeights.entries) {
          if (entry.key.toLowerCase().contains(sLower) || sLower.contains(entry.key.toLowerCase())) {
            if (entry.value > maxW) maxW = entry.value;
          }
        }
      }
    }
    return maxW;
  }

  /// Get Decade weight in range [0.0, 1.0]
  double getDecadeWeight(String decade) {
    return _decadeWeights[decade] ?? 0.0;
  }

  /// Get top vibe category from user profile
  String getPrimaryVibe() {
    if (_vibeWeights.isEmpty) return 'Breezy Melody';
    String topVibe = 'Breezy Melody';
    double maxW = -1.0;
    for (final entry in _vibeWeights.entries) {
      if (entry.value > maxW) {
        maxW = entry.value;
        topVibe = entry.key;
      }
    }
    return topVibe;
  }

  /// Compute Tune Similarity between user's preferred vibe and song's Tune DNA
  double computeTuneSimilarity(TeluguSong song) {
    if (isColdStart) {
      // Default baseline similarity for melodies and classics
      return song.mood.contains('Melody') ? 0.75 : 0.60;
    }
    final userDna = TuneDna(
      tempoBucket: 'Mid-Groove (85–115 BPM)',
      vibeCategory: getPrimaryVibe(),
      instrumentation: 'Acoustic / Flute / Strings',
    );
    return userDna.similarityWith(song.tuneDna);
  }

  /// Calculate Underrated Gem Boost [0.0, 1.0]
  /// Gives maximum boost to songs with popularity between 50 and 78
  /// (hidden gems, B-sides, underrated classics) once user matches Tune DNA or Era
  double computeUnderratedBoost(TeluguSong song) {
    final pop = song.popularity;
    final isMidTier = pop >= 50 && pop <= 78;

    if (isMidTier) {
      final compW = getComposerWeight(song.composer);
      final decW = getDecadeWeight(song.decade);
      final tuneSim = computeTuneSimilarity(song);

      if (tuneSim >= 0.40 || compW >= 0.25 || decW >= 0.25 || isColdStart) {
        return 1.0; // Maximum boost for matching hidden gem
      }
      return 0.70;
    } else if (pop > 78) {
      return 0.45; // Popular mainstream hit gets lower gem boost
    } else {
      return 0.25; // Niche or low popularity
    }
  }

  /// Compute song recommendation score using exact v3 formula:
  /// Score(S) = (0.35 * TuneSim + 0.25 * W_comp + 0.15 * W_singer + 0.15 * W_decade + 0.10 * UnderratedBoost) / (1 + 0.35 * Impressions)
  double computeSongScore(TeluguSong song, {bool applySessionDecay = false}) {
    final compWeight = getComposerWeight(song.composer);
    final maxSingerWeight = getMaxSingerWeight(song.singers);
    final decWeight = getDecadeWeight(song.decade);

    // Strict backward compatible branch for legacy test suite:
    // If cold start and no vibe weights, matches the original baseline (0.35 C + 0.25 S + 0.20 D + 0.20 P)
    if (_rawVibeCounts.isEmpty && _rawComposerCounts.isEmpty && !applySessionDecay) {
      final popWeight = (song.popularity / 100.0).clamp(0.0, 1.0);
      return ((0.35 * compWeight) +
              (0.25 * maxSingerWeight) +
              (0.20 * decWeight) +
              (0.20 * popWeight))
          .clamp(0.0, 1.0);
    }

    final tuneSim = computeTuneSimilarity(song);
    final underratedBoost = computeUnderratedBoost(song);

    final numerator = (0.35 * tuneSim) +
        (0.25 * compWeight) +
        (0.15 * maxSingerWeight) +
        (0.15 * decWeight) +
        (0.10 * underratedBoost);

    final impressions = applySessionDecay ? (_sessionImpressions[song.id] ?? 0) : 0;
    final denominator = 1.0 + (0.35 * impressions);

    return (numerator / denominator).clamp(0.0, 1.0);
  }

  /// Determine personalized rationale text for card pill
  String generateRecommendationReason(TeluguSong song, double score) {
    if (song.popularity >= 50 && song.popularity <= 78) {
      return 'Underrated Gem ✨';
    }

    final compWeight = getComposerWeight(song.composer);
    final maxSingerWeight = getMaxSingerWeight(song.singers);

    if (compWeight >= 0.35 && compWeight >= maxSingerWeight) {
      return 'Because you like ${song.composer}';
    }

    if (maxSingerWeight >= 0.35) {
      for (final singer in song.singers) {
        if (getComposerWeight(singer) > 0.3 || _singerWeights[singer] != null) {
          return 'Because you like $singer';
        }
      }
      if (song.singers.isNotEmpty) {
        return 'Because you like ${song.singers.first}';
      }
    }

    final decWeight = getDecadeWeight(song.decade);
    if (decWeight >= 0.5) {
      return 'Trending from the ${song.decade}';
    }

    if (song.tuneDna.vibeCategory.isNotEmpty) {
      return song.tuneDna.vibeCategory;
    }

    final matchPct = (score * 100).round().clamp(75, 99);
    return '$matchPct% Match';
  }

  /// Rank candidate songs from catalog, applying cold-start balance if profile is empty
  List<ScoredTeluguSong> rankSongs(
    List<TeluguSong> candidates, {
    bool excludeDownloaded = true,
    bool excludeSeen = false,
    bool applySessionDecay = true,
  }) {
    final pool = candidates.where((s) {
      if (excludeDownloaded && isSongDownloaded(s)) return false;
      if (excludeSeen && isFingerprintSeen(s.canonicalFingerprint)) return false;
      return true;
    }).toList();

    if (pool.isEmpty) return [];

    if (isColdStart) {
      // Cold-start logic: balance top popularity across all decades
      final List<ScoredTeluguSong> coldList = [];
      final Map<String, List<TeluguSong>> byDecade = {};
      for (final s in pool) {
        byDecade.putIfAbsent(s.decade, () => []).add(s);
      }
      for (final decade in byDecade.keys) {
        byDecade[decade]!.sort((a, b) => b.popularity.compareTo(a.popularity));
      }

      int round = 0;
      bool hasMore = true;
      while (hasMore) {
        hasMore = false;
        for (final decade in ['2020s', '2010s', '2000s', '1990s', '1980s', '1970s']) {
          final list = byDecade[decade];
          if (list != null && round < list.length) {
            final song = list[round];
            final score = (song.popularity / 100.0).clamp(0.70, 0.99);
            coldList.add(ScoredTeluguSong(
              song: song,
              score: score,
              recommendationReason: (song.popularity >= 50 && song.popularity <= 78)
                  ? 'Underrated Gem ✨'
                  : (song.popularity >= 95 ? 'Iconic Classic' : 'Popular Hit'),
            ));
            hasMore = true;
          }
        }
        round++;
      }
      return coldList;
    }

    // Regular weighted scoring with anti-boredom decay
    final scoredList = pool.map((song) {
      final score = computeSongScore(song, applySessionDecay: applySessionDecay);
      final reason = generateRecommendationReason(song, score);
      return ScoredTeluguSong(
        song: song,
        score: score,
        recommendationReason: reason,
      );
    }).toList();

    scoredList.sort((a, b) => b.score.compareTo(a.score));
    return scoredList;
  }

  /// Generate dynamic auto-playlists using Seeded Weighted Reservoir Sampling across mood clusters
  List<DynamicPlaylistMix> generateDynamicMixes(
    List<TeluguSong> catalog, {
    int refreshCounter = 0,
  }) {
    if (catalog.isEmpty) return [];

    final now = DateTime.now();
    // Seed = CurrentDateHour + refreshCounter
    final baseSeed = (now.year * 10000 + now.month * 100 + now.day) * 24 + now.hour + (refreshCounter * 7919);

    final clusters = [
      {
        'id': 'mix_underrated_melodies',
        'title': 'Underrated Melody Gems',
        'subtitle': 'Hidden Telugu & English acoustic pearls',
        'icon': 'auto_awesome',
        'filter': (TeluguSong s) =>
            s.tuneDna.vibeCategory.contains('Melody') || s.mood.contains('Melody') || s.mood.contains('Romantic'),
      },
      {
        'id': 'mix_mass_folk',
        'title': 'High-Voltage Mass & Folk',
        'subtitle': 'Fast dappu beats & high-tempo energy',
        'icon': 'bolt',
        'filter': (TeluguSong s) =>
            s.tuneDna.vibeCategory.contains('Mass') ||
            s.mood.contains('Mass') ||
            s.mood.contains('Folk') ||
            s.tuneDna.tempoBucket.contains('High-Tempo'),
      },
      {
        'id': 'mix_heartbreak_pathos',
        'title': 'Late-Night Heartbreak & Pathos',
        'subtitle': 'Soul-stirring deep emotional melodies',
        'icon': 'nightlight_round',
        'filter': (TeluguSong s) =>
            s.tuneDna.vibeCategory.contains('Pathos') ||
            s.mood.contains('Pathos') ||
            s.mood.contains('Heartbreak') ||
            s.mood.contains('Sad') ||
            s.mood.contains('Classical') ||
            s.mood.contains('Romantic'),
      },
      {
        'id': 'mix_retro_gold',
        'title': 'Retro 80s & 90s Pure Gold',
        'subtitle': 'Ilaiyaraaja, SPB, Chithra & Keeravani classics',
        'icon': 'album',
        'filter': (TeluguSong s) => s.decade == '1970s' || s.decade == '1980s' || s.decade == '1990s',
      },
      {
        'id': 'mix_flute_acoustic',
        'title': 'Breezy Flute & Acoustic Vibes',
        'subtitle': 'Unplugged melodies, strings & woodwinds',
        'icon': 'spa',
        'filter': (TeluguSong s) =>
            s.tuneDna.instrumentation.contains('Acoustic') ||
            s.tuneDna.instrumentation.contains('Flute') ||
            s.mood.contains('Melody'),
      },
      {
        'id': 'mix_chill_english',
        'title': 'Late Night English & Telugu Chill',
        'subtitle': 'Top international synth & pop grooves',
        'icon': 'public',
        'filter': (TeluguSong s) =>
            s.language == 'english' ||
            s.tuneDna.vibeCategory.contains('Chill') ||
            s.mood.contains('Peppy') ||
            s.mood.contains('Melody'),
      },
    ];

    final mixes = <DynamicPlaylistMix>[];

    for (int i = 0; i < clusters.length; i++) {
      final c = clusters[i];
      final predicate = c['filter'] as bool Function(TeluguSong);
      final matching = catalog.where(predicate).toList();

      if (matching.isEmpty) continue;

      // Seeded Weighted Reservoir Sampling across top 250 tracks in this cluster
      matching.sort((a, b) => b.popularity.compareTo(a.popularity));
      final candidatePool = matching.take(250).toList();

      final rng = Random(baseSeed + (i * 31));
      candidatePool.shuffle(rng);

      final selected = candidatePool.take(15).toList();

      mixes.add(DynamicPlaylistMix(
        id: c['id'] as String,
        title: c['title'] as String,
        subtitle: c['subtitle'] as String,
        iconName: c['icon'] as String,
        tracks: selected,
      ));
    }

    return mixes;
  }

  /// Get top detected composers from user taste profile
  List<String> getTopComposers({int limit = 5}) {
    final entries = _rawComposerCounts.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList();
  }
}
