import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../theme/pulse_theme.dart';
import 'track_artwork.dart';

class MiniPlayerWidget extends StatelessWidget {
  final VoidCallback onExpand;

  const MiniPlayerWidget({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;

    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, trackSnapshot) {
        final track = trackSnapshot.data;
        if (track == null) return const SizedBox.shrink();

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
                    final progress = (pos.inSeconds / durationSecs).clamp(0.0, 1.0);

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: PulseColors.surfaceContainerHigh.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x26FFFFFF), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.8),
                        blurRadius: 36,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: onExpand,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                // Album Art Artwork
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: PulseColors.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: TrackArtwork(
                                    thumbUrl: track.thumbnailUrl,
                                    width: 44,
                                    height: 44,
                                    borderRadius: 8,
                                    fallback: const Icon(Icons.graphic_eq, color: PulseColors.primaryMint, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Marquee & Artist stack with Pulsing Green Dot
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 6,
                                            height: 6,
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: isPlaying ? PulseColors.primaryMint : PulseColors.textMuted,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: PulseColors.textWhite,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${track.artist} • 320k Lossless',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: PulseColors.onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Skip Next
                                IconButton(
                                  icon: const Icon(Icons.skip_next, color: PulseColors.onSurfaceVariant, size: 22),
                                  onPressed: () => player.next(),
                                ),

                                // Play / Pause
                                GestureDetector(
                                  onTap: () => player.togglePlayPause(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: const BoxDecoration(
                                      color: PulseColors.primaryMint,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isPlaying ? Icons.pause : Icons.play_arrow,
                                      color: PulseColors.onPrimary,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),

                        // Bottom Edge-to-Edge Progress Bar in Mint
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 2.5,
                          backgroundColor: PulseColors.surfaceContainerHighest,
                          valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
                        ),
                      ],
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
}
