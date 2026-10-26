import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/storage_service.dart';
import '../theme/pulse_theme.dart';

class QueueView extends StatefulWidget {
  final List<DownloadTask> tasks;
  final VoidCallback onClearCompleted;
  final Function(int pid)? onKillProcess;

  const QueueView({
    super.key,
    required this.tasks,
    required this.onClearCompleted,
    this.onKillProcess,
  });

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  @override
  Widget build(BuildContext context) {
    final active = widget.tasks.where((t) => t.status == DownloadStatus.downloading).toList();
    final queued = widget.tasks.where((t) => t.status == DownloadStatus.queued).toList();
    final completed = widget.tasks.where((t) => t.status == DownloadStatus.completed).toList();
    final failed = widget.tasks.where((t) => t.status == DownloadStatus.failed || t.status == DownloadStatus.cancelled).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Download Manager Stats Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1AFFFFFF)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('DOWNLOADING', active.length.toString(), PulseColors.primaryMint),
                Container(width: 1, height: 32, color: const Color(0x1AFFFFFF)),
                _buildStatItem('IN QUEUE', queued.length.toString(), PulseColors.textWhite),
                Container(width: 1, height: 32, color: const Color(0x1AFFFFFF)),
                _buildStatItem('COMPLETED', completed.length.toString(), PulseColors.primaryMintBright),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Active Download Section
          if (active.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.downloading, color: PulseColors.primaryMint, size: 20),
                SizedBox(width: 8),
                Text(
                  'ACTIVE DOWNLOAD',
                  style: TextStyle(
                    color: PulseColors.primaryMint,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...active.map((task) => _buildActiveTaskCard(task)),
            const SizedBox(height: 20),
          ],

          // Queued Downloads Section (Multiple concurrent downloads)
          if (queued.isNotEmpty) ...[
            const Row(
              children: [
                Icon(Icons.queue_music, color: PulseColors.textMuted, size: 20),
                SizedBox(width: 8),
                Text(
                  'WAITING IN QUEUE (FIFO)',
                  style: TextStyle(
                    color: PulseColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...queued.asMap().entries.map((entry) => _buildQueuedTaskCard(entry.value, position: entry.key + 1)),
            const SizedBox(height: 20),
          ],

          // Completed Downloads Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: PulseColors.primaryMint, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'COMPLETED (${completed.length})',
                    style: const TextStyle(
                      color: PulseColors.textWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              if (completed.isNotEmpty)
                TextButton(
                  onPressed: widget.onClearCompleted,
                  child: const Text('Clear Finished', style: TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (completed.isEmpty && active.isEmpty && queued.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: PulseColors.surfaceContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_download_outlined, color: PulseColors.primaryMint, size: 32),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No Active Downloads',
                      style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Songs you download will appear here with live progress and queue management.',
                      style: TextStyle(color: PulseColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ...completed.map((task) => _buildCompletedTaskCard(task)),

          // Cancelled / Failed Section
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'CANCELLED / FAILED',
              style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...failed.map((task) => _buildFailedTaskCard(task)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String count, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: PulseColors.textMuted, fontSize: 9.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildActiveTaskCard(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PulseColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PulseColors.primaryMint.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo.png', width: 38, height: 38, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: PulseColors.primaryMint.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'PID #${task.pid}',
                            style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'DOWNLOADING',
                          style: TextStyle(color: PulseColors.primaryMintBright, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    Text(
                      task.channel.isNotEmpty ? task.channel : 'Downloading audio',
                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(task.progress * 100).toInt()}%',
                    style: const TextStyle(color: PulseColors.primaryMint, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (widget.onKillProcess != null)
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 18),
                      tooltip: 'Cancel Download',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => widget.onKillProcess!(task.pid),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 6,
              backgroundColor: PulseColors.surfaceContainerLowest,
              valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueuedTaskCard(DownloadTask task, {int position = 1}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PulseColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'PID #${task.pid}',
              style: const TextStyle(color: PulseColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PulseColors.textWhite, fontSize: 13),
                ),
                Text(
                  task.channel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: PulseColors.primaryMint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              position == 1 ? 'Next Up' : '#$position in Queue',
              style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
          if (widget.onKillProcess != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close, color: PulseColors.textMuted, size: 16),
              tooltip: 'Cancel PID #${task.pid}',
              onPressed: () => widget.onKillProcess!(task.pid),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompletedTaskCard(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PulseColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: PulseColors.primaryMint.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.music_note, color: PulseColors.primaryMint, size: 20),
        ),
        title: Text(
          task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: Text(
          'PID #${task.pid} • Terminated Successfully',
          style: const TextStyle(color: PulseColors.primaryMint, fontSize: 11),
        ),
        trailing: ElevatedButton(
          onPressed: () async {
            final tracks = await StorageService.instance.loadTracks();
            final tr = tracks.firstWhere((t) => t.id == task.videoId, orElse: () => tracks.first);
            AudioPlayerService.instance.playTrack(tr, tracks);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: PulseColors.primaryMint,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
          child: const Text('Play', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildFailedTaskCard(DownloadTask task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PulseColors.textWhite, fontSize: 12.5),
                ),
                Text(
                  'PID #${task.pid} • ${task.status == DownloadStatus.cancelled ? 'Download Cancelled' : 'Download Failed'}',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 10.5),
                ),
              ],
            ),
          ),
          Text(
            task.status == DownloadStatus.cancelled ? 'CANCELLED' : 'FAILED',
            style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
