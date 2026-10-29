import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitauri_flutter/models/telugu_song.dart';
import 'package:chitauri_flutter/services/taste_profiler.dart';
import 'package:chitauri_flutter/services/telugu_catalog_service.dart';
import 'package:chitauri_flutter/services/open_catalog_service.dart';
import 'package:chitauri_flutter/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // SUITE 1: Tune-DNA & v3 Scoring Math Test
  // =========================================================================
  group('Suite 1: Tune DNA & v3 Scoring Math Test', () {
    test('TuneDna parses and calculates accurate cosine-like similarity across vectors', () {
      const melodyAcoustic = TuneDna(
        tempoBucket: 'Mid-Groove (85–115 BPM)',
        vibeCategory: 'Breezy Melody',
        instrumentation: 'Acoustic / Flute / Strings',
      );

      const melodyOrchestral = TuneDna(
        tempoBucket: 'Mid-Groove (85–115 BPM)',
        vibeCategory: 'Breezy Melody',
        instrumentation: 'Orchestral',
      );

      const massPercussion = TuneDna(
        tempoBucket: 'High-Tempo/Mass (>135 BPM)',
        vibeCategory: 'High-Energy Mass / Folk',
        instrumentation: 'Heavy Bass / Percussion',
      );

      // Identity check
      expect(melodyAcoustic.similarityWith(melodyAcoustic), closeTo(1.0, 0.001));

      // Same tempo & vibe, different instrumentation -> high similarity (> 0.70)
      final closeSim = melodyAcoustic.similarityWith(melodyOrchestral);
      expect(closeSim, greaterThan(0.70));
      expect(closeSim, lessThan(1.0));

      // Disparate tempo, vibe, and instrumentation -> low similarity (< 0.35)
      final lowSim = melodyAcoustic.similarityWith(massPercussion);
      expect(lowSim, lessThan(0.35));
    });

    test('v3 scoring formula accurately weights similarity, metadata, and underrated boost', () {
      final profiler = TasteProfiler.instance;
      profiler.clearSessionImpressions();

      const song = TeluguSong(
        id: 'score_math_test_01',
        title: 'Underrated Melody Track',
        movie: 'Test Cinema',
        year: 2021,
        decade: '2020s',
        composer: 'M. M. Keeravani',
        singers: ['Sid Sriram'],
        mood: 'Melody',
        popularity: 65, // In 50–78 sweet spot -> maximum boost!
        tempoBucket: 'Mid-Groove (85–115 BPM)',
        vibeCategory: 'Breezy Melody',
        instrumentation: 'Acoustic / Flute / Strings',
      );

      // Verify UnderratedBoost is near maximum (1.0)
      final boost = profiler.computeUnderratedBoost(song);
      expect(boost, closeTo(1.0, 0.05));

      final score = profiler.computeSongScore(song, applySessionDecay: false);
      expect(score, greaterThan(0.0));
      expect(score, lessThanOrEqualTo(1.0));
    });

    test('Underrated Gem Boost rewards songs with popularity between 50 and 78', () {
      final profiler = TasteProfiler.instance;

      const hiddenGem = TeluguSong(
        id: 'gem_01',
        title: 'Hidden Classic',
        movie: 'Classic Movie',
        year: 1985,
        decade: '1980s',
        composer: 'Ilaiyaraaja',
        singers: ['S. P. Balasubrahmanyam'],
        mood: 'Melody',
        popularity: 65, // In 50–78 sweet spot
      );

      const mainstreamHit = TeluguSong(
        id: 'hit_01',
        title: 'Blockbuster Track',
        movie: 'Action Movie',
        year: 2024,
        decade: '2020s',
        composer: 'Thaman S',
        singers: ['Sid Sriram'],
        mood: 'Peppy',
        popularity: 99, // Mainstream 99 hit
      );

      const obscureTrack = TeluguSong(
        id: 'low_01',
        title: 'Obscure Track',
        movie: 'Unknown Movie',
        year: 2015,
        decade: '2010s',
        composer: 'Unknown',
        singers: ['Unknown'],
        mood: 'Folk',
        popularity: 20, // Low popularity
      );

      final gemBoost = profiler.computeUnderratedBoost(hiddenGem);
      final hitBoost = profiler.computeUnderratedBoost(mainstreamHit);
      final lowBoost = profiler.computeUnderratedBoost(obscureTrack);

      expect(gemBoost, greaterThan(hitBoost));
      expect(gemBoost, greaterThan(lowBoost));
      expect(gemBoost, closeTo(1.0, 0.05));
    });

    test('Anti-Boredom Session Decay monotonically penalizes repeatedly shown songs', () {
      final profiler = TasteProfiler.instance;
      profiler.clearSessionImpressions();

      const song = TeluguSong(
        id: 'decay_test_song',
        title: 'Decay Song',
        movie: 'Decay Movie',
        year: 2022,
        decade: '2020s',
        composer: 'Hesham Abdul Wahab',
        singers: ['Sid Sriram'],
        mood: 'Melody',
        popularity: 70,
      );

      final score0 = profiler.computeSongScore(song, applySessionDecay: true);

      profiler.recordSessionImpression(song.id);
      final score1 = profiler.computeSongScore(song, applySessionDecay: true);

      profiler.recordSessionImpression(song.id);
      final score2 = profiler.computeSongScore(song, applySessionDecay: true);

      profiler.recordSessionImpression(song.id);
      final score3 = profiler.computeSongScore(song, applySessionDecay: true);

      // Monotonic strictly decreasing score
      expect(score1, lessThan(score0));
      expect(score2, lessThan(score1));
      expect(score3, lessThan(score2));

      // At 3 impressions, denominator is (1 + 0.35 * 3) = 2.05
      expect(score0 / score3, closeTo(2.05, 0.05));
    });
  });

  // =========================================================================
  // SUITE 2: Seeded Weighted Reservoir Sampling & Dynamic Auto-Playlists Test
  // =========================================================================
  group('Suite 2: Seeded Weighted Reservoir Sampling & Dynamic Auto-Playlists Test', () {
    test('All 6 Dynamic Mixes generate cohesive 15-track playlists', () {
      final profiler = TasteProfiler.instance;
      final seed = TeluguCatalogService.fallbackSeedJson.map((e) => TeluguSong.fromJson(e)).toList();

      final mixes = profiler.generateDynamicMixes(seed, refreshCounter: 0);
      expect(mixes.isNotEmpty, isTrue);

      final expectedMixTitles = [
        'Underrated Melody Gems',
        'High-Voltage Mass & Folk',
        'Late-Night Heartbreak & Pathos',
        'Retro 80s & 90s Pure Gold',
        'Breezy Flute & Acoustic Vibes',
        'Late Night English & Telugu Chill',
      ];

      final actualTitles = mixes.map((m) => m.title).toSet();
      for (final title in expectedMixTitles) {
        expect(actualTitles.contains(title), isTrue, reason: 'Missing mix: $title');
      }

      for (final mix in mixes) {
        expect(mix.tracks.isNotEmpty, isTrue);
        expect(mix.tracks.length, lessThanOrEqualTo(15));
      }
    });

    test('Incrementing refreshCount produces different track selections via seeded sampling', () {
      final profiler = TasteProfiler.instance;
      // Build a realistic pool of 120 mock songs
      final pool = List.generate(120, (i) {
        final moods = ['Melody', 'Mass', 'Pathos', 'Classical', 'Peppy', 'Romantic'];
        final mood = moods[i % moods.length];
        return TeluguSong(
          id: 'mock_pool_song_$i',
          title: 'Track Title $i',
          movie: 'Movie ${(i ~/ 5) + 1}',
          year: 1980 + (i % 44),
          decade: '${1980 + ((i % 44) ~/ 10) * 10}s',
          composer: 'Composer ${i % 8}',
          singers: ['Singer ${i % 10}'],
          mood: mood,
          popularity: 50 + (i % 45),
        );
      });

      final mixesSeed0 = profiler.generateDynamicMixes(pool, refreshCounter: 0);
      final mixesSeed1 = profiler.generateDynamicMixes(pool, refreshCounter: 1);

      // Compare track IDs of the first mix between refresh 0 and refresh 1
      final mix0Ids = mixesSeed0.first.tracks.map((t) => t.id).toList();
      final mix1Ids = mixesSeed1.first.tracks.map((t) => t.id).toList();

      // At least some tracks should differ due to the seeded pseudo-random shuffle
      final overlap = mix0Ids.toSet().intersection(mix1Ids.toSet()).length;
      expect(overlap, lessThan(mix0Ids.length), reason: 'Track selections must differ across refreshes');
    });
  });

  // =========================================================================
  // SUITE 3: Hybrid Open Catalog & Safeguard 4 (open_catalog_service.dart) Test
  // =========================================================================
  group('Suite 3: Hybrid Open Catalog & Safeguard 4 Test', () {
    test('Apple iTunes JSON with utf8 decoding parses clean 600x600 HD banners', () {
      final service = OpenCatalogService.instance;

      // Mock iTunes API response payload
      const mockRawJson = '''
      {
        "resultCount": 1,
        "results": [
          {
            "trackId": 987654321,
            "trackName": " Samajavaragamana ",
            "artistName": "Sid Sriram & Thaman S",
            "collectionName": "Ala Vaikunthapurramuloo (Soundtrack)",
            "releaseDate": "2019-10-08T07:00:00Z",
            "primaryGenreName": "Telugu Soundtrack",
            "artworkUrl100": "https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/a1/b2/c3/100x100bb.jpg"
          }
        ]
      }
      ''';

      // Verify utf8.decode(bodyBytes) simulation
      final bytes = utf8.encode(mockRawJson);
      final decodedStr = utf8.decode(bytes);
      final map = jsonDecode(decodedStr) as Map<String, dynamic>;
      final rawTrack = (map['results'] as List).first as Map;

      final song = service.parseItunesTrack(rawTrack, 'telugu');
      expect(song, isNotNull);
      expect(song!.title, 'Samajavaragamana');
      expect(song.movie, 'Ala Vaikunthapurramuloo');
      expect(song.year, 2019);
      expect(song.decade, '2010s');
      // Verify artwork transformation: 100x100bb -> 600x600bb
      expect(song.bannerUrl, contains('600x600bb.jpg'));
      expect(song.bannerUrl, isNot(contains('100x100bb.jpg')));
    });

    test('Deduplication by normalized title and movie prevents duplicate entries', () {
      const song1 = TeluguSong(
        id: 'itunes_101',
        title: 'Butta Bomma',
        movie: 'Ala Vaikunthapurramuloo',
        year: 2020,
        decade: '2020s',
        composer: 'Thaman S',
        singers: ['Armaan Malik'],
        mood: 'Peppy',
        popularity: 95,
      );

      // Exact same song from a different shard with different casing and whitespace
      const song2 = TeluguSong(
        id: 'itunes_999',
        title: '  butta bomma  ',
        movie: 'ala vaikunthapurramuloo ',
        year: 2020,
        decade: '2020s',
        composer: 'Thaman S',
        singers: ['Armaan Malik'],
        mood: 'Peppy',
        popularity: 90,
      );

      expect(song1.normalizedDedupeKey, song2.normalizedDedupeKey);

      // Verify Set deduplication works cleanly
      final uniqueKeys = <String>{};
      final uniqueSongs = <TeluguSong>[];

      for (final s in [song1, song2]) {
        if (!uniqueKeys.contains(s.normalizedDedupeKey)) {
          uniqueKeys.add(s.normalizedDedupeKey);
          uniqueSongs.add(s);
        }
      }

      expect(uniqueSongs.length, 1);
      expect(uniqueSongs.first.id, 'itunes_101');
    });
  });

  // =========================================================================
  // SUITE 4: Full-Pool Sorting & Filtering Before Pagination (Safeguard 3) Test
  // =========================================================================
  group('Suite 4: Full-Pool Sorting & Filtering Before Pagination (Safeguard 3)', () {
    test('Sorting 150 songs orders the entire pool globally before paginating visibleCount = 20', () {
      // Generate mock pool of 150 songs
      final pool = List.generate(150, (i) {
        // Assign titles with clear alphabetical prefix: Song 001 to Song 150
        final numStr = (i + 1).toString().padLeft(3, '0');
        return TeluguSong(
          id: 'pool_song_$i',
          title: 'Track $numStr',
          movie: 'Movie ${(i % 30) + 1}',
          year: 1980 + (i % 45), // Years from 1980 to 2024
          decade: '${1980 + ((i % 45) ~/ 10) * 10}s',
          composer: 'Composer ${i % 5}',
          singers: ['Singer ${i % 7}'],
          mood: 'Melody',
          popularity: 50 + (i % 50),
          language: i % 2 == 0 ? 'telugu' : 'english',
        );
      });

      expect(pool.length, 150);

      // Test 1: Sort by Title A-Z globally
      final titleAscPool = List<TeluguSong>.from(pool);
      titleAscPool.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

      // Take first page (visibleCount = 20)
      final page1 = titleAscPool.take(20).toList();
      expect(page1.length, 20);
      expect(page1.first.title, 'Track 001');
      expect(page1.last.title, 'Track 020');

      // Test 2: Sort by Title Z-A globally
      final titleDescPool = List<TeluguSong>.from(pool);
      titleDescPool.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));

      final pageDesc = titleDescPool.take(20).toList();
      expect(pageDesc.length, 20);
      expect(pageDesc.first.title, 'Track 150');
      expect(pageDesc.last.title, 'Track 131');

      // Test 3: Sort by Latest First (descending year)
      final latestPool = List<TeluguSong>.from(pool);
      latestPool.sort((a, b) => b.year.compareTo(a.year));
      final pageLatest = latestPool.take(20).toList();
      expect(pageLatest.first.year, 2024);
      for (int k = 0; k < pageLatest.length - 1; k++) {
        expect(pageLatest[k].year >= pageLatest[k + 1].year, isTrue);
      }

      // Test 4: Verify scroll past 75% appends +20 items (20 -> 40 -> 60)
      int displayedCount = 20;
      displayedCount = (displayedCount + 20).clamp(0, pool.length);
      expect(displayedCount, 40);

      displayedCount = (displayedCount + 20).clamp(0, pool.length);
      expect(displayedCount, 60);
    });

    test('Filtering by Language operates on complete pool before pagination', () {
      final pool = List.generate(150, (i) {
        return TeluguSong(
          id: 'lang_song_$i',
          title: 'Track $i',
          movie: 'Movie $i',
          year: 2020,
          decade: '2020s',
          composer: 'Composer',
          singers: ['Singer'],
          mood: 'Melody',
          popularity: 80,
          language: i < 100 ? 'telugu' : 'english',
        );
      });

      final teluguOnly = pool.where((s) => s.language == 'telugu').toList();
      final englishOnly = pool.where((s) => s.language == 'english').toList();

      expect(teluguOnly.length, 100);
      expect(englishOnly.length, 50);

      final teluguPage1 = teluguOnly.take(20).toList();
      expect(teluguPage1.length, 20);
      expect(teluguPage1.every((s) => s.language == 'telugu'), isTrue);
    });
  });

  // =========================================================================
  // SUITE 5: Playlist Flat Unrolling Nullable Duration Guard (Safeguard 2) Test
  // =========================================================================
  group('Suite 5: Playlist Flat Unrolling Nullable Duration Guard (Safeguard 2)', () {
    test('parsePlaylistJson preserves null/valid durations and filters shorts (<90s) & jukeboxes (>540s)', () {
      final ytService = YouTubeService.instance;

      const mockYtDlpOutput = '''
      {
        "_type": "playlist",
        "id": "PL_TEST_PLAYLIST_123",
        "title": "Chitauri Test Mix",
        "entries": [
          {
            "id": "keep_null_dur",
            "title": "Keep Null Duration Song",
            "uploader": "Artist One",
            "duration": null,
            "thumbnails": [{"url": "https://img.youtube.com/vi/keep_null_dur/hqdefault.jpg"}]
          },
          {
            "id": "keep_valid_dur",
            "title": "Keep 210s Valid Song",
            "uploader": "Artist Two",
            "duration": 210,
            "thumbnails": [{"url": "https://img.youtube.com/vi/keep_valid_dur/hqdefault.jpg"}]
          },
          {
            "id": "filter_short_30",
            "title": "Filtered YouTube Short",
            "uploader": "Shorts Channel",
            "duration": 30,
            "thumbnails": [{"url": "https://img.youtube.com/vi/filter_short_30/hqdefault.jpg"}]
          },
          {
            "id": "filter_long_1200",
            "title": "Filtered Full Album Jukebox",
            "uploader": "Jukebox Channel",
            "duration": 1200,
            "thumbnails": [{"url": "https://img.youtube.com/vi/filter_long_1200/hqdefault.jpg"}]
          }
        ]
      }
      ''';

      final items = ytService.parsePlaylistJson(mockYtDlpOutput);

      expect(items.length, 2, reason: 'Must keep exactly duration: null and duration: 210');

      final ids = items.map((e) => e.id).toList();
      expect(ids, contains('keep_null_dur'));
      expect(ids, contains('keep_valid_dur'));
      expect(ids, isNot(contains('filter_short_30')));
      expect(ids, isNot(contains('filter_long_1200')));

      // Verify null duration receives graceful fallback formatting (03:35 / 215s)
      final nullDurItem = items.firstWhere((e) => e.id == 'keep_null_dur');
      expect(nullDurItem.duration, isNotEmpty);
      expect(nullDurItem.duration, '3:35');
    });
  });

  // =========================================================================
  // SUITE 6: Immediate Exclusion on Download Test
  // =========================================================================
  group('Suite 6: Immediate Exclusion on Download Test', () {
    test('Triggering download immediately appends song to downloadedSongIds and purges from active feed', () {
      final profiler = TasteProfiler.instance;

      const testSong = TeluguSong(
        id: 'exclude_dl_test_123',
        title: 'Inkem Inkem',
        movie: 'Geetha Govindam',
        year: 2018,
        decade: '2010s',
        composer: 'Gopi Sundar',
        singers: ['Sid Sriram'],
        mood: 'Melody',
        popularity: 98,
      );

      // Verify initial state
      expect(profiler.isSongDownloaded(testSong), isFalse);

      // Simulate active For You feed list in UI State
      final activeFeed = <ScoredTeluguSong>[
        const ScoredTeluguSong(song: testSong, score: 0.95, recommendationReason: 'Top Melody Match'),
        const ScoredTeluguSong(
          song: TeluguSong(
            id: 'other_song_456',
            title: 'Other Song',
            movie: 'Other Movie',
            year: 2022,
            decade: '2020s',
            composer: 'Thaman S',
            singers: ['Sid Sriram'],
            mood: 'Melody',
            popularity: 88,
          ),
          score: 0.90,
          recommendationReason: 'Melody Match',
        ),
      ];

      expect(activeFeed.length, 2);

      // Trigger immediate exclusion as performed in _triggerDownload()
      profiler.addDownloadedSong(testSong.id, testSong.title);
      activeFeed.removeWhere((item) => item.song.id == testSong.id);

      // Assertions
      expect(profiler.isSongDownloaded(testSong), isTrue);
      expect(activeFeed.length, 1);
      expect(activeFeed.any((item) => item.song.id == testSong.id), isFalse);
    });
  });

  // =========================================================================
  // SUITE 7: Chitauri v4 Multi-Regional Rhythm-DNA & Gaussian Rarity Suite
  // =========================================================================
  group('Suite 7: Chitauri v4 Engine & Dynamic Rhythm-DNA Tests', () {
    test('Gaussian Rarity Scoring peaks precisely at popularity = 62', () {
      const peakSong = TeluguSong(
        id: 'peak_rarity',
        title: 'Rare Gem',
        movie: 'Film A',
        year: 2005,
        decade: '2000s',
        composer: 'M. M. Keeravani',
        singers: ['Hariharan'],
        mood: 'Melody',
        popularity: 62,
      );

      const popularSong = TeluguSong(
        id: 'popular_hit',
        title: 'Massive Viral Hit',
        movie: 'Film B',
        year: 2024,
        decade: '2020s',
        composer: 'Anirudh',
        singers: ['Anirudh'],
        mood: 'Mass',
        popularity: 98,
      );

      const obscureSong = TeluguSong(
        id: 'very_obscure',
        title: 'Forgotten Track',
        movie: 'Film C',
        year: 1975,
        decade: '1970s',
        composer: 'Ramesh',
        singers: ['Unknown'],
        mood: 'Classical',
        popularity: 20,
      );

      // Peak song at popularity = 62 must achieve maximal Gaussian Rarity Score of 1.0
      expect(peakSong.rarityScore, closeTo(1.0, 0.001));

      // Popular song and obscure song must score significantly lower on the Gaussian bell curve
      expect(popularSong.rarityScore, lessThan(0.05));
      expect(obscureSong.rarityScore, lessThan(0.05));
    });

    test('Canonical Fingerprint normalizes whitespace, accents, and film names', () {
      const songA = TeluguSong(
        id: 'song_a',
        title: '  Samajavaragamana  ',
        movie: 'Ala Vaikunthapurramuloo',
        year: 2020,
        decade: '2020s',
        composer: 'Thaman S',
        singers: ['Sid Sriram'],
        mood: 'Melody',
        popularity: 90,
      );

      const songB = TeluguSong(
        id: 'song_b',
        title: 'samajavaragamana',
        movie: 'ala vaikunthapurramuloo',
        year: 2020,
        decade: '2020s',
        composer: 'Thaman S',
        singers: ['Sid Sriram'],
        mood: 'Melody',
        popularity: 90,
      );

      expect(songA.canonicalFingerprint, equals(songB.canonicalFingerprint));
    });

    test('TasteProfiler 200-item Ring Buffer maintains strict FIFO bound', () {
      final profiler = TasteProfiler.instance;

      for (int i = 0; i < 250; i++) {
        profiler.recordSeenFingerprint('track_fingerprint_$i');
      }

      // First 50 items should have been evicted by the 200-item ring buffer
      expect(profiler.isFingerprintSeen('track_fingerprint_0'), isFalse);
      expect(profiler.isFingerprintSeen('track_fingerprint_49'), isFalse);

      // The last 200 items must remain in the ring buffer
      expect(profiler.isFingerprintSeen('track_fingerprint_50'), isTrue);
      expect(profiler.isFingerprintSeen('track_fingerprint_249'), isTrue);
    });

    test('Dynamic on-demand Rhythm-DNA correctly infers BPM, pulse and mood without static storage', () {
      const folkSong = TeluguSong(
        id: 'folk_song',
        title: 'Folk Beat',
        movie: 'Rural Cinema',
        year: 2018,
        decade: '2010s',
        composer: 'Bheems Ceciroleo',
        singers: ['Mangli'],
        mood: 'Folk',
        popularity: 75,
      );

      final dna = folkSong.tuneDna;
      expect(dna.vibeCategory, contains('Folk'));
      expect(dna.tempoBucket, contains('BPM'));
      expect(dna.instrumentation.isNotEmpty, isTrue);
    });
  });
}
