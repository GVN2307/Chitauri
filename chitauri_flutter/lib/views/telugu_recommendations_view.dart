import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telugu_song.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/storage_service.dart';
import '../services/taste_profiler.dart';
import '../services/telugu_catalog_service.dart';
import '../services/youtube_service.dart';
import '../theme/pulse_theme.dart';
import '../widgets/cached_banner_image.dart';

enum RecommendationViewMode {
  largeBanner,
  iconGrid,
  compactList,
}

enum RecommendationSortOption {
  recommended,
  titleAsc,
  titleDesc,
  latestFirst,
  oldestFirst,
}

class TeluguRecommendationsView extends StatefulWidget {
  final VoidCallback? onSwitchToLibrary;
  final Function(DownloadTask task)? onStartDownload;

  const TeluguRecommendationsView({
    super.key,
    this.onSwitchToLibrary,
    this.onStartDownload,
  });

  @override
  State<TeluguRecommendationsView> createState() => _TeluguRecommendationsViewState();
}

class _TeluguRecommendationsViewState extends State<TeluguRecommendationsView>
    with AutomaticKeepAliveClientMixin {
  final TeluguCatalogService _catalogService = TeluguCatalogService.instance;
  final TasteProfiler _tasteProfiler = TasteProfiler.instance;

  @override
  bool get wantKeepAlive => true;

  String _selectedLanguage = 'all'; // 'all', 'telugu', 'tamil', 'malayalam', 'kannada', 'hindi', 'english'
  String _selectedFilter = 'For You';
  RecommendationViewMode _viewMode = RecommendationViewMode.iconGrid;
  RecommendationSortOption _sortOption = RecommendationSortOption.recommended;

  bool _isLoading = true;
  int _refreshCounter = 0;
  List<ScoredTeluguSong> _allRankedSongs = [];
  List<DynamicPlaylistMix> _dynamicMixes = [];
  List<String> _topComposers = [];

  // Lazy loading pagination
  final ScrollController _scrollController = ScrollController();
  int _displayedCount = 20;
  bool _isLoadingMore = false;

  // Active downloads map
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadStatusText = {};
  final Set<String> _completedSongIds = {};

  StreamSubscription<DownloadProgressEvent>? _progressSub;

  @override
  void initState() {
    super.initState();
    _loadSavedViewMode();
    _initData();
    _subscribeToProgress();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadSavedViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeIndex = prefs.getInt('for_you_view_mode');
      if (modeIndex != null && modeIndex >= 0 && modeIndex < RecommendationViewMode.values.length) {
        if (mounted) {
          setState(() {
            _viewMode = RecommendationViewMode.values[modeIndex];
          });
        }
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.75) {
      if (!_isLoadingMore && _displayedCount < _allRankedSongs.length) {
        setState(() {
          _displayedCount = (_displayedCount + 20).clamp(0, _allRankedSongs.length);
        });
      } else if (!_isLoadingMore && _displayedCount >= _allRankedSongs.length) {
        _fetchMoreLiveSongs();
      }
    }
  }

  Future<void> _fetchMoreLiveSongs() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      await _catalogService.loadMoreLiveSongs(language: _selectedLanguage, offset: _displayedCount);
      _applyFilterAndSort();
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  void _subscribeToProgress() {
    _progressSub = YouTubeService.instance.downloadProgressStream.listen((event) {
      if (mounted) {
        setState(() {
          if (event.isCompleted) {
            _downloadProgress.remove(event.songId);
            _downloadStatusText.remove(event.songId);
            _completedSongIds.add(event.songId);
          } else if (event.isFailed) {
            _downloadProgress.remove(event.songId);
            _downloadStatusText.remove(event.songId);
          } else {
            _downloadProgress[event.songId] = event.progress;
            _downloadStatusText[event.songId] = event.statusText;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    await _tasteProfiler.initialize();
    await _catalogService.initializeCatalog();
    _topComposers = _tasteProfiler.getTopComposers(limit: 5);
    _applyFilterAndSort();
    _isLoading = false;
  }

  void _applyFilterAndSort() {
    final all = _catalogService.getSongsByLanguage(_selectedLanguage);
    List<TeluguSong> filteredPool = [];

    switch (_selectedFilter) {
      case 'For You':
        filteredPool = all;
        break;
      case '70s–80s Retro':
        filteredPool = _catalogService.getRetroSongs(language: _selectedLanguage);
        break;
      case '90s–00s Gold':
        filteredPool = _catalogService.getGoldSongs(language: _selectedLanguage);
        break;
      case '2010s–20s Hits':
        filteredPool = _catalogService.getModernHits(language: _selectedLanguage);
        break;
      default:
        filteredPool = _catalogService.getSongsByComposer(_selectedFilter, language: _selectedLanguage);
        break;
    }

    // Rank candidate songs using TasteProfiler with Underrated Gem Boost & Anti-Boredom Decay
    var ranked = _tasteProfiler.rankSongs(filteredPool, excludeDownloaded: false);

    // Apply Sorting
    switch (_sortOption) {
      case RecommendationSortOption.recommended:
        // Already scored by TasteProfiler
        break;
      case RecommendationSortOption.titleAsc:
        ranked.sort((a, b) => a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase()));
        break;
      case RecommendationSortOption.titleDesc:
        ranked.sort((a, b) => b.song.title.toLowerCase().compareTo(a.song.title.toLowerCase()));
        break;
      case RecommendationSortOption.latestFirst:
        ranked.sort((a, b) => b.song.year.compareTo(a.song.year));
        break;
      case RecommendationSortOption.oldestFirst:
        ranked.sort((a, b) => a.song.year.compareTo(b.song.year));
        break;
    }

    // Generate Dynamic Auto-Playlists for top carousel
    _dynamicMixes = _tasteProfiler.generateDynamicMixes(all, refreshCounter: _refreshCounter);

    setState(() {
      _allRankedSongs = ranked;
      _displayedCount = 20.clamp(0, _allRankedSongs.length);
    });
  }

  Future<void> _onSongCardTap(TeluguSong song) async {
    final isDownloaded = _completedSongIds.contains(song.id) || _tasteProfiler.isSongDownloaded(song);
    if (isDownloaded) {
      final tracks = await StorageService.instance.loadTracks();
      final match = tracks.firstWhere(
        (t) => t.id == song.id || t.title.toLowerCase().contains(song.cleanTitle.toLowerCase()),
        orElse: () => tracks.isNotEmpty ? tracks.first : Track(
          id: song.id,
          title: song.title,
          artist: song.subtitle,
          filePath: '',
          durationSecs: 240,
          fileSize: 0,
        ),
      );
      if (match.filePath.isNotEmpty) {
        await AudioPlayerService.instance.playTrack(match, tracks);
        return;
      }
    }

    _triggerDownload(song);
  }

  Future<void> _triggerDownload(TeluguSong song) async {
    if (_downloadProgress.containsKey(song.id)) return;

    // Immediate exclusion from "For You" feed
    _tasteProfiler.addDownloadedSong(song.id, song.title);

    setState(() {
      _downloadProgress[song.id] = 0.05;
      _downloadStatusText[song.id] = '0%';
      // Remove immediately from UI feed so user gets instant responsive feedback
      _allRankedSongs.removeWhere((item) => item.song.id == song.id);
    });

    if (widget.onStartDownload != null) {
      final task = DownloadTask(
        videoId: song.id,
        title: song.title,
        channel: song.subtitle,
        status: DownloadStatus.queued,
        songItem: song,
        artworkUrl: song.bannerUrl,
      );
      widget.onStartDownload!(task);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.downloading_rounded, color: PulseColors.onPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Added "${song.title}" to Download Queue',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: PulseColors.primaryMint,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      await YouTubeService.instance.downloadTeluguRecommendation(
        song,
        onProgress: (progress, statusText) {
          if (mounted) {
            setState(() {
              _downloadProgress[song.id] = progress;
              _downloadStatusText[song.id] = statusText;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadProgress.remove(song.id);
          _downloadStatusText.remove(song.id);
          _completedSongIds.add(song.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: PulseColors.onPrimary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved "${song.title}" to Offline Library',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: PulseColors.primaryMint,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(song.id);
          _downloadStatusText.remove(song.id);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to grab "${song.title}": ${e.toString().replaceAll('Exception:', '').trim()}',
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showDynamicMixModal(DynamicPlaylistMix mix) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        List<TeluguSong> currentTracks = List.from(mix.tracks);
        bool isLoadingMoreInModal = false;

        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.70,
              minChildSize: 0.40,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, sheetScrollController) {
                sheetScrollController.addListener(() {
                  if (sheetScrollController.position.pixels >= sheetScrollController.position.maxScrollExtent * 0.8) {
                    if (!isLoadingMoreInModal && currentTracks.length < 50) {
                      setModalState(() => isLoadingMoreInModal = true);
                      final allSongs = _catalogService.getSongsByLanguage(_selectedLanguage);
                      final nextSeedMixes = _tasteProfiler.generateDynamicMixes(
                        allSongs,
                        refreshCounter: _refreshCounter + currentTracks.length,
                      );
                      final match = nextSeedMixes.firstWhere(
                        (m) => m.title == mix.title,
                        orElse: () => nextSeedMixes.first,
                      );
                      final fresh = match.tracks.where((t) => !currentTracks.any((c) => c.id == t.id)).toList();
                      setModalState(() {
                        if (fresh.isNotEmpty) {
                          currentTracks.addAll(fresh);
                        }
                        isLoadingMoreInModal = false;
                      });
                    }
                  }
                });

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: PulseColors.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: PulseColors.primaryMint.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.auto_awesome, color: PulseColors.primaryMint, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mix.title,
                                  style: const TextStyle(
                                    color: PulseColors.textWhite,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${currentTracks.length} tracks • ${mix.subtitle}',
                                  style: const TextStyle(color: PulseColors.textMuted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Download Full Mix Queue Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _queueFullMix(currentTracks);
                          },
                          icon: const Icon(Icons.download_rounded, color: PulseColors.onPrimary, size: 20),
                          label: Text(
                            'Download Full Mix Queue (${currentTracks.length} Songs)',
                            style: const TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PulseColors.primaryMint,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: PulseColors.borderSubtle),

                      // Songs List
                      Expanded(
                        child: ListView.separated(
                          controller: sheetScrollController,
                          itemCount: currentTracks.length + (isLoadingMoreInModal ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, idx) {
                            if (idx >= currentTracks.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: PulseColors.primaryMint),
                                  ),
                                ),
                              );
                            }
                            final song = currentTracks[idx];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedBannerImage(
                                  imageUrl: song.bannerUrl,
                                  width: 48,
                                  height: 48,
                                ),
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PulseColors.textWhite, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                song.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PulseColors.textMuted, fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.download_rounded, color: PulseColors.primaryMint, size: 22),
                                onPressed: () {
                                  _triggerDownload(song);
                                },
                              ),
                              onTap: () => _onSongCardTap(song),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _queueFullMix(List<TeluguSong> tracks) {
    int count = 0;
    for (final song in tracks) {
      if (!_tasteProfiler.isSongDownloaded(song)) {
        final task = DownloadTask(
          videoId: song.id,
          title: song.title,
          channel: song.subtitle,
          status: DownloadStatus.queued,
          statusText: 'In Queue',
          progress: 0.0,
        );
        widget.onStartDownload?.call(task);
        count++;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added $count tracks to sequential download queue!'),
        backgroundColor: PulseColors.primaryMint,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: PulseColors.primaryMint),
      );
    }

    final visibleSongs = _allRankedSongs.take(_displayedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Header with Title, View Switcher & Sort Menu
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: PulseColors.primaryMint, size: 20),
              const SizedBox(width: 8),
              const Text(
                'For You',
                style: TextStyle(
                  color: PulseColors.textWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              // View Switcher Icon Button
              _buildViewSwitcherButton(),
              const SizedBox(width: 4),
              // Sort Menu Button
              _buildSortMenuButton(),
            ],
          ),
        ),

        // Horizontal Language Pills Bar (All, Telugu, Tamil, Malayalam, Kannada, Hindi, English)
        SizedBox(
          height: 34,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: [
              _buildLanguagePill('All', 'all'),
              const SizedBox(width: 6),
              _buildLanguagePill('Telugu', 'telugu'),
              const SizedBox(width: 6),
              _buildLanguagePill('Tamil', 'tamil'),
              const SizedBox(width: 6),
              _buildLanguagePill('Malayalam', 'malayalam'),
              const SizedBox(width: 6),
              _buildLanguagePill('Kannada', 'kannada'),
              const SizedBox(width: 6),
              _buildLanguagePill('Hindi', 'hindi'),
              const SizedBox(width: 6),
              _buildLanguagePill('English', 'english'),
            ],
          ),
        ),

        // Horizontal Dynamic Mix Banners Carousel
        if (_dynamicMixes.isNotEmpty)
          SizedBox(
            height: 110,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: _dynamicMixes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final mix = _dynamicMixes[index];
                return _buildDynamicMixCard(mix);
              },
            ),
          ),

        // Category Filter Chips
        _buildFilterChips(),

        // Feed of Songs (Large Banner / Grid / List)
        Expanded(
          child: RefreshIndicator(
            color: PulseColors.primaryMint,
            backgroundColor: PulseColors.cardSurface,
            onRefresh: () async {
              setState(() {
                _refreshCounter++;
                _tasteProfiler.clearSessionImpressions();
              });
              await _catalogService.refreshFromCloud(language: _selectedLanguage);
              _applyFilterAndSort();
            },
            child: visibleSongs.isEmpty
                ? const Center(
                    child: Text(
                      'No songs found for this selection.',
                      style: TextStyle(color: PulseColors.textMuted),
                    ),
                  )
                : _buildSongsView(visibleSongs),
          ),
        ),
      ],
    );
  }

  Widget _buildLanguagePill(String label, String value) {
    final isSelected = _selectedLanguage == value;
    return GestureDetector(
      onTap: () {
        if (_selectedLanguage != value) {
          setState(() {
            _selectedLanguage = value;
          });
          _applyFilterAndSort();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? PulseColors.primaryMint : PulseColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? PulseColors.primaryMint : PulseColors.cardBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? PulseColors.onPrimary : PulseColors.textWhite,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildViewSwitcherButton() {
    IconData icon;
    switch (_viewMode) {
      case RecommendationViewMode.largeBanner:
        icon = Icons.view_agenda_rounded;
        break;
      case RecommendationViewMode.iconGrid:
        icon = Icons.grid_view_rounded;
        break;
      case RecommendationViewMode.compactList:
        icon = Icons.view_headline_rounded;
        break;
    }

    return IconButton(
      icon: Icon(icon, color: PulseColors.primaryMint, size: 20),
      tooltip: 'Switch View Mode',
      onPressed: () {
        setState(() {
          if (_viewMode == RecommendationViewMode.largeBanner) {
            _viewMode = RecommendationViewMode.iconGrid;
          } else if (_viewMode == RecommendationViewMode.iconGrid) {
            _viewMode = RecommendationViewMode.compactList;
          } else {
            _viewMode = RecommendationViewMode.largeBanner;
          }
        });
        SharedPreferences.getInstance().then(
          (p) => p.setInt('for_you_view_mode', _viewMode.index),
        );
      },
    );
  }

  Widget _buildSortMenuButton() {
    return PopupMenuButton<RecommendationSortOption>(
      icon: const Icon(Icons.sort_rounded, color: PulseColors.textWhite, size: 20),
      tooltip: 'Sort Songs',
      color: PulseColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (opt) {
        setState(() {
          _sortOption = opt;
        });
        _applyFilterAndSort();
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(
          value: RecommendationSortOption.recommended,
          child: Text('Recommended For You', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: RecommendationSortOption.titleAsc,
          child: Text('Title (A–Z)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: RecommendationSortOption.titleDesc,
          child: Text('Title (Z–A)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: RecommendationSortOption.latestFirst,
          child: Text('Latest First (2026 → 1970)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
        ),
        const PopupMenuItem(
          value: RecommendationSortOption.oldestFirst,
          child: Text('Oldest First (1970 → 2026)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildDynamicMixCard(DynamicPlaylistMix mix) {
    return GestureDetector(
      onTap: () => _showDynamicMixModal(mix),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E2822),
              Color(0xFF16161A),
            ],
          ),
          border: Border.all(color: PulseColors.primaryMint.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: PulseColors.primaryMint, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mix.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PulseColors.textWhite,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _refreshCounter++;
                    });
                    _applyFilterAndSort();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: PulseColors.surfaceContainerHigh.withOpacity(0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh_rounded, color: PulseColors.primaryMint, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              mix.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: PulseColors.primaryMint.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${mix.tracks.length} Songs',
                    style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios_rounded, color: PulseColors.textZinc, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final List<String> allFilters = [
      'For You',
      '70s–80s Retro',
      '90s–00s Gold',
      '2010s–20s Hits',
      ..._topComposers,
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: allFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = allFilters[index];
          final isSelected = _selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedFilter = filter);
              _applyFilterAndSort();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? PulseColors.primaryMint : PulseColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? PulseColors.primaryMint : PulseColors.cardBorder,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? PulseColors.onPrimary : PulseColors.textWhite,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSongsView(List<ScoredTeluguSong> songs) {
    switch (_viewMode) {
      case RecommendationViewMode.largeBanner:
        return ListView.builder(
          key: const PageStorageKey('for_you_large_banner_list'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final item = songs[index];
            _tasteProfiler.recordSessionImpression(item.song.id);
            return _buildLargeBannerCard(item);
          },
        );

      case RecommendationViewMode.iconGrid:
        return GridView.builder(
          key: const PageStorageKey('for_you_icon_grid'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.76,
          ),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final item = songs[index];
            _tasteProfiler.recordSessionImpression(item.song.id);
            return _buildGridCard(item);
          },
        );

      case RecommendationViewMode.compactList:
        return ListView.builder(
          key: const PageStorageKey('for_you_compact_list'),
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final item = songs[index];
            _tasteProfiler.recordSessionImpression(item.song.id);
            return _buildCompactListCard(item);
          },
        );
    }
  }

  // 1. Large 16:9 Banner Card (Default)
  Widget _buildLargeBannerCard(ScoredTeluguSong item) {
    final song = item.song;
    final isSaved = _completedSongIds.contains(song.id) || _tasteProfiler.isSongDownloaded(song);
    final isDownloading = _downloadProgress.containsKey(song.id);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onSongCardTap(song),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 190,
      decoration: BoxDecoration(
        color: PulseColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PulseColors.cardBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background High-Res Banner
            CachedBannerImage(
              imageUrl: song.bannerUrl,
              width: double.infinity,
              height: 190,
              fit: BoxFit.cover,
            ),

            // Gradient Shade for High-Contrast Legibility
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x330B0B0E),
                    Color(0x990B0B0E),
                    Color(0xF00B0B0E),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),

            // Card Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Rationale Pill Badge
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: PulseColors.background.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: PulseColors.primaryMint.withOpacity(0.6), width: 1),
                        ),
                        child: Text(
                          item.recommendationReason,
                          style: const TextStyle(
                            color: PulseColors.primaryMint,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (song.language == 'english')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: PulseColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('EN', style: TextStyle(color: PulseColors.textMuted, fontSize: 10)),
                        ),
                    ],
                  ),

                  const Spacer(),

                  // Bottom Row: Details and Instant Action Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PulseColors.textWhite,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              song.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: PulseColors.textMuted, fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              song.eraBadge,
                              style: const TextStyle(color: PulseColors.textZinc, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // One-Tap Download Button
                      GestureDetector(
                        onTap: () => _onSongCardTap(song),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isSaved ? PulseColors.surfaceContainerHigh : PulseColors.primaryMint,
                            shape: BoxShape.circle,
                            boxShadow: [
                              if (!isSaved)
                                BoxShadow(
                                  color: PulseColors.primaryMint.withOpacity(0.4),
                                  blurRadius: 10,
                                ),
                            ],
                          ),
                          child: Center(
                            child: isDownloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: PulseColors.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    isSaved ? Icons.play_arrow_rounded : Icons.download_rounded,
                                    color: isSaved ? PulseColors.primaryMint : PulseColors.onPrimary,
                                    size: 24,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  // 2. Small Icon Grid Card
  Widget _buildGridCard(ScoredTeluguSong item) {
    final song = item.song;
    final isSaved = _completedSongIds.contains(song.id) || _tasteProfiler.isSongDownloaded(song);

    return Container(
      decoration: BoxDecoration(
        color: PulseColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PulseColors.cardBorder, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onSongCardTap(song),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedBannerImage(
                      imageUrl: song.bannerUrl,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: PulseColors.background.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          song.year.toString(),
                          style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PulseColors.textWhite, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(
                        isSaved ? Icons.check_circle_rounded : Icons.download_rounded,
                        color: PulseColors.primaryMint,
                        size: 16,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3. Compact List Card
  Widget _buildCompactListCard(ScoredTeluguSong item) {
    final song = item.song;
    final isSaved = _completedSongIds.contains(song.id) || _tasteProfiler.isSongDownloaded(song);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PulseColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PulseColors.cardBorder, width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedBannerImage(
            imageUrl: song.bannerUrl,
            width: 48,
            height: 48,
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PulseColors.textWhite, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${song.subtitle} • ${song.eraBadge}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: PulseColors.textMuted, fontSize: 11.5),
        ),
        trailing: IconButton(
          icon: Icon(
            isSaved ? Icons.play_arrow_rounded : Icons.download_rounded,
            color: PulseColors.primaryMint,
            size: 24,
          ),
          onPressed: () => _onSongCardTap(song),
        ),
        onTap: () => _onSongCardTap(song),
      ),
    );
  }
}
