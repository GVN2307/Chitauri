import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/youtube_service.dart';
import '../theme/pulse_theme.dart';

class YouTubeSearchView extends StatefulWidget {
  final Function(DownloadTask task) onStartDownload;
  final List<DownloadTask> activeDownloads;

  const YouTubeSearchView({
    super.key,
    required this.onStartDownload,
    required this.activeDownloads,
  });

  @override
  State<YouTubeSearchView> createState() => _YouTubeSearchViewState();
}

class _YouTubeSearchViewState extends State<YouTubeSearchView> {
  final TextEditingController _queryController = TextEditingController();
  List<YouTubeVideoItem> _results = [];
  bool _isLoading = false;
  String _selectedCategory = 'All Results';

  final List<String> _categories = [
    'All Results',
    'Songs',
    'Podcasts',
    'Downloaded',
    'High Bitrate (320k)',
  ];

  @override
  void initState() {
    super.initState();
    _performSearch('Trending');
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });

    final items = await YouTubeService.instance.search(query);

    if (mounted) {
      setState(() {
        _results = items;
        _isLoading = false;
      });
    }
  }

  void _triggerDownload(YouTubeVideoItem item) {
    final task = DownloadTask(
      videoId: item.id,
      title: item.title,
      channel: item.channel,
      status: DownloadStatus.queued,
      statusText: 'Starting...',
      progress: 0.05,
    );
    widget.onStartDownload(task);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset('assets/logo.png', width: 20, height: 20, fit: BoxFit.cover),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Grabbing MP3: ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: PulseColors.primaryMint,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // App Top Header Bar (Matching Stitch: Logo + PulseMP3 + Search & Grab pill + Avatar)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: PulseColors.surface,
            border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset('assets/logo.png', width: 32, height: 32, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Chitauri',
                    style: TextStyle(
                      color: PulseColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: PulseColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'SEARCH & GRAB',
                      style: TextStyle(
                        color: PulseColors.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: PulseColors.primaryMint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: PulseColors.onPrimary, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Sticky Search Pill (Pill Shaped, Height: 52px, Elevated)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Container(
            height: 52,
            padding: const EdgeInsets.only(left: 16, right: 6),
            decoration: BoxDecoration(
              color: PulseColors.surfaceContainer,
              borderRadius: BorderRadius.circular(9999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: PulseColors.textMuted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    style: const TextStyle(color: PulseColors.textWhite, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search YouTube to grab MP3...',
                      hintStyle: TextStyle(color: Color(0x99BCCABB), fontSize: 13.5),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _performSearch(val.trim());
                      }
                    },
                  ),
                ),
                if (_queryController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, color: PulseColors.textMuted, size: 16),
                    onPressed: () {
                      _queryController.clear();
                      setState(() {});
                    },
                  ),
                // Inline Extraction Trigger (Bolt + Grab)
                GestureDetector(
                  onTap: () {
                    if (_queryController.text.trim().isNotEmpty) {
                      _performSearch(_queryController.text.trim());
                    }
                  },
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: PulseColors.primaryMint,
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: [
                        BoxShadow(
                          color: PulseColors.primaryMint.withOpacity(0.35),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset('assets/logo.png', width: 16, height: 16, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Grab',
                          style: TextStyle(
                            color: PulseColors.onPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Filter Pills Horizontal Bar
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, idx) {
              final cat = _categories[idx];
              final isSelected = _selectedCategory == cat;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedCategory = cat;
                  });
                  if (cat != 'All Results') {
                    _performSearch(cat);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? PulseColors.primaryMint : PulseColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(9999),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: PulseColors.primaryMint.withOpacity(0.25),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: PulseColors.onPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? PulseColors.onPrimary : PulseColors.onSurfaceVariant,
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Realtime Conversion Metrics Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.sensors, color: PulseColors.primaryMint, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'CHITAURI AUDIO • LOSSLESS MP3',
                    style: TextStyle(
                      color: PulseColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
              Text(
                '${_results.length} Streams Detected',
                style: const TextStyle(
                  color: PulseColors.primaryMint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Center Conversion & Extraction Queue Feed
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: PulseColors.primaryMint),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  itemCount: _results.length + 1, // +1 for the batch extraction pill
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    if (idx == _results.length) {
                      // Extraction Batch Utility Pill Bar
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: PulseColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.auto_fix_high, color: PulseColors.primaryMint, size: 22),
                                SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Batch Extraction Mode',
                                      style: TextStyle(color: PulseColors.textWhite, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Extract all audios directly to offline storage',
                                      style: TextStyle(color: PulseColors.onSurfaceVariant, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            ElevatedButton(
                              onPressed: () {
                                for (final r in _results.take(3)) {
                                  _triggerDownload(r);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: PulseColors.surfaceContainerHighest,
                                foregroundColor: PulseColors.primaryMint,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              child: const Text('Grab All', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    }

                    final item = _results[idx];
                    final activeTask = widget.activeDownloads.firstWhere(
                      (d) => d.videoId == item.id,
                      orElse: () => DownloadTask(videoId: '', title: '', channel: ''),
                    );
                    final isDownloading = activeTask.videoId.isNotEmpty && activeTask.status == DownloadStatus.downloading;
                    final isCompleted = activeTask.videoId.isNotEmpty && activeTask.status == DownloadStatus.completed;

                    return GestureDetector(
                      onTap: () {
                        if (isDownloading) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Currently grabbing MP3: ${(activeTask.progress * 100).toInt()}%'),
                              backgroundColor: PulseColors.surfaceContainerHigh,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        } else {
                          // Clicked on video -> Directly download MP3! (Do not play video)
                          _triggerDownload(item);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: PulseColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDownloading ? PulseColors.primaryMint.withOpacity(0.4) : const Color(0x1AFFFFFF),
                            width: 1,
                          ),
                          boxShadow: isDownloading
                              ? [
                                  BoxShadow(
                                    color: PulseColors.primaryMint.withOpacity(0.12),
                                    blurRadius: 20,
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                        children: [
                          Row(
                            children: [
                              // 16:9 Thumbnail Preview with Duration
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 96,
                                      height: 64,
                                      color: PulseColors.surfaceContainerHighest,
                                      child: Image.network(
                                        item.thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(Icons.music_note, color: PulseColors.textMuted, size: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.all(4),
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: PulseColors.surfaceContainerLowest.withOpacity(0.85),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.duration,
                                      style: TextStyle(
                                        color: isDownloading ? PulseColors.primaryMint : PulseColors.onSurface,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),

                              // Metadata Column
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: PulseColors.textWhite,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      isDownloading
                                          ? '${item.channel} • Converting'
                                          : '${item.channel} • ${item.views} views',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: PulseColors.onSurfaceVariant, fontSize: 11),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isDownloading
                                                ? PulseColors.primaryMint.withOpacity(0.12)
                                                : PulseColors.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isDownloading)
                                                Container(
                                                  width: 5,
                                                  height: 5,
                                                  margin: const EdgeInsets.only(right: 4),
                                                  decoration: const BoxDecoration(
                                                    color: PulseColors.primaryMint,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              Text(
                                                isDownloading ? 'Downloading' : 'Compact Audio',
                                                style: const TextStyle(
                                                  color: PulseColors.primaryMint,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          '~3.2 MB',
                                          style: TextStyle(color: PulseColors.onSurfaceVariant, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Action Button: Circular Download / Progress Ring / Saved Pill
                              if (isDownloading)
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CircularProgressIndicator(
                                        value: activeTask.progress,
                                        strokeWidth: 3.5,
                                        valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
                                        backgroundColor: PulseColors.surfaceContainerHighest,
                                      ),
                                      Text(
                                        '${(activeTask.progress * 100).toInt()}%',
                                        style: const TextStyle(
                                          color: PulseColors.primaryMint,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (isCompleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: PulseColors.primaryMint,
                                    borderRadius: BorderRadius.circular(9999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: PulseColors.primaryMint.withOpacity(0.25),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, color: PulseColors.onPrimary, size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Saved',
                                        style: TextStyle(color: PulseColors.onPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                GestureDetector(
                                  onTap: () => _triggerDownload(item),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: PulseColors.surfaceContainerHigh,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: PulseColors.primaryMint.withOpacity(0.15),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                    child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.download, color: PulseColors.primaryMint, size: 18),
                                        Text(
                                          'MP3',
                                          style: TextStyle(color: PulseColors.primaryMint, fontSize: 8, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          // Inline bottom dynamic progress bar when active
                          if (isDownloading)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9999),
                                child: LinearProgressIndicator(
                                  value: activeTask.progress,
                                  minHeight: 3.5,
                                  valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
                                  backgroundColor: PulseColors.surfaceContainerHighest,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                  },
                ),
        ),
      ],
    );
  }
}
