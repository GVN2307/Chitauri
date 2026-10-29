import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/youtube_service.dart';
import '../theme/pulse_theme.dart';
import 'track_artwork.dart';

class MiniPlayerWidget extends StatelessWidget {
  final VoidCallback onExpand;

  const MiniPlayerWidget({super.key, required this.onExpand});

  @override
  Widget build(BuildContext context) {
    final player = AudioPlayerService.instance;
    final ytService = YouTubeService.instance;

    return StreamBuilder<DownloadProgressEvent>(
      stream: ytService.downloadProgressStream,
      initialData: ytService.activeDownloadEvent,
      builder: (context, downloadSnapshot) {
        final downloadEvent = downloadSnapshot.data;
        final hasActiveDownload = downloadEvent != null &&
            !downloadEvent.isCompleted &&
            !downloadEvent.isFailed &&
            downloadEvent.progress < 1.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sticky Real-Time Download & FFmpeg Conversion Bar
            if (hasActiveDownload)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: PulseColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PulseColors.primaryMint.withOpacity(0.4), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: PulseColors.primaryMint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Grabbing: ${downloadEvent.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PulseColors.textWhite,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          downloadEvent.statusText,
                          style: const TextStyle(
                            color: PulseColors.primaryMint,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: downloadEvent.progress > 0 ? downloadEvent.progress : null,
                        minHeight: 3,
                        backgroundColor: PulseColors.surfaceContainerHighest,
                        valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
                      ),
                    ),
                  ],
                ),
              ),

            // Playback Mini Player
            StreamBuilder<Track?>(
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
                                color: PulseColors.cardSurface.withOpacity(0.95),
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
            ),
          ],
        );
      },
    );
  }
}
