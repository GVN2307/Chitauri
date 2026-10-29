import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../services/audio_player_service.dart';
import '../services/storage_service.dart';
import '../theme/pulse_theme.dart';
import '../widgets/track_artwork.dart';

enum LibraryViewMode { list, grid }

enum LibrarySortOption {
  dateNewest,
  dateOldest,
  titleAsc,
  titleDesc,
  yearOrDuration,
}

class LibraryView extends StatefulWidget {
  final List<Track> tracks;
  final Future<void> Function() onRefresh;
  final void Function(String trackId) onDelete;
  final void Function(List<String> trackIds)? onBatchDelete;

  const LibraryView({
    super.key,
    required this.tracks,
    required this.onRefresh,
    required this.onDelete,
    this.onBatchDelete,
  });

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchFilter = TextEditingController();
  List<Playlist> _playlists = [];
  List<Track> _favoriteTracks = [];
  Playlist? _selectedPlaylist;
  bool _isSelectionMode = false;
  final Set<String> _selectedTrackIds = {};
  LibraryViewMode _viewMode = LibraryViewMode.grid;
  LibrarySortOption _sortOption = LibrarySortOption.dateNewest;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadViewPreferences();
    _loadPlaylistsAndFavorites();
  }

  Future<void> _loadViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('library_view_mode');
      if (mode == 'list') {
        if (mounted) setState(() => _viewMode = LibraryViewMode.list);
      } else if (mode == 'grid') {
        if (mounted) setState(() => _viewMode = LibraryViewMode.grid);
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant LibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadPlaylistsAndFavorites();
  }

  Future<void> _loadPlaylistsAndFavorites() async {
    final pl = await StorageService.instance.loadPlaylists();
    final favs = await StorageService.instance.getFavoriteTracks();
    if (mounted) {
      setState(() {
        _playlists = pl;
        _favoriteTracks = favs;
        if (_selectedPlaylist != null) {
          _selectedPlaylist = pl.firstWhere(
            (p) => p.id == _selectedPlaylist!.id,
            orElse: () => _selectedPlaylist!,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchFilter.dispose();
    super.dispose();
  }

  void _showCreatePlaylistDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.playlist_add, color: PulseColors.primaryMint),
            SizedBox(width: 8),
            Text('New Playlist', style: TextStyle(color: PulseColors.textWhite, fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: PulseColors.textWhite),
          decoration: InputDecoration(
            hintText: 'Enter playlist name',
            hintStyle: const TextStyle(color: PulseColors.textMuted),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: PulseColors.primaryMint.withOpacity(0.5)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PulseColors.primaryMint),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final nav = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                await StorageService.instance.createPlaylist(name);
                nav.pop();
                _loadPlaylistsAndFavorites();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Created playlist "$name"'),
                    backgroundColor: PulseColors.primaryMint,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: PulseColors.primaryMint,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Create', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistSheet(Track track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final customPlaylists = _playlists.where((p) => p.id != 'favorites').toList();

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Track to Playlist',
                        style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: PulseColors.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.primaryMint, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: PulseColors.primaryMint.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: PulseColors.primaryMint),
                    ),
                    title: const Text('Create New Playlist', style: TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCreatePlaylistDialog();
                    },
                  ),
                  const Divider(color: Color(0x1AFFFFFF)),
                  Expanded(
                    child: customPlaylists.isEmpty
                        ? const Center(
                            child: Text('No custom playlists yet. Tap "Create New Playlist" above.', style: TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                          )
                        : ListView.builder(
                            itemCount: customPlaylists.length,
                            itemBuilder: (context, index) {
                              final pl = customPlaylists[index];
                              final alreadyAdded = pl.trackIds.contains(track.id);
                              return ListTile(
                                leading: const Icon(Icons.queue_music, color: PulseColors.textMuted),
                                title: Text(pl.name, style: const TextStyle(color: PulseColors.textWhite)),
                                subtitle: Text('${pl.trackIds.length} tracks', style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                                trailing: alreadyAdded
                                    ? const Icon(Icons.check_circle, color: PulseColors.primaryMint)
                                    : const Icon(Icons.add_circle_outline, color: PulseColors.textMuted),
                                onTap: () async {
                                  final nav = Navigator.of(ctx);
                                  final messenger = ScaffoldMessenger.of(context);
                                  if (!alreadyAdded) {
                                    await StorageService.instance.addTrackToPlaylist(pl.id, track.id);
                                    _loadPlaylistsAndFavorites();
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Added to "${pl.name}"'),
                                        backgroundColor: PulseColors.primaryMint,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  } else {
                                    await StorageService.instance.removeTrackFromPlaylist(pl.id, track.id);
                                    _loadPlaylistsAndFavorites();
                                    nav.pop();
                                  }
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSelectSongsForPlaylistSheet(Playlist pl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Add Songs to "${pl.name}"',
                            style: const TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(icon: const Icon(Icons.close, color: PulseColors.textMuted), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: widget.tracks.isEmpty
                            ? const Center(child: Text('No tracks downloaded yet', style: TextStyle(color: PulseColors.textMuted)))
                            : ListView.separated(
                                itemCount: widget.tracks.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, idx) {
                                  final trk = widget.tracks[idx];
                                  final isAdded = pl.trackIds.contains(trk.id);
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    leading: TrackArtwork(
                                      thumbUrl: trk.thumbnailUrl,
                                      width: 40,
                                      height: 40,
                                      borderRadius: 6,
                                      fallback: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                                    ),
                                    title: Text(trk.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textWhite, fontSize: 13.5)),
                                    subtitle: Text(trk.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                                    trailing: IconButton(
                                      icon: Icon(isAdded ? Icons.check_circle : Icons.add_circle_outline, color: isAdded ? PulseColors.primaryMint : PulseColors.textMuted),
                                      onPressed: () async {
                                        if (isAdded) {
                                          await StorageService.instance.removeTrackFromPlaylist(pl.id, trk.id);
                                          pl.trackIds.remove(trk.id);
                                        } else {
                                          await StorageService.instance.addTrackToPlaylist(pl.id, trk.id);
                                          pl.trackIds.add(trk.id);
                                        }
                                        setSheetState(() {});
                                        _loadPlaylistsAndFavorites();
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showSelectSongsForFavoritesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Add Songs to Favorites',
                            style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          IconButton(icon: const Icon(Icons.close, color: PulseColors.textMuted), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: widget.tracks.isEmpty
                            ? const Center(child: Text('No tracks downloaded yet', style: TextStyle(color: PulseColors.textMuted)))
                            : ListView.separated(
                                itemCount: widget.tracks.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 8),
                                itemBuilder: (context, idx) {
                                  final trk = widget.tracks[idx];
                                  final isFav = _favoriteTracks.any((f) => f.id == trk.id);
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    leading: TrackArtwork(
                                      thumbUrl: trk.thumbnailUrl,
                                      width: 40,
                                      height: 40,
                                      borderRadius: 6,
                                      fallback: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                                    ),
                                    title: Text(trk.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textWhite, fontSize: 13.5)),
                                    subtitle: Text(trk.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                                    trailing: IconButton(
                                      icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? PulseColors.primaryMint : PulseColors.textMuted),
                                      onPressed: () async {
                                        await StorageService.instance.toggleFavorite(trk.id);
                                        await _loadPlaylistsAndFavorites();
                                        setSheetState(() {});
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Track> _applySort(List<Track> tracks) {
    final list = List<Track>.from(tracks);
    switch (_sortOption) {
      case LibrarySortOption.dateNewest:
        break;
      case LibrarySortOption.dateOldest:
        return list.reversed.toList();
      case LibrarySortOption.titleAsc:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case LibrarySortOption.titleDesc:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case LibrarySortOption.yearOrDuration:
        list.sort((a, b) => b.durationSecs.compareTo(a.durationSecs));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedPlaylist != null) {
      return _buildPlaylistDetailView(_selectedPlaylist!);
    }

    final filteredTracks = _applySort(widget.tracks.where((t) {
      final q = _searchFilter.text.toLowerCase();
      return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
    }).toList());

    final userPlaylists = _playlists.where((p) => p.id != 'favorites').toList();

    return Column(
      children: [
        if (_isSelectionMode)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: PulseColors.surfaceContainerHigh,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: PulseColors.textWhite),
                  tooltip: 'Cancel Selection',
                  onPressed: () {
                    setState(() {
                      _isSelectionMode = false;
                      _selectedTrackIds.clear();
                    });
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  '${_selectedTrackIds.length} Selected',
                  style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedTrackIds.length == widget.tracks.length) {
                        _selectedTrackIds.clear();
                      } else {
                        _selectedTrackIds.addAll(widget.tracks.map((t) => t.id));
                      }
                    });
                  },
                  child: Text(
                    _selectedTrackIds.length == widget.tracks.length ? 'Deselect All' : 'Select All',
                    style: const TextStyle(color: PulseColors.primaryMint, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_selectedTrackIds.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
                    tooltip: 'Delete Selected Songs',
                    onPressed: _confirmBatchDelete,
                  ),
              ],
            ),
          )
        else
          // Search & Multi-Select Toolbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: PulseColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x1AFFFFFF)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: _searchFilter,
                      style: const TextStyle(color: PulseColors.textWhite, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Search offline library...',
                        hintStyle: TextStyle(color: PulseColors.textMuted, fontSize: 13),
                        icon: Icon(Icons.search, color: PulseColors.textMuted, size: 18),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                if (widget.tracks.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      _viewMode == LibraryViewMode.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                      color: PulseColors.primaryMint,
                      size: 22,
                    ),
                    tooltip: _viewMode == LibraryViewMode.grid ? 'Switch to List View' : 'Switch to Square Grid',
                    onPressed: () {
                      setState(() {
                        _viewMode = _viewMode == LibraryViewMode.grid ? LibraryViewMode.list : LibraryViewMode.grid;
                      });
                      SharedPreferences.getInstance().then(
                        (p) => p.setString('library_view_mode', _viewMode == LibraryViewMode.grid ? 'grid' : 'list'),
                      );
                    },
                  ),
                  PopupMenuButton<LibrarySortOption>(
                    icon: const Icon(Icons.sort_rounded, color: PulseColors.primaryMint, size: 22),
                    tooltip: 'Sort Tracks',
                    color: PulseColors.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (opt) => setState(() => _sortOption = opt),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: LibrarySortOption.dateNewest,
                        child: Text('Date Downloaded (Newest)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                      ),
                      const PopupMenuItem(
                        value: LibrarySortOption.dateOldest,
                        child: Text('Date Downloaded (Oldest)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                      ),
                      const PopupMenuItem(
                        value: LibrarySortOption.titleAsc,
                        child: Text('Song Title (A–Z)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                      ),
                      const PopupMenuItem(
                        value: LibrarySortOption.titleDesc,
                        child: Text('Song Title (Z–A)', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                      ),
                      const PopupMenuItem(
                        value: LibrarySortOption.yearOrDuration,
                        child: Text('Duration / Length', style: TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.checklist, color: PulseColors.primaryMint),
                    tooltip: 'Select Multiple',
                    onPressed: () {
                      setState(() {
                        _isSelectionMode = true;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

        // Tab Selector: All Songs vs Favorites Module vs Playlists
        Container(
          color: PulseColors.surface,
          child: TabBar(
            controller: _tabController,
            indicatorColor: PulseColors.primaryMint,
            labelColor: PulseColors.primaryMint,
            unselectedLabelColor: PulseColors.textMuted,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            tabs: [
              Tab(text: 'All Tracks (${widget.tracks.length})'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 14),
                    const SizedBox(width: 4),
                    Text('Favorites (${_favoriteTracks.length})'),
                  ],
                ),
              ),
              Tab(text: 'Playlists (${userPlaylists.length})'),
            ],
          ),
        ),

        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: All Songs List
              _buildTracksList(filteredTracks),

              // Tab 2: Dedicated Favorites Module
              _buildFavoritesModule(),

              // Tab 3: Playlists Manager
              _buildPlaylistsGrid(userPlaylists),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTracksList(List<Track> tracks) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: PulseColors.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.music_off, color: PulseColors.textMuted, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Downloaded Tracks Yet',
              style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Search YouTube or grab songs to play offline',
              style: TextStyle(color: PulseColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final player = AudioPlayerService.instance;

    return StreamBuilder<Track?>(
      stream: player.currentTrackStream,
      initialData: player.currentTrack,
      builder: (context, trackSnapshot) {
        final currentTrack = trackSnapshot.data;

        if (_viewMode == LibraryViewMode.grid) {
          return _buildTracksGrid(tracks, currentTrack, player);
        }

        return _buildTracksListView(tracks, currentTrack, player);
      },
    );
  }

  Widget _buildTracksGrid(
    List<Track> tracks,
    Track? currentTrack,
    AudioPlayerService player,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await _loadPlaylistsAndFavorites();
      },
      color: PulseColors.primaryMint,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.74,
        ),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final isCurrent = currentTrack?.id == track.id;
          final isFav = _favoriteTracks.any((f) => f.id == track.id);
          final isSelected = _selectedTrackIds.contains(track.id);

          return Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? PulseColors.primaryMint.withOpacity(0.15)
                  : (isCurrent ? PulseColors.surfaceContainerHigh : PulseColors.cardSurface),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? PulseColors.primaryMint
                    : (isCurrent ? PulseColors.primaryMint.withOpacity(0.8) : PulseColors.cardBorder),
                width: (isSelected || isCurrent) ? 1.5 : 1.0,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (_isSelectionMode) {
                  _toggleSelection(track.id);
                } else {
                  player.playTrack(track, tracks);
                }
              },
              onLongPress: () {
                if (!_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedTrackIds.add(track.id);
                  });
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                          child: TrackArtwork(
                            thumbUrl: track.thumbnailUrl,
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: 0,
                            fallback: Container(
                              color: PulseColors.surfaceContainerLowest,
                              child: const Icon(Icons.music_note, color: PulseColors.primaryMint, size: 36),
                            ),
                          ),
                        ),
                        if (isCurrent)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                            ),
                            child: const Center(
                              child: Icon(Icons.equalizer, color: PulseColors.primaryMint, size: 32),
                            ),
                          ),
                        if (_isSelectionMode)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Checkbox(
                              value: isSelected,
                              activeColor: PulseColors.primaryMint,
                              onChanged: (_) => _toggleSelection(track.id),
                            ),
                          ),
                        Positioned(
                          bottom: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: PulseColors.background.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              track.durationFormatted,
                              style: const TextStyle(color: PulseColors.primaryMint, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isSelected
                                      ? PulseColors.primaryMintBright
                                      : (isCurrent ? PulseColors.primaryMint : PulseColors.textWhite),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PulseColors.textMuted, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        if (!_isSelectionMode)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: PulseColors.textMuted, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32),
                            color: PulseColors.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            onSelected: (val) async {
                              if (val == 'fav') {
                                await StorageService.instance.toggleFavorite(track.id);
                                _loadPlaylistsAndFavorites();
                              } else if (val == 'delete') {
                                _confirmDeleteTrack(track);
                              } else if (val == 'more') {
                                _showTrackOptionsMenu(track);
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'fav',
                                child: Row(
                                  children: [
                                    Icon(
                                      isFav ? Icons.favorite : Icons.favorite_border,
                                      color: isFav ? PulseColors.primaryMint : PulseColors.textMuted,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      isFav ? 'Remove Favorite' : 'Save Favorite',
                                      style: const TextStyle(color: PulseColors.textWhite, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    SizedBox(width: 8),
                                    Text('Delete Song', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'more',
                                child: Row(
                                  children: [
                                    Icon(Icons.playlist_add, color: PulseColors.primaryMint, size: 18),
                                    SizedBox(width: 8),
                                    Text('Add to Playlist...', style: TextStyle(color: PulseColors.textWhite, fontSize: 12)),
                                  ],
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
          );
        },
      ),
    );
  }

  Widget _buildTracksListView(
    List<Track> tracks,
    Track? currentTrack,
    AudioPlayerService player,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        widget.onRefresh();
        await _loadPlaylistsAndFavorites();
      },
      color: PulseColors.primaryMint,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: tracks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final isCurrent = currentTrack?.id == track.id;
          final isFav = _favoriteTracks.any((f) => f.id == track.id);
          final isSelected = _selectedTrackIds.contains(track.id);

          return Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? PulseColors.primaryMint.withOpacity(0.15)
                  : (isCurrent ? PulseColors.surfaceContainerHigh : PulseColors.surfaceContainer),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? PulseColors.primaryMint
                    : (isCurrent ? PulseColors.primaryMint.withOpacity(0.6) : const Color(0x1AFFFFFF)),
                width: (isSelected || isCurrent) ? 1.5 : 1.0,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              onTap: () {
                if (_isSelectionMode) {
                  _toggleSelection(track.id);
                } else {
                  player.playTrack(track, tracks);
                }
              },
              onLongPress: () {
                if (!_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedTrackIds.add(track.id);
                  });
                }
              },
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSelectionMode)
                    Checkbox(
                      value: isSelected,
                      activeColor: PulseColors.primaryMint,
                      onChanged: (_) => _toggleSelection(track.id),
                    ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      TrackArtwork(
                        thumbUrl: track.thumbnailUrl,
                        width: 48,
                        height: 48,
                        borderRadius: 8,
                        fallback: Container(
                          color: PulseColors.surfaceContainerLowest,
                          child: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.equalizer, color: PulseColors.primaryMint, size: 24),
                        ),
                    ],
                  ),
                ],
              ),
              title: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? PulseColors.primaryMintBright : (isCurrent ? PulseColors.primaryMint : PulseColors.textWhite),
                  fontWeight: (isSelected || isCurrent) ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              subtitle: Text(
                '${track.artist} • ${track.durationFormatted}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
              ),
              trailing: _isSelectionMode
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            color: isFav ? PulseColors.primaryMint : PulseColors.textMuted,
                            size: 20,
                          ),
                          tooltip: isFav ? 'Remove Favorite' : 'Save Favorite',
                          onPressed: () async {
                            await StorageService.instance.toggleFavorite(track.id);
                            _loadPlaylistsAndFavorites();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          tooltip: 'Delete Song',
                          onPressed: () => _confirmDeleteTrack(track),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert, color: PulseColors.textMuted, size: 20),
                          onPressed: () => _showTrackOptionsMenu(track),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }

  // Dedicated Favorites Module View
  Widget _buildFavoritesModule() {
    if (_favoriteTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: PulseColors.primaryMint.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_border, color: PulseColors.primaryMint, size: 36),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Favorite Tracks Yet',
              style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tap the heart icon on any song or add songs below',
              style: TextStyle(color: PulseColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showSelectSongsForFavoritesSheet,
              icon: const Icon(Icons.add, size: 16, color: PulseColors.onPrimary),
              label: const Text('Add Songs to Favorites', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: PulseColors.primaryMint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }

    final player = AudioPlayerService.instance;

    return Column(
      children: [
        // Hero Favorites Header Card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                PulseColors.surfaceContainerHigh,
                PulseColors.surfaceContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PulseColors.primaryMint.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: PulseColors.primaryMint,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: PulseColors.primaryMint.withOpacity(0.35),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: const Icon(Icons.favorite, color: PulseColors.onPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Favorites Collection',
                      style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_favoriteTracks.length} Saved Tracks',
                      style: const TextStyle(color: PulseColors.primaryMint, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: PulseColors.primaryMint, size: 28),
                tooltip: 'Add songs',
                onPressed: _showSelectSongsForFavoritesSheet,
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                onPressed: () {
                  if (_favoriteTracks.isNotEmpty) {
                    player.playTrack(_favoriteTracks.first, _favoriteTracks);
                  }
                },
                icon: const Icon(Icons.play_arrow, color: PulseColors.onPrimary, size: 18),
                label: const Text('Play All', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PulseColors.primaryMint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // List of Favorites
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: _favoriteTracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = _favoriteTracks[index];

              return Container(
                decoration: BoxDecoration(
                  color: PulseColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x1AFFFFFF)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  onTap: () {
                    player.playTrack(track, _favoriteTracks);
                  },
                  leading: TrackArtwork(
                    thumbUrl: track.thumbnailUrl,
                    width: 48,
                    height: 48,
                    borderRadius: 8,
                    fallback: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                  ),
                  title: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '${track.artist} • ${track.durationFormatted}',
                    style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.favorite, color: PulseColors.primaryMint, size: 20),
                    tooltip: 'Remove from Favorites',
                    onPressed: () async {
                      await StorageService.instance.toggleFavorite(track.id);
                      _loadPlaylistsAndFavorites();
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistsGrid(List<Playlist> userPlaylists) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'YOUR PLAYLISTS',
                style: TextStyle(
                  color: PulseColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreatePlaylistDialog,
                icon: const Icon(Icons.add, size: 16, color: PulseColors.onPrimary),
                label: const Text('New Playlist', style: TextStyle(color: PulseColors.onPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PulseColors.primaryMint,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: userPlaylists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music, color: PulseColors.textMuted, size: 48),
                      const SizedBox(height: 12),
                      const Text('No Custom Playlists Yet', style: TextStyle(color: PulseColors.textWhite, fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Create playlists to organize your downloaded songs', style: TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _showCreatePlaylistDialog,
                        style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
                        child: const Text('Create First Playlist', style: TextStyle(color: PulseColors.onPrimary)),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: userPlaylists.length,
                  itemBuilder: (context, index) {
                    final pl = userPlaylists[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: PulseColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0x1AFFFFFF)),
                      ),
                      child: ListTile(
                        onTap: () {
                          setState(() {
                            _selectedPlaylist = pl;
                          });
                        },
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: PulseColors.primaryMint.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.playlist_play, color: PulseColors.primaryMint),
                        ),
                        title: Text(
                          pl.name,
                          style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${pl.trackIds.length} Songs',
                          style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            await StorageService.instance.deletePlaylist(pl.id);
                            _loadPlaylistsAndFavorites();
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPlaylistDetailView(Playlist pl) {
    final playlistTracks = widget.tracks.where((t) => pl.trackIds.contains(t.id)).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: PulseColors.surface,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: PulseColors.textWhite),
                onPressed: () => setState(() => _selectedPlaylist = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pl.name,
                      style: const TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${playlistTracks.length} Songs',
                      style: const TextStyle(color: PulseColors.primaryMint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showSelectSongsForPlaylistSheet(pl),
                icon: const Icon(Icons.add, size: 16, color: PulseColors.onPrimary),
                label: const Text('Add Songs', style: TextStyle(color: PulseColors.onPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PulseColors.primaryMint,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              if (playlistTracks.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: PulseColors.primaryMint, size: 36),
                  onPressed: () {
                    AudioPlayerService.instance.playTrack(playlistTracks.first, playlistTracks);
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: playlistTracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.queue_music, color: PulseColors.textMuted, size: 48),
                      const SizedBox(height: 12),
                      const Text('Playlist is empty', style: TextStyle(color: PulseColors.textWhite, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Add downloaded songs from your library to this playlist', style: TextStyle(color: PulseColors.textMuted, fontSize: 12)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showSelectSongsForPlaylistSheet(pl),
                        icon: const Icon(Icons.add, size: 16, color: PulseColors.onPrimary),
                        label: const Text('Add Songs Now', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: playlistTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final track = playlistTracks[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: PulseColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: TrackArtwork(
                          thumbUrl: track.thumbnailUrl,
                          width: 40,
                          height: 40,
                          borderRadius: 6,
                          fallback: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                        ),
                        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textWhite, fontSize: 13)),
                        subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: PulseColors.textMuted, size: 18),
                          onPressed: () async {
                            await StorageService.instance.removeTrackFromPlaylist(pl.id, track.id);
                            final updated = await StorageService.instance.loadPlaylists();
                            setState(() {
                              _playlists = updated;
                              _selectedPlaylist = updated.firstWhere((p) => p.id == pl.id);
                            });
                          },
                        ),
                        onTap: () {
                          AudioPlayerService.instance.playTrack(track, playlistTracks);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showTrackOptionsMenu(Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.favorite_border, color: PulseColors.primaryMint),
                title: const Text('Toggle Favorite', style: TextStyle(color: PulseColors.textWhite)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await StorageService.instance.toggleFavorite(track.id);
                  _loadPlaylistsAndFavorites();
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note, color: PulseColors.primaryMint),
                title: const Text('Rename Song', style: TextStyle(color: PulseColors.textWhite)),
                subtitle: const Text('Edit title & artist name', style: TextStyle(color: PulseColors.textMuted, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRenameDialog(track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: PulseColors.primaryMint),
                title: const Text('Add to Playlist', style: TextStyle(color: PulseColors.textWhite)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToPlaylistSheet(track);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Track', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteTrack(track);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSelection(String trackId) {
    setState(() {
      if (_selectedTrackIds.contains(trackId)) {
        _selectedTrackIds.remove(trackId);
        if (_selectedTrackIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedTrackIds.add(trackId);
      }
    });
  }

  Future<void> _confirmDeleteTrack(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Delete Song?', style: TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${track.title}" from your library and storage?',
          style: const TextStyle(color: PulseColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final tId = track.id;
      final tTitle = track.title;
      if (AudioPlayerService.instance.currentTrack?.id == tId) {
        await AudioPlayerService.instance.stop();
      }
      widget.onDelete(tId);
      await _loadPlaylistsAndFavorites();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "$tTitle"'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmBatchDelete() async {
    final count = _selectedTrackIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PulseColors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
            const SizedBox(width: 8),
            Text('Delete $count Song${count > 1 ? 's' : ''}?', style: const TextStyle(color: PulseColors.textWhite, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $count selected songs from your device and library? This cannot be undone.',
          style: const TextStyle(color: PulseColors.textMuted, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final idsToDelete = _selectedTrackIds.toList();
      final currentPlayingId = AudioPlayerService.instance.currentTrack?.id;
      if (currentPlayingId != null && idsToDelete.contains(currentPlayingId)) {
        await AudioPlayerService.instance.stop();
      }
      setState(() {
        _selectedTrackIds.clear();
        _isSelectionMode = false;
      });
      if (widget.onBatchDelete != null) {
        widget.onBatchDelete!(idsToDelete);
      } else {
        for (final id in idsToDelete) {
          widget.onDelete(id);
        }
      }
      await _loadPlaylistsAndFavorites();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $count song${count > 1 ? 's' : ''}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showRenameDialog(Track track) {
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
                Navigator.pop(ctx);
                await StorageService.instance.renameTrack(
                  track.id,
                  newTitle,
                  newArtist: newArtist.isNotEmpty ? newArtist : null,
                );
                widget.onRefresh();
                await _loadPlaylistsAndFavorites();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Renamed to "$newTitle"'),
                      backgroundColor: PulseColors.primaryMint,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
            child: const Text('Save', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
