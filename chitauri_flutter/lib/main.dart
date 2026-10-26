import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'models/track.dart';
import 'services/storage_service.dart';
import 'services/youtube_service.dart';
import 'theme/pulse_theme.dart';
import 'views/library_view.dart';
import 'views/profile_view.dart';
import 'views/queue_view.dart';
import 'views/youtube_webview.dart';
import 'widgets/mini_player.dart';
import 'widgets/vinyl_player_sheet.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: PulseColors.surfaceContainerLowest,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize storage directory and .nomedia sentinel
  final storage = StorageService.instance;
  await storage.ensureNomedia();

  runApp(const ChitauriApp());
}

class ChitauriApp extends StatelessWidget {
  const ChitauriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chitauri',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PulseColors.background,
        primaryColor: PulseColors.primaryMint,
        colorScheme: const ColorScheme.dark(
          primary: PulseColors.primaryMint,
          secondary: PulseColors.primaryMintBright,
          surface: PulseColors.surfaceContainer,
        ),
        fontFamily: 'Roboto',
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTabIndex = 0;
  List<Track> _tracks = [];
  final List<DownloadTask> _downloadTasks = [];
  bool _isPlayerExpanded = false;
  WebViewController? _webViewController;
  DateTime? _lastBackPressTime;
  bool _isDownloading = false;
  int _lastProgressUpdateMs = 0;

  @override
  void initState() {
    super.initState();
    _loadTracks();
    // Run legacy upgrades once in background after app launch
    Future.microtask(() async {
      await YouTubeService.instance.upgradeLegacyTrackNames();
      if (mounted) _loadTracks();
    });
  }

  Future<void> _loadTracks() async {
    final t = await StorageService.instance.loadTracks();
    if (mounted) {
      setState(() {
        _tracks = t;
      });
    }
  }

  void _deleteTrack(String trackId) async {
    setState(() {
      _tracks.removeWhere((t) => t.id == trackId);
    });
    await StorageService.instance.deleteTrack(trackId);
    final fresh = await StorageService.instance.loadTracks();
    if (mounted) {
      setState(() {
        _tracks = fresh;
      });
    }
  }

  void _deleteTracks(List<String> trackIds) async {
    final idSet = trackIds.toSet();
    setState(() {
      _tracks.removeWhere((t) => idSet.contains(t.id));
    });
    await StorageService.instance.deleteTracks(trackIds);
    final fresh = await StorageService.instance.loadTracks();
    if (mounted) {
      setState(() {
        _tracks = fresh;
      });
    }
  }

  void _startDownload(DownloadTask task) {
    // If this video is already actively downloading or in queue, do not duplicate
    final isAlreadyActive = _downloadTasks.any(
      (d) => d.videoId == task.videoId && (d.status == DownloadStatus.downloading || d.status == DownloadStatus.queued),
    );
    if (isAlreadyActive) return;

    final hasActiveOrQueued = _downloadTasks.any(
      (d) => d.status == DownloadStatus.downloading || d.status == DownloadStatus.queued,
    );

    setState(() {
      _downloadTasks.removeWhere((d) => d.videoId == task.videoId);
      if (!_isDownloading && !hasActiveOrQueued) {
        // Immediate execution for single download!
        task.status = DownloadStatus.downloading;
        task.statusText = '0%';
      } else {
        // Multiple downloads or playlist: queue behind active download in FIFO order
        task.status = DownloadStatus.queued;
        task.statusText = 'In Queue';
      }
      _downloadTasks.add(task);
    });
    _processDownloadQueue();
  }

  void _processDownloadQueue() async {
    if (_isDownloading) return;

    // Find the next task: first check if a task is already marked downloading,
    // otherwise pick the earliest queued task in FIFO order
    DownloadTask? nextTask;
    for (final t in _downloadTasks) {
      if (t.status == DownloadStatus.downloading) {
        nextTask = t;
        break;
      }
    }
    if (nextTask == null) {
      for (final t in _downloadTasks) {
        if (t.status == DownloadStatus.queued) {
          nextTask = t;
          break;
        }
      }
    }

    if (nextTask == null) return;

    _isDownloading = true;
    setState(() {
      nextTask!.status = DownloadStatus.downloading;
      if (nextTask.progress == 0.0) {
        nextTask.statusText = '0%';
      }
    });

    try {
      final downloadedTrack = await YouTubeService.instance.downloadAudio(
        nextTask.videoId,
        pid: nextTask.pid,
        processId: nextTask.processIdentifier,
        title: nextTask.title,
        channel: nextTask.channel,
        onMetadataResolved: (resolvedTitle, resolvedArtist) {
          if (nextTask!.status != DownloadStatus.cancelled) {
            nextTask.title = resolvedTitle;
            nextTask.channel = resolvedArtist;
            if (mounted) setState(() {});
          }
        },
        onProgress: (p, statusText) {
          if (nextTask!.status == DownloadStatus.cancelled) return;
          nextTask.progress = p;
          nextTask.statusText = statusText;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (mounted && (now - _lastProgressUpdateMs > 120 || p >= 1.0)) {
            _lastProgressUpdateMs = now;
            setState(() {});
          }
        },
      ).timeout(
        const Duration(minutes: 4),
        onTimeout: () => throw TimeoutException('Download exceeded maximum safety timeout (4 minutes)'),
      );

      if (nextTask.status != DownloadStatus.cancelled) {
        nextTask.title = downloadedTrack.title;
        nextTask.channel = downloadedTrack.artist;
        nextTask.status = DownloadStatus.completed;
        nextTask.statusText = '100%';
        nextTask.progress = 1.0;
        if (mounted) setState(() {});
        await _loadTracks();
      }
    } catch (err) {
      if (nextTask.status != DownloadStatus.cancelled) {
        nextTask.status = DownloadStatus.failed;
        nextTask.statusText = 'Failed';
        nextTask.errorMessage = err.toString();
        if (mounted) setState(() {});
      }
    } finally {
      _isDownloading = false;
      _processDownloadQueue(); // Process next queued song in FIFO order
    }
  }

  void _killProcess(int pid) async {
    final idx = _downloadTasks.indexWhere((t) => t.pid == pid);
    if (idx == -1) return;
    final task = _downloadTasks[idx];

    if (task.status == DownloadStatus.downloading) {
      await YouTubeService.instance.killProcess(task.processIdentifier);
      if (mounted) {
        setState(() {
          task.status = DownloadStatus.cancelled;
          task.statusText = 'Cancelled';
        });
      }
      _isDownloading = false;
      _processDownloadQueue();
    } else if (task.status == DownloadStatus.queued) {
      if (mounted) {
        setState(() {
          task.status = DownloadStatus.cancelled;
          task.statusText = 'Cancelled';
        });
      }
    }
  }

  void _openFullPlayer() {
    setState(() {
      _isPlayerExpanded = true;
    });
  }

  void _closeFullPlayer() {
    setState(() {
      _isPlayerExpanded = false;
    });
  }

  void _handleBackPress() async {
    if (_isPlayerExpanded) {
      _closeFullPlayer();
      return;
    }

    if (_currentTabIndex == 0 && _webViewController != null) {
      final canGoBack = await _webViewController!.canGoBack();
      if (canGoBack) {
        await _webViewController!.goBack();
        return;
      }
    }

    if (_currentTabIndex != 0) {
      setState(() {
        _currentTabIndex = 0;
      });
      return;
    }

    final now = DateTime.now();
    if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit Chitauri'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackPress();
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    if (_isPlayerExpanded) {
      return Scaffold(
        body: VinylPlayerSheet(onMinimize: _closeFullPlayer),
      );
    }

    final pages = [
      // Tab 0: Integrated YouTube Web & Audio Grab
      YouTubeWebViewPage(
        onStartDownload: _startDownload,
        onControllerReady: (c) => _webViewController = c,
      ),
      // Tab 1: Offline Library & Playlists
      LibraryView(
        tracks: _tracks,
        onRefresh: _loadTracks,
        onDelete: _deleteTrack,
        onBatchDelete: _deleteTracks,
      ),
      // Tab 2: Download Queue
      QueueView(
        tasks: _downloadTasks,
        onClearCompleted: () {
          setState(() {
            _downloadTasks.removeWhere((t) => t.status == DownloadStatus.completed);
          });
        },
        onKillProcess: _killProcess,
      ),
      // Tab 3: User Profile & Preferences
      ProfileView(tracks: _tracks),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Constant Global Header: Always Strictly "Chitauri" with Official Brand Logo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: PulseColors.surface,
                border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: PulseColors.primaryMint.withOpacity(0.35),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset('assets/logo.png', width: 34, height: 34, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Chitauri',
                    style: TextStyle(
                      color: PulseColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentTabIndex = 3; // Switch to Profile tab
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _currentTabIndex == 3 ? PulseColors.primaryMint : PulseColors.surfaceContainerHigh,
                        shape: BoxShape.circle,
                        border: Border.all(color: PulseColors.primaryMint.withOpacity(0.4)),
                      ),
                      child: Icon(
                        Icons.person,
                        color: _currentTabIndex == 3 ? PulseColors.onPrimary : PulseColors.primaryMint,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Current Active Screen
            Expanded(
              child: IndexedStack(
                index: _currentTabIndex,
                children: pages,
              ),
            ),

            // Docked Mini Player
            MiniPlayerWidget(onExpand: _openFullPlayer),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PulseColors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTabIndex,
          onTap: (idx) {
            setState(() {
              _currentTabIndex = idx;
            });
            if (idx == 1) {
              _loadTracks();
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: PulseColors.primaryMint,
          unselectedItemColor: PulseColors.textMuted,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.public),
              activeIcon: Icon(Icons.public, color: PulseColors.primaryMint),
              label: 'Grab',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.library_music),
              activeIcon: Icon(Icons.library_music, color: PulseColors.primaryMint),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: _downloadTasks.any((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued),
                backgroundColor: PulseColors.primaryMint,
                child: const Icon(Icons.download),
              ),
              activeIcon: const Icon(Icons.download, color: PulseColors.primaryMint),
              label: 'Queue',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person, color: PulseColors.primaryMint),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
