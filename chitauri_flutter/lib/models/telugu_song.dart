import 'dart:math';

class TuneDna {
  final String tempoBucket; // Slow (<85 BPM), Mid-Groove (85–115 BPM), Upbeat (115–135 BPM), High-Tempo/Mass (>135 BPM)
  final String vibeCategory; // Breezy Melody, Deep Pathos / Heartbreak, High-Energy Mass / Folk, Classical / Soulful, Chill / Late Night, Upbeat / Groove
  final String instrumentation; // Acoustic / Flute / Strings, Orchestral, Heavy Bass / Percussion, Electronic / Synth

  const TuneDna({
    required this.tempoBucket,
    required this.vibeCategory,
    required this.instrumentation,
  });

  Map<String, dynamic> toJson() => {
        'tempoBucket': tempoBucket,
        'vibeCategory': vibeCategory,
        'instrumentation': instrumentation,
      };

  factory TuneDna.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TuneDna(
        tempoBucket: 'Mid-Groove (85–115 BPM)',
        vibeCategory: 'Breezy Melody',
        instrumentation: 'Acoustic / Flute / Strings',
      );
    }
    return TuneDna(
      tempoBucket: json['tempoBucket'] as String? ?? 'Mid-Groove (85–115 BPM)',
      vibeCategory: json['vibeCategory'] as String? ?? 'Breezy Melody',
      instrumentation: json['instrumentation'] as String? ?? 'Acoustic / Flute / Strings',
    );
  }

  /// Compute similarity distance [0.0, 1.0] between two Tune DNA vectors
  double similarityWith(TuneDna other) {
    double sim = 0.0;
    if (vibeCategory == other.vibeCategory) {
      sim += 0.50;
    } else if (_isCompatibleVibe(vibeCategory, other.vibeCategory)) {
      sim += 0.25;
    }

    if (tempoBucket == other.tempoBucket) {
      sim += 0.30;
    } else if (_isAdjacentTempo(tempoBucket, other.tempoBucket)) {
      sim += 0.15;
    }

    if (instrumentation == other.instrumentation) {
      sim += 0.20;
    } else {
      sim += 0.05;
    }

    return sim.clamp(0.0, 1.0);
  }

  static bool _isCompatibleVibe(String v1, String v2) {
    if ((v1.contains('Melody') || v1.contains('Soulful')) && (v2.contains('Melody') || v2.contains('Soulful'))) return true;
    if ((v1.contains('Mass') || v1.contains('Groove')) && (v2.contains('Mass') || v2.contains('Groove'))) return true;
    if ((v1.contains('Chill') || v1.contains('Pathos')) && (v2.contains('Chill') || v2.contains('Pathos'))) return true;
    return false;
  }

  static bool _isAdjacentTempo(String t1, String t2) {
    const list = [
      'Slow (<85 BPM)',
      'Mid-Groove (85–115 BPM)',
      'Upbeat (115–135 BPM)',
      'High-Tempo/Mass (>135 BPM)',
    ];
    final idx1 = list.indexOf(t1);
    final idx2 = list.indexOf(t2);
    if (idx1 != -1 && idx2 != -1 && (idx1 - idx2).abs() == 1) return true;
    return false;
  }

  static TuneDna infer(String mood, {String genre = '', int year = 2000}) {
    final m = mood.toLowerCase();
    final g = genre.toLowerCase();

    if (m.contains('mass') || m.contains('folk') || m.contains('dappu') || m.contains('peppy') || m.contains('party')) {
      return const TuneDna(
        tempoBucket: 'High-Tempo/Mass (>135 BPM)',
        vibeCategory: 'High-Energy Mass / Folk',
        instrumentation: 'Heavy Bass / Percussion',
      );
    }
    if (m.contains('pathos') || m.contains('heartbreak') || m.contains('sad') || m.contains('breakup')) {
      return const TuneDna(
        tempoBucket: 'Slow (<85 BPM)',
        vibeCategory: 'Deep Pathos / Heartbreak',
        instrumentation: 'Acoustic / Flute / Strings',
      );
    }
    if (m.contains('classical') || m.contains('carnatic') || m.contains('devotional')) {
      return const TuneDna(
        tempoBucket: 'Mid-Groove (85–115 BPM)',
        vibeCategory: 'Classical / Soulful',
        instrumentation: 'Acoustic / Flute / Strings',
      );
    }
    if (m.contains('synth') || m.contains('electronic') || g.contains('synth') || g.contains('dance') || g.contains('pop') || g.contains('rock')) {
      return const TuneDna(
        tempoBucket: 'Upbeat (115–135 BPM)',
        vibeCategory: 'Upbeat / Groove',
        instrumentation: 'Electronic / Synth',
      );
    }
    if (m.contains('chill') || m.contains('lo-fi') || m.contains('ambient') || m.contains('late night') || g.contains('r&b') || m.contains('acoustic')) {
      return const TuneDna(
        tempoBucket: 'Slow (<85 BPM)',
        vibeCategory: 'Chill / Late Night',
        instrumentation: 'Acoustic / Flute / Strings',
      );
    }
    return const TuneDna(
      tempoBucket: 'Mid-Groove (85–115 BPM)',
      vibeCategory: 'Breezy Melody',
      instrumentation: 'Orchestral',
    );
  }
}

class TeluguSong {
  final String id;
  final String title;
  final String movie;
  final int year;
  final String decade;
  final String composer;
  final List<String> singers;
  final String mood;
  final int popularity;
  final String language; // 'telugu', 'tamil', 'malayalam', 'kannada', 'hindi', 'english'
  final String? bannerUrl;
  final String? tempoBucket;
  final String? vibeCategory;
  final String? instrumentation;

  // Multi-Regional Rhythm-DNA attributes
  final int? bpm;
  final String? rhythmPulse;
  final String? harmonicMood;
  final double? energyLevel;

  const TeluguSong({
    required this.id,
    required this.title,
    required this.movie,
    required this.year,
    required this.decade,
    required this.composer,
    required this.singers,
    required this.mood,
    required this.popularity,
    this.language = 'telugu',
    this.bannerUrl,
    this.tempoBucket,
    this.vibeCategory,
    this.instrumentation,
    this.bpm,
    this.rhythmPulse,
    this.harmonicMood,
    this.energyLevel,
  });

  TuneDna get tuneDna {
    if (tempoBucket != null && vibeCategory != null && instrumentation != null) {
      return TuneDna(
        tempoBucket: tempoBucket!,
        vibeCategory: vibeCategory!,
        instrumentation: instrumentation!,
      );
    }
    return TuneDna.infer(mood, year: year);
  }

  /// Gaussian Rarity Score centered at popularity = 62 with sigma = 14:
  /// RarityScore = exp(-((popularity - 62)^2) / (2 * 14^2))
  /// Gives ~1.0 for hidden gems in 50–74 range, drops to ~0.03 for 99 mainstream hits.
  double get rarityScore {
    final diff = popularity - 62.0;
    return exp(-(diff * diff) / (2.0 * 14.0 * 14.0));
  }

  /// Canonical fingerprint for permanent exclusion: normalized title + movie/composer
  String get canonicalFingerprint {
    final t = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final m = movie.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final c = composer.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${t}_${m.isNotEmpty ? m : c}';
  }

  factory TeluguSong.fromJson(Map<String, dynamic> json) {
    final rawTitle = (json['title'] as String?) ?? 'Unknown Song';
    final cleanT = rawTitle.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final rawMovie = (json['movie'] as String?) ?? (json['album'] as String?) ?? 'Cinema Track';
    final cleanM = rawMovie.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    return TeluguSong(
      id: (json['id'] as String?) ?? '',
      title: cleanT,
      movie: cleanM,
      year: (json['year'] as num?)?.toInt() ?? 2000,
      decade: (json['decade'] as String?) ?? '2000s',
      composer: (json['composer'] as String?) ?? (json['artist'] as String?) ?? 'Unknown Composer',
      singers: (json['singers'] as List<dynamic>?)
              ?.map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          [],
      mood: (json['mood'] as String?) ?? 'Melody',
      popularity: (json['popularity'] as num?)?.toInt() ?? 75,
      language: (json['language'] as String?) ?? 'telugu',
      bannerUrl: json['bannerUrl'] as String? ?? json['artworkUrl'] as String?,
      tempoBucket: json['tempoBucket'] as String?,
      vibeCategory: json['vibeCategory'] as String?,
      instrumentation: json['instrumentation'] as String?,
      bpm: (json['bpm'] as num?)?.toInt(),
      rhythmPulse: json['rhythmPulse'] as String?,
      harmonicMood: json['harmonicMood'] as String?,
      energyLevel: (json['energyLevel'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'movie': movie,
        'year': year,
        'decade': decade,
        'composer': composer,
        'singers': singers,
        'mood': mood,
        'popularity': popularity,
        'language': language,
        if (bannerUrl != null) 'bannerUrl': bannerUrl,
        if (tempoBucket != null) 'tempoBucket': tempoBucket,
        if (vibeCategory != null) 'vibeCategory': vibeCategory,
        if (instrumentation != null) 'instrumentation': instrumentation,
        if (bpm != null) 'bpm': bpm,
        if (rhythmPulse != null) 'rhythmPulse': rhythmPulse,
        if (harmonicMood != null) 'harmonicMood': harmonicMood,
        if (energyLevel != null) 'energyLevel': energyLevel,
      };

  /// Cleaned title for display and file system output
  String get cleanTitle {
    return title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Cleaned movie title for file system output
  String get cleanMovie {
    return movie.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalized key for robust deduplication across local shards and live search APIs
  String get normalizedDedupeKey => '${title.toLowerCase().trim()}_${movie.toLowerCase().trim()}';

  /// Output file base name: "${cleanTitle} - ${cleanMovie}"
  String get outputFileName => cleanMovie.isNotEmpty && cleanMovie != 'Unknown' ? '$cleanTitle - $cleanMovie' : '$cleanTitle - $composer';

  /// Standardized ytsearch1 search query constructed from song metadata
  String get searchQuery {
    if (language.toLowerCase() == 'english') {
      return 'ytsearch1:$title $composer official audio';
    }
    final langLabel = language.isNotEmpty
        ? (language.substring(0, 1).toUpperCase() + language.substring(1).toLowerCase())
        : 'Telugu';
    return 'ytsearch1:$title $movie $composer $langLabel official audio song';
  }

  /// Compact era badge for card UI: "1991 • Aditya 369"
  String get eraBadge => movie.isNotEmpty ? '$year • $movie' : '$year • $composer';

  /// Formatted subtitle: "Ilaiyaraaja • S. P. Balasubrahmanyam, Jikki"
  String get subtitle {
    final s = singers.isNotEmpty ? singers.join(', ') : '';
    if (s.isNotEmpty && s != composer) {
      return '$composer • $s';
    }
    return composer;
  }
}

typedef SongItem = TeluguSong;
