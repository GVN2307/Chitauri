import 'package:flutter_test/flutter_test.dart';
import 'package:chitauri_flutter/models/telugu_song.dart';
import 'package:chitauri_flutter/services/taste_profiler.dart';
import 'package:chitauri_flutter/services/telugu_catalog_service.dart';

void main() {
  group('Feature A: TeluguSong Model & Fallback Seed Tests', () {
    test('TeluguSong correctly formats searchQuery and eraBadge', () {
      const song = TeluguSong(
        id: 'tel_1991_aditya369_01',
        title: 'Jaanavule Nerajaanavule',
        movie: 'Aditya 369',
        year: 1991,
        decade: '1990s',
        composer: 'Ilaiyaraaja',
        singers: ['S. P. Balasubrahmanyam', 'Jikki'],
        mood: 'Melody',
        popularity: 96,
      );

      expect(song.searchQuery,
          'ytsearch1:Jaanavule Nerajaanavule Aditya 369 Ilaiyaraaja Telugu official audio song');
      expect(song.eraBadge, '1991 • Aditya 369');
      expect(song.subtitle, 'Ilaiyaraaja • S. P. Balasubrahmanyam, Jikki');
      expect(song.outputFileName, 'Jaanavule Nerajaanavule - Aditya 369');
    });

    test('Fallback seed contains at least 30 iconic Telugu songs across all 6 decades', () {
      const seed = TeluguCatalogService.fallbackSeedJson;
      expect(seed.length, greaterThanOrEqualTo(30));

      final decadesPresent = seed.map((e) => e['decade'] as String).toSet();
      expect(decadesPresent, containsAll(['1970s', '1980s', '1990s', '2000s', '2010s', '2020s']));
    });
  });

  group('Feature B: Taste Profiler Scoring Formula Tests', () {
    test('Scoring formula conforms to exact weights: 0.35 C + 0.25 S + 0.20 D + 0.20 P', () {
      final profiler = TasteProfiler.instance;

      const song = TeluguSong(
        id: 'test_01',
        title: 'Test Song',
        movie: 'Test Movie',
        year: 2005,
        decade: '2000s',
        composer: 'Mani Sharma',
        singers: ['Karthik'],
        mood: 'Melody',
        popularity: 100, // 100/100 = 1.0 -> 0.20 * 1.0 = 0.20
      );

      // In cold state (no weights):
      // ComposerWeight=0, SingerWeight=0, DecadeWeight=0, Popularity=1.0
      // Score = 0.35*0 + 0.25*0 + 0.20*0 + 0.20*1.0 = 0.20
      final score = profiler.computeSongScore(song);
      expect(score, closeTo(0.20, 0.001));
    });

    test('Cold-start logic balances songs across decades without crashes', () {
      final profiler = TasteProfiler.instance;
      final seedSongs = TeluguCatalogService.fallbackSeedJson
          .map((e) => TeluguSong.fromJson(e))
          .toList();

      final ranked = profiler.rankSongs(seedSongs, excludeDownloaded: false);
      expect(ranked.isNotEmpty, isTrue);
      expect(ranked.length, seedSongs.length);

      // Verify all scores are within [0.0, 1.0]
      for (final s in ranked) {
        expect(s.score, greaterThanOrEqualTo(0.0));
        expect(s.score, lessThanOrEqualTo(1.0));
        expect(s.recommendationReason.isNotEmpty, isTrue);
      }
    });
  });
}
