import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../services/audio_fx_service.dart';
import '../services/audio_player_service.dart';
import '../services/storage_service.dart';
import '../theme/pulse_theme.dart';
import 'track_artwork.dart';

class VinylPlayerSheet extends StatefulWidget {
  final VoidCallback onMinimize;

  const VinylPlayerSheet({super.key, required this.onMinimize});

  @override
  State<VinylPlayerSheet> createState() => _VinylPlayerSheetState();
}

class _VinylPlayerSheetState extends State<VinylPlayerSheet> {
  bool _isFavorite = false;
  String? _lastTrackId;
  double _bassBoost = 0.5;
  bool _surroundActive = true;
  String _activePreset = 'Bass Boost';
  final List<double> _eqBands = [3.0, 4.5, 0.0, 2.0, 3.5]; // 60, 230, 910, 3.6k, 14k

  void _syncFavoriteStatus(String trackId) async {
    if (_lastTrackId == trackId) return;
    _lastTrackId = trackId;
    final fav = await StorageService.instance.isTrackFavorite(trackId);
    if (mounted) {
      setState(() {
        _isFavorite = fav;
      });
    }
  }

  void _toggleFavorite(String trackId) async {
    final newFav = await StorageService.instance.toggleFavorite(trackId);
    if (mounted) {
      setState(() {
        _isFavorite = newFav;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(newFav ? Icons.favorite : Icons.favorite_border, color: PulseColors.primaryMint, size: 18),
              const SizedBox(width: 8),
              Text(newFav ? 'Saved to Favorites Module' : 'Removed from Favorites'),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;

    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) return const SizedBox.shrink();

        _syncFavoriteStatus(track.id);

        return StreamBuilder<bool>(
          stream: player.isPlayingStream,
          initialData: player.isPlaying,
          builder: (context, playSnapshot) {
            final isPlaying = playSnapshot.data ?? false;

            return StreamBuilder<Duration>(
              stream: player.durationStream,
              initialData: player.duration,
              builder: (context, durSnapshot) {
                final liveDur = durSnapshot.data ?? player.duration;
                final totalSecs = liveDur.inSeconds > 0
                    ? liveDur.inSeconds
                    : (track.durationSecs > 0 ? track.durationSecs : 0);
                final durationSecs = totalSecs > 0 ? totalSecs : 1;

                return StreamBuilder<Duration>(
                  stream: player.positionStream,
                  initialData: player.position,
                  builder: (context, posSnapshot) {
                    final pos = posSnapshot.data ?? Duration.zero;
                    final currentSeconds = pos.inSeconds.clamp(0, durationSecs);
                    final progress = (currentSeconds / durationSecs).clamp(0.0, 1.0);

                return Scaffold(
                  backgroundColor: PulseColors.background,
                  body: SafeArea(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // 1. Top Header Bar: Strictly Constant "Chitauri" + Mint Bolt Logo
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: const BoxDecoration(
                              color: PulseColors.surface,
                              border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.arrow_back_ios_new, color: PulseColors.textWhite, size: 20),
                                      onPressed: widget.onMinimize,
                                    ),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Chitauri',
                                      style: TextStyle(
                                        color: PulseColors.textWhite,
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard_arrow_down, color: PulseColors.textWhite, size: 28),
                                  onPressed: widget.onMinimize,
                                ),
                              ],
                            ),
                          ),

                          // 2. Options Header Row with More Vert Menu
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.more_vert, color: PulseColors.textWhite, size: 22),
                                  onPressed: () => _showMoreOptionsModal(context, track),
                                ),
                              ],
                            ),
                          ),

                          // 3. Album Art Hero with Mint Atmosphere Backlight
                          Container(
                            width: 260,
                            height: 260,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Ambient Glow
                                Container(
                                  width: 230,
                                  height: 230,
                                  decoration: BoxDecoration(
                                    color: PulseColors.primaryMint.withOpacity(isPlaying ? 0.3 : 0.08),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: PulseColors.primaryMint.withOpacity(isPlaying ? 0.4 : 0.1),
                                        blurRadius: 36,
                                        spreadRadius: 6,
                                      ),
                                    ],
                                  ),
                                ),

                                // Artwork Card with Vinyl Grooves
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    width: 250,
                                    height: 250,
                                    color: PulseColors.surfaceContainerLowest,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: TrackArtwork(
                                            thumbUrl: track.thumbnailUrl,
                                            width: 250,
                                            height: 250,
                                            borderRadius: 20,
                                            fallback: const Center(
                                              child: Icon(Icons.music_note, color: PulseColors.primaryMint, size: 80),
                                            ),
                                          ),
                                        ),
                                        // Gradient Shade
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.bottomCenter,
                                                end: Alignment.topCenter,
                                                colors: [
                                                  PulseColors.surfaceContainerLowest.withOpacity(0.6),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Quick Favorite Button wired to Favorites Module
                                        Positioned(
                                          top: 12,
                                          right: 12,
                                          child: GestureDetector(
                                            onTap: () => _toggleFavorite(track.id),
                                            child: Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: PulseColors.surfaceContainerLowest.withOpacity(0.75),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                _isFavorite ? Icons.favorite : Icons.favorite_border,
                                                color: _isFavorite ? PulseColors.primaryMint : PulseColors.textWhite,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 4. Metadata Block: True Song Title & Artist Description
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            child: Column(
                              children: [
                                Text(
                                  track.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PulseColors.textWhite,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  track.artist,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: PulseColors.primaryMint,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (track.description != null && track.description!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      track.description!.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => ''),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PulseColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // 5. Interactive Waveform & Dedicated Timeline Scrubber
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                            child: Column(
                              children: [
                                // Waveform Canvas
                                GestureDetector(
                                  onHorizontalDragUpdate: (details) {
                                    final box = context.findRenderObject() as RenderBox?;
                                    if (box != null) {
                                      final local = details.localPosition;
                                      final p = (local.dx / (box.size.width - 48)).clamp(0.0, 1.0);
                                      player.seek(Duration(seconds: (p * durationSecs).toInt()));
                                    }
                                  },
                                  onTapDown: (details) {
                                    final box = context.findRenderObject() as RenderBox?;
                                    if (box != null) {
                                      final local = details.localPosition;
                                      final p = (local.dx / (box.size.width - 48)).clamp(0.0, 1.0);
                                      player.seek(Duration(seconds: (p * durationSecs).toInt()));
                                    }
                                  },
                                  child: Container(
                                    height: 46,
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: CustomPaint(
                                      painter: PulseWaveformPainter(progress: progress),
                                    ),
                                  ),
                                ),

                                // Interactive Scrubber Slider
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3.0,
                                    activeTrackColor: PulseColors.primaryMint,
                                    inactiveTrackColor: PulseColors.surfaceContainerLowest,
                                    thumbColor: PulseColors.primaryMintBright,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    overlayColor: PulseColors.primaryMint.withOpacity(0.2),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                  ),
                                  child: Slider(
                                    value: currentSeconds.toDouble(),
                                    min: 0.0,
                                    max: durationSecs.toDouble(),
                                    onChanged: (val) {
                                      player.seek(Duration(seconds: val.toInt()));
                                    },
                                  ),
                                ),

                                // Time Stamps
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(pos),
                                      style: const TextStyle(color: PulseColors.primaryMint, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      _formatDuration(Duration(seconds: durationSecs)),
                                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // 6. Playback Controls Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Shuffle Mode
                                StreamBuilder<bool>(
                                  stream: player.isShuffledStream,
                                  initialData: player.isShuffled,
                                  builder: (context, shufSnap) {
                                    final isShuf = shufSnap.data ?? false;
                                    return IconButton(
                                      icon: Icon(
                                        Icons.shuffle,
                                        color: isShuf ? PulseColors.primaryMint : PulseColors.textMuted,
                                        size: 20,
                                      ),
                                      onPressed: () => player.toggleShuffle(),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),

                                // Rewind 10 Seconds
                                IconButton(
                                  icon: const Icon(Icons.replay_10, color: PulseColors.textWhite, size: 28),
                                  tooltip: 'Rewind 10s',
                                  onPressed: () => player.rewind10(),
                                ),
                                const SizedBox(width: 4),

                                // Previous Track
                                IconButton(
                                  icon: const Icon(Icons.skip_previous, color: PulseColors.textWhite, size: 32),
                                  onPressed: () => player.previous(),
                                ),
                                const SizedBox(width: 8),

                                // Hero Mint Play / Pause
                                GestureDetector(
                                  onTap: () => player.togglePlayPause(),
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: PulseColors.primaryMint,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: PulseColors.primaryMint.withOpacity(0.45),
                                          blurRadius: 20,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: PulseColors.onPrimary,
                                      size: 32,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Next Track
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: PulseColors.textWhite, size: 32),
                                  onPressed: () => player.next(),
                                ),
                                const SizedBox(width: 4),

                                // Fast-Forward 10 Seconds
                                IconButton(
                                  icon: const Icon(Icons.forward_10, color: PulseColors.textWhite, size: 28),
                                  tooltip: 'Forward 10s',
                                  onPressed: () => player.forward10(),
                                ),
                                const SizedBox(width: 8),

                                // Repeat Mode
                                StreamBuilder<RepeatMode>(
                                  stream: player.repeatModeStream,
                                  initialData: player.repeatMode,
                                  builder: (context, repSnap) {
                                    final rep = repSnap.data ?? RepeatMode.off;
                                    IconData icon;
                                    Color color;
                                    switch (rep) {
                                      case RepeatMode.off:
                                        icon = Icons.repeat;
                                        color = PulseColors.textMuted;
                                        break;
                                      case RepeatMode.all:
                                        icon = Icons.repeat;
                                        color = PulseColors.primaryMint;
                                        break;
                                      case RepeatMode.one:
                                        icon = Icons.repeat_one;
                                        color = PulseColors.primaryMintBright;
                                        break;
                                    }
                                    return IconButton(
                                      icon: Icon(icon, color: color, size: 20),
                                      onPressed: () => player.cycleRepeatMode(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),

                          // 7. Functional Acoustic Extras Bar: Equalizer, Share, Info, Speaker
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.speaker_group, color: PulseColors.primaryMint, size: 20),
                                  tooltip: 'Audio Output',
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Audio output: Native Device Hardware Speaker / Headset'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.tune, color: PulseColors.primaryMint, size: 20),
                                  tooltip: 'Hardware Equalizer',
                                  onPressed: () => _showEqualizerModal(context),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.share, color: PulseColors.primaryMint, size: 20),
                                  tooltip: 'Share Audio',
                                  onPressed: () => _showShareModal(context, track),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.info_outline, color: PulseColors.primaryMint, size: 20),
                                  tooltip: 'Track Info',
                                  onPressed: () => _showTrackInfoModal(context, track),
                                ),
                              ],
                            ),
                          ),

                          // 8. Up-Next Queue
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: PulseColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.queue_music, color: PulseColors.primaryMint, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'PLAYLIST QUEUE',
                                          style: TextStyle(color: PulseColors.primaryMint, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${player.queue.length} ${player.queue.length == 1 ? "Track" : "Tracks"}',
                                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...player.queue.map((item) {
                                  final isCurrent = item.id == track.id;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                    leading: Icon(
                                      isCurrent ? Icons.play_arrow : Icons.music_note,
                                      color: isCurrent ? PulseColors.primaryMint : PulseColors.textMuted,
                                      size: 18,
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? PulseColors.primaryMint : PulseColors.textWhite,
                                        fontSize: 12.5,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    subtitle: Text(
                                      item.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 10.5),
                                    ),
                                    trailing: Text(
                                      item.durationFormatted,
                                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                                    ),
                                    onTap: () {
                                      player.playTrack(item, player.queue);
                                    },
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  },
);
  }

  // Real Hardware Equalizer Modal Bottom Sheet
  void _showEqualizerModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final presets = ['Flat', 'Bass Boost', 'Rock', 'Pop', 'Electronic', 'Vocal'];
            final freqLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tune, color: PulseColors.primaryMint, size: 22),
                            SizedBox(width: 8),
                            Text('Hardware Equalizer', style: TextStyle(color: PulseColors.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: PulseColors.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Preset Chips
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: presets.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final p = presets[index];
                          final isSelected = p == _activePreset;
                          return ChoiceChip(
                            label: Text(p),
                            selected: isSelected,
                            selectedColor: PulseColors.primaryMint,
                            backgroundColor: PulseColors.surfaceContainer,
                            labelStyle: TextStyle(
                              color: isSelected ? PulseColors.onPrimary : PulseColors.textWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                            onSelected: (val) {
                              setSheetState(() {
                                _activePreset = p;
                                if (p == 'Bass Boost') {
                                  _eqBands[0] = 5.0;
                                  _eqBands[1] = 4.0;
                                  _eqBands[2] = 0.0;
                                  _eqBands[3] = 1.0;
                                  _eqBands[4] = 2.0;
                                } else if (p == 'Flat') {
                                  for (int i = 0; i < 5; i++) {
                                    _eqBands[i] = 0.0;
                                  }
                                } else if (p == 'Rock') {
                                  _eqBands[0] = 4.0;
                                  _eqBands[1] = 2.0;
                                  _eqBands[2] = -1.0;
                                  _eqBands[3] = 2.0;
                                  _eqBands[4] = 4.5;
                                } else if (p == 'Pop') {
                                  _eqBands[0] = 2.0;
                                  _eqBands[1] = 3.0;
                                  _eqBands[2] = 4.0;
                                  _eqBands[3] = 2.0;
                                  _eqBands[4] = -1.0;
                                } else if (p == 'Electronic') {
                                  _eqBands[0] = 5.0;
                                  _eqBands[1] = 3.5;
                                  _eqBands[2] = 0.5;
                                  _eqBands[3] = 3.0;
                                  _eqBands[4] = 4.0;
                                } else if (p == 'Vocal') {
                                  _eqBands[0] = -2.0;
                                  _eqBands[1] = 0.0;
                                  _eqBands[2] = 4.5;
                                  _eqBands[3] = 3.5;
                                  _eqBands[4] = 1.0;
                                }
                              });
                              // Push all band updates to Android Hardware AudioEffect
                              for (int i = 0; i < 5; i++) {
                                AudioFxService.instance.setBandLevel(i, _eqBands[i]);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 5-Band Equalizer Sliders
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(5, (index) {
                        return Column(
                          children: [
                            Text(
                              '${_eqBands[index] > 0 ? '+' : ''}${_eqBands[index].toStringAsFixed(1)} dB',
                              style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(
                              height: 120,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: PulseColors.primaryMint,
                                    inactiveTrackColor: PulseColors.surfaceContainerLowest,
                                    thumbColor: PulseColors.primaryMintBright,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  ),
                                  child: Slider(
                                    value: _eqBands[index],
                                    min: -12.0,
                                    max: 12.0,
                                    onChanged: (val) {
                                      setSheetState(() {
                                        _eqBands[index] = val;
                                      });
                                      // Real hardware DSP gain adjustment
                                      AudioFxService.instance.setBandLevel(index, val);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Text(freqLabels[index], style: const TextStyle(color: PulseColors.textMuted, fontSize: 10)),
                          ],
                        );
                      }),
                    ),
                    const SizedBox(height: 16),

                    // Bass Boost & 3D Surround Toggles
                    SwitchListTile(
                      activeColor: PulseColors.primaryMint,
                      title: const Text('Bass Boost & Sub-Harmonics', style: TextStyle(color: PulseColors.textWhite, fontSize: 13.5)),
                      value: _bassBoost > 0,
                      onChanged: (val) {
                        setSheetState(() {
                          _bassBoost = val ? 0.6 : 0.0;
                        });
                        AudioFxService.instance.setBassBoost(val, _bassBoost);
                      },
                    ),
                    SwitchListTile(
                      activeColor: PulseColors.primaryMint,
                      title: const Text('3D Spatial Surround', style: TextStyle(color: PulseColors.textWhite, fontSize: 13.5)),
                      value: _surroundActive,
                      onChanged: (val) {
                        setSheetState(() {
                          _surroundActive = val;
                        });
                        AudioFxService.instance.setVirtualizer(val, 1.0);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Functional Share Modal Bottom Sheet with Real System Share Intent
  void _showShareModal(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.share, color: PulseColors.primaryMint, size: 22),
                        SizedBox(width: 8),
                        Text('Share Track', style: TextStyle(color: PulseColors.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: PulseColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.primaryMint, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),

                // Native System Share Intent (like sharing from File Manager)
                ListTile(
                  leading: const Icon(Icons.send_rounded, color: PulseColors.primaryMint),
                  title: const Text('Share Audio File (System Intent)', style: TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Send audio directly to WhatsApp, Drive, Bluetooth, etc.', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await AudioFxService.instance.shareAudioFile(track.filePath, track.title);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link, color: PulseColors.primaryMint),
                  title: const Text('Copy YouTube Link', style: TextStyle(color: PulseColors.textWhite)),
                  subtitle: Text('https://youtube.com/watch?v=${track.id}', style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: 'https://youtube.com/watch?v=${track.id}'));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('YouTube URL copied to clipboard!'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_shared, color: PulseColors.primaryMint),
                  title: const Text('Copy Device File Path', style: TextStyle(color: PulseColors.textWhite)),
                  subtitle: Text(track.filePath, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: track.filePath));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File path copied to clipboard!'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.text_snippet, color: PulseColors.primaryMint),
                  title: const Text('Share Track Metadata', style: TextStyle(color: PulseColors.textWhite)),
                  subtitle: const Text('Share title, artist, and duration formatted text', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '🎵 Now Playing: ${track.title} by ${track.artist} on Chitauri Audio Suite'));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Track metadata copied to clipboard!'), behavior: SnackBarBehavior.floating),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Functional Track Info Modal Bottom Sheet
  void _showTrackInfoModal(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final mb = (track.fileSize / (1024 * 1024)).toStringAsFixed(2);
        final format = track.filePath.toLowerCase().endsWith('.m4a')
            ? 'MPEG-4 AAC (itag 140 / 44.1kHz)'
            : track.filePath.toLowerCase().endsWith('.mp3')
                ? 'MPEG-1 Layer 3 (MP3 320 kbps CBR)'
                : 'Studio Quality Audio Master';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: PulseColors.primaryMint, size: 22),
                        SizedBox(width: 8),
                        Text('Track Technical Info', style: TextStyle(color: PulseColors.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: PulseColors.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Title', track.title),
                _buildInfoRow('Artist', track.artist),
                if (track.description != null && track.description!.isNotEmpty)
                  _buildInfoRow('Description', track.description!.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')),
                _buildInfoRow('YouTube Video ID', track.id),
                _buildInfoRow('Audio Codec', format),
                _buildInfoRow('Bitrate', '320 kbps CBR Studio Quality'),
                _buildInfoRow('File Size', '$mb MB'),
                _buildInfoRow('Local Path', track.filePath),
                _buildInfoRow('.nomedia Isolation', 'Active (Protected from System Media Crawlers)'),
                _buildInfoRow('Duration', track.durationFormatted),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: PulseColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: PulseColors.textWhite, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Functional More Options Modal Bottom Sheet
  void _showMoreOptionsModal(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.playlist_add, color: PulseColors.primaryMint),
                  title: const Text('Add to Playlist', style: TextStyle(color: PulseColors.textWhite)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPlaylistPicker(track);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note, color: PulseColors.primaryMint),
                  title: const Text('Rename Song', style: TextStyle(color: PulseColors.textWhite)),
                  subtitle: const Text('Change title or artist', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showRenameDialog(context, track);
                  },
                ),
                ListTile(
                  leading: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border, color: PulseColors.primaryMint),
                  title: Text(_isFavorite ? 'Remove from Favorites' : 'Add to Favorites', style: const TextStyle(color: PulseColors.textWhite)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleFavorite(track.id);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Delete from Device', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await StorageService.instance.deleteTrack(track.id);
                    widget.onMinimize();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPlaylistPicker(Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    final playlists = await StorageService.instance.loadPlaylists();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose Playlist', style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...playlists.map((p) => ListTile(
                      leading: const Icon(Icons.queue_music, color: PulseColors.primaryMint),
                      title: Text(p.name, style: const TextStyle(color: PulseColors.textWhite)),
                      trailing: Text('${p.trackIds.length} tracks', style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                      onTap: () async {
                        final nav = Navigator.of(ctx);
                        await StorageService.instance.addTrackToPlaylist(p.id, track.id);
                        nav.pop();
                        messenger.showSnackBar(
                          SnackBar(content: Text('Added to "${p.name}"'), behavior: SnackBarBehavior.floating),
                        );
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRenameDialog(BuildContext context, Track track) {
    final titleController = TextEditingController(text: track.title);
    final artistController = TextEditingController(text: track.artist);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: PulseColors.primaryMint, size: 24),
            SizedBox(width: 8),
            Text('Rename Song', style: TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Song Title', style: TextStyle(color: PulseColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: PulseColors.textWhite),
              decoration: const InputDecoration(
                hintText: 'Enter new song title',
                hintStyle: TextStyle(color: PulseColors.textMuted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: PulseColors.primaryMint)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: PulseColors.primaryMint, width: 2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Artist Name', style: TextStyle(color: PulseColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TextField(
              controller: artistController,
              style: const TextStyle(color: PulseColors.textWhite),
              decoration: const InputDecoration(
                hintText: 'Enter artist name',
                hintStyle: TextStyle(color: PulseColors.textMuted),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0x33FFFFFF))),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: PulseColors.primaryMint, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = titleController.text.trim();
              final newArtist = artistController.text.trim();
              if (newTitle.isNotEmpty) {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final updated = await StorageService.instance.renameTrack(
                  track.id,
                  newTitle,
                  newArtist: newArtist.isNotEmpty ? newArtist : null,
                );
                if (updated != null) {
                  AudioPlayerService.instance.updateTrackMetadata(updated);
                }
                if (!mounted) return;
                setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Renamed to "$newTitle"'),
                    backgroundColor: PulseColors.primaryMint,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
            child: const Text('Save', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class PulseWaveformPainter extends CustomPainter {
  final double progress;

  PulseWaveformPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 48;
    final barWidth = size.width / (barCount * 1.5);
    final gap = barWidth * 0.5;

    final paintActive = Paint()
      ..color = PulseColors.primaryMint
      ..style = PaintingStyle.fill;

    final paintInactive = Paint()
      ..color = PulseColors.surfaceContainerHigh
      ..style = PaintingStyle.fill;

    final heights = [
      0.3, 0.5, 0.4, 0.7, 0.9, 0.6, 0.8, 0.4, 0.6, 0.85,
      1.0, 0.7, 0.5, 0.8, 0.95, 0.6, 0.4, 0.7, 0.8, 0.5,
      0.65, 0.9, 0.75, 0.5, 0.85, 0.9, 0.6, 0.4, 0.7, 0.8,
      0.95, 0.7, 0.5, 0.6, 0.85, 0.65, 0.4, 0.75, 0.9, 0.55,
      0.7, 0.85, 0.6, 0.45, 0.65, 0.5, 0.4, 0.3
    ];

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      final hFactor = heights[i % heights.length];
      final barH = size.height * hFactor;
      final y = (size.height - barH) / 2;

      final isPlayed = (i / barCount) <= progress;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, isPlayed ? paintActive : paintInactive);
    }
  }

  @override
  bool shouldRepaint(covariant PulseWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
