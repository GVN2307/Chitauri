import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/youtube_service.dart';
import '../theme/pulse_theme.dart';

class YouTubeWebViewPage extends StatefulWidget {
  final Function(DownloadTask task) onStartDownload;
  final void Function(WebViewController controller)? onControllerReady;

  const YouTubeWebViewPage({
    super.key,
    required this.onStartDownload,
    this.onControllerReady,
  });

  @override
  State<YouTubeWebViewPage> createState() => YouTubeWebViewPageState();
}

class YouTubeWebViewPageState extends State<YouTubeWebViewPage> {
  late final WebViewController controller;
  final TextEditingController _searchController = TextEditingController();
  String? _detectedVideoId;
  String? _detectedTitle;
  bool _isLoading = true;
  double _loadProgress = 0.0;
  bool _showQuickCards = false;
  List<YouTubeVideoItem> _quickSearchResults = [];

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(PulseColors.background)
      ..addJavaScriptChannel(
        'VideoGrabber',
        onMessageReceived: (JavaScriptMessage message) {
          final raw = message.message.trim();
          if (raw.startsWith('{')) {
            try {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              if (map['type'] == 'playlist') {
                final pId = map['playlistId'] as String?;
                final pUrl = map['url'] as String?;
                final title = map['title'] as String?;
                if (pId != null && pId.isNotEmpty) {
                  _triggerPlaylistDownload(pId, playlistUrl: pUrl, defaultTitle: title);
                  return;
                }
              }
              final videoId = map['id'] as String? ?? '';
              final extractedTitle = map['title'] as String?;
              final channel = map['channel'] as String?;
              final playlistId = map['playlistId'] as String?;
              if (playlistId != null && playlistId.isNotEmpty && !playlistId.startsWith('RD')) {
                _promptPlaylistOrSongDownload(videoId, playlistId, 'https://www.youtube.com/watch?v=$videoId&list=$playlistId');
                return;
              }
              if (videoId.isNotEmpty) {
                _triggerDirectMp3Download(videoId, defaultTitle: extractedTitle, defaultChannel: channel);
                return;
              }
            } catch (_) {}
          }
          if (raw.isNotEmpty) {
            _triggerDirectMp3Download(raw);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadProgress = progress / 100.0;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final playlistId = YouTubeService.instance.extractPlaylistId(request.url);
            if (playlistId != null && request.url.contains('playlist?list=')) {
              _triggerPlaylistDownload(playlistId, playlistUrl: request.url);
              return NavigationDecision.prevent;
            }
            final videoId = YouTubeService.instance.extractVideoId(request.url);
            if (videoId != null && !request.url.contains('results?search_query')) {
              if (playlistId != null && !playlistId.startsWith('RD')) {
                _promptPlaylistOrSongDownload(videoId, playlistId, request.url);
              } else {
                _triggerDirectMp3Download(videoId);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
            _checkUrlForVideo(url);
          },
          onPageFinished: (String url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _checkUrlForVideo(url);

            // Intercept clicks to block video stream and trigger audio grab with DOM metadata
            controller.runJavaScript('''
              document.addEventListener('click', function(e) {
                var el = e.target;
                var a = el.closest('a');
                var card = el.closest('ytm-compact-video-renderer, ytm-video-with-context-renderer, ytm-media-item, ytm-rich-item-renderer, ytd-video-renderer, ytd-compact-video-renderer, .media-item-info, div[class*="media-item"]') || (a ? a.closest('div') : null);

                var href = (a && a.href) ? a.href : '';
                if (!href && card) {
                  var link = card.querySelector('a[href*="watch?v="], a[href*="youtu.be/"], a[href*="list="]');
                  if (link) href = link.href;
                }

                if (href) {
                  var playlistMatch = href.match(/[?&]list=([a-zA-Z0-9_-]+)/);
                  var match = href.match(/(?:watch\\?v=|youtu\\.be\\/)([a-zA-Z0-9_-]{11})/);

                  // Extract true title: search card first, then link, then aria
                  var title = '';
                  if (card) {
                    var titleElem = card.querySelector('h3, h4, .compact-media-item-headline, .media-item-headline, [class*="headline"], [class*="title"], #video-title');
                    if (titleElem) title = (titleElem.innerText || titleElem.textContent || '').trim();
                  }
                  if (!title && a) {
                    var titleElem2 = a.querySelector('h3, h4, .compact-media-item-headline, .media-item-headline, [class*="headline"], [class*="title"], #video-title');
                    if (titleElem2) title = (titleElem2.innerText || titleElem2.textContent || '').trim();
                  }
                  if (!title && a) {
                    var aria = a.getAttribute('aria-label') || '';
                    if (aria && !aria.toLowerCase().includes('thumbnail') && !aria.toLowerCase().includes('avatar')) {
                      title = aria.trim();
                    }
                  }

                  // Extract channel / artist
                  var channel = '';
                  if (card) {
                    var chElem = card.querySelector('.compact-media-item-byline, .media-item-byline, [class*="byline"], [class*="channel"], ytm-badge-and-byline-renderer');
                    if (chElem) channel = (chElem.innerText || chElem.textContent || '').trim();
                  }

                  if (playlistMatch && (!match || href.indexOf('playlist') !== -1)) {
                    e.preventDefault();
                    e.stopPropagation();
                    if (window.VideoGrabber) {
                      window.VideoGrabber.postMessage(JSON.stringify({
                        type: 'playlist',
                        playlistId: playlistMatch[1],
                        url: href,
                        title: title,
                        channel: channel
                      }));
                    }
                    return;
                  }

                  if (match) {
                    e.preventDefault();
                    e.stopPropagation();
                    document.querySelectorAll('video').forEach(function(v) {
                      try { v.pause(); } catch(_) {}
                    });
                    if (window.VideoGrabber) {
                      window.VideoGrabber.postMessage(JSON.stringify({
                        id: match[1],
                        playlistId: playlistMatch ? playlistMatch[1] : null,
                        title: title,
                        channel: channel
                      }));
                    }
                  }
                }
              }, true);
            ''');

            try {
              final title = await controller.getTitle();
              if (title != null && title.isNotEmpty && !title.contains('YouTube')) {
                if (mounted) {
                  setState(() {
                    _detectedTitle = title.replaceAll('- YouTube', '').trim();
                  });
                }
              }
            } catch (_) {}
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) {
              _checkUrlForVideo(change.url!);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://m.youtube.com'));

    widget.onControllerReady?.call(controller);
  }

  Future<void> _performQuickSearch(String query) async {
    final results = await YouTubeService.instance.search(query);
    if (mounted) {
      setState(() {
        _quickSearchResults = results;
      });
    }
  }

  String? _lastTriggeredVideoId;
  int _lastTriggerTime = 0;

  void _triggerDirectMp3Download(String videoId, {String? defaultTitle, String? defaultChannel}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (videoId == _lastTriggeredVideoId && (now - _lastTriggerTime < 1200)) {
      return; // Deduplicate rapid multiple triggers for the same video within 1.2s
    }
    _lastTriggeredVideoId = videoId;
    _lastTriggerTime = now;

    String title = (defaultTitle != null && defaultTitle.isNotEmpty && !defaultTitle.startsWith('YouTube Audio'))
        ? defaultTitle
        : (_detectedTitle ?? '');
    title = title.replaceAll(RegExp(r'\s*-\s*YouTube$', caseSensitive: false), '').trim();
    String channel = defaultChannel ?? '';

    if (title.isEmpty) {
      title = 'Fetching title...';
    }
    if (channel.isEmpty) {
      channel = 'Music Artist';
    }

    // Check if song already exists in user's library using fast in-memory cache
    final existingTracks = StorageService.instance.getCachedTracks();
    final cleanTitleLower = title.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim().toLowerCase();
    final isGenericTitle = cleanTitleLower == 'fetching title...' ||
        cleanTitleLower == 'audio track' ||
        cleanTitleLower == 'song' ||
        cleanTitleLower.startsWith('track ');
    final matching = existingTracks.where((t) {
      final tTitleLower = t.title.replaceAll(RegExp(r'\s*\(\d+\)$'), '').trim().toLowerCase();
      return t.id == videoId || (!isGenericTitle && cleanTitleLower.length > 3 && tTitleLower == cleanTitleLower);
    }).toList();

    if (matching.isNotEmpty && mounted) {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: PulseColors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: PulseColors.primaryMint),
              SizedBox(width: 8),
              Text('Song Already Downloaded', style: TextStyle(color: PulseColors.textWhite, fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            '"$title" is already in your library.\n\nWould you like to download it again as an additional copy?',
            style: const TextStyle(color: PulseColors.textMuted, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Cancel', style: TextStyle(color: PulseColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'download_again'),
              style: ElevatedButton.styleFrom(backgroundColor: PulseColors.primaryMint),
              child: const Text('Download Again', style: TextStyle(color: PulseColors.background, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (choice != 'download_again') {
        return; // User cancelled duplicate download
      }

      // Append (2), (3), etc. to title and create unique ID
      final copyNumber = matching.length + 1;
      title = '$title ($copyNumber)';
      videoId = '${videoId}_$copyNumber';
    }

    final task = DownloadTask(
      videoId: videoId,
      title: title,
      channel: channel,
      status: DownloadStatus.queued,
      statusText: 'Starting...',
      progress: 0.05,
    );

    widget.onStartDownload(task);

    if (mounted) {
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
                  'Grabbing Audio: $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: PulseColors.primaryMint,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _triggerPlaylistDownload(String playlistId, {String? playlistUrl, String? defaultTitle}) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: PulseColors.background),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fetching all playlist tracks...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, color: PulseColors.background),
                ),
              ),
            ],
          ),
          backgroundColor: PulseColors.primaryMint,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final cleanListId = YouTubeService.instance.extractPlaylistId(playlistId) ?? playlistId;
    final canonicalUrl = 'https://www.youtube.com/playlist?list=$cleanListId';
    var tracks = await YouTubeService.instance.getPlaylistTracks(canonicalUrl);

    // If native yt-dlp returned empty, scrape visible playlist tracks directly from current WebView DOM
    if (tracks.isEmpty) {
      try {
        final rawJsResult = await controller.runJavaScriptReturningResult('''
          (function() {
            var links = Array.from(document.querySelectorAll('a[href*="watch?v="]'));
            var results = [];
            var seen = {};
            for (var i = 0; i < links.length; i++) {
              var a = links[i];
              var m = a.href.match(/watch\\?v=([a-zA-Z0-9_-]{11})/);
              if (m && !seen[m[1]]) {
                seen[m[1]] = true;
                var titleElem = a.querySelector('h3, h4, .compact-media-item-headline, .media-item-headline');
                var t = titleElem ? titleElem.innerText.trim() : (a.getAttribute('aria-label') || '');
                results.push({ id: m[1], title: t });
              }
            }
            return JSON.stringify(results);
          })()
        ''');
        if (rawJsResult is String && rawJsResult.isNotEmpty && rawJsResult != 'null') {
          final decoded = jsonDecode(rawJsResult.startsWith('"') ? jsonDecode(rawJsResult) : rawJsResult) as List;
          final domItems = <YouTubeVideoItem>[];
          for (final item in decoded) {
            if (item is Map) {
              final id = item['id'] as String? ?? '';
              final t = item['title'] as String? ?? 'Audio Track';
              if (id.isNotEmpty) {
                domItems.add(YouTubeVideoItem(
                  id: id,
                  title: t,
                  channel: 'Playlist Artist',
                  duration: '03:45',
                  views: 'Playlist',
                  thumbnailUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
                  url: 'https://www.youtube.com/watch?v=$id',
                ));
              }
            }
          }
          if (domItems.isNotEmpty) {
            tracks = domItems;
          }
        }
      } catch (_) {}
    }

    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No videos found in this playlist or playlist is private.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: PulseColors.primaryMint.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.playlist_play_rounded, color: PulseColors.primaryMint, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          defaultTitle ?? 'Playlist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          '${tracks.length} tracks detected',
                          style: const TextStyle(fontSize: 13, color: PulseColors.textZinc),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Would you like to queue all songs from this playlist for background download?',
                style: TextStyle(fontSize: 14, color: PulseColors.textMuted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: PulseColors.outline),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.download_rounded, color: PulseColors.background),
                      label: Text(
                        'Download All (${tracks.length})',
                        style: const TextStyle(color: PulseColors.background, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PulseColors.primaryMint,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      for (final track in tracks) {
        final task = DownloadTask(
          videoId: track.id,
          title: track.title,
          channel: track.channel,
          status: DownloadStatus.queued,
          statusText: 'In Queue',
          progress: 0.0,
        );
        widget.onStartDownload(task);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Queued ${tracks.length} songs from playlist for download!'),
            backgroundColor: PulseColors.primaryMint,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _promptPlaylistOrSongDownload(String videoId, String playlistId, String url) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: PulseColors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Download Selection',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'This video belongs to a playlist. What would you like to download?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PulseColors.textMuted),
              ),
              const SizedBox(height: 18),
              ListTile(
                tileColor: PulseColors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.music_note_rounded, color: PulseColors.primaryMint),
                title: const Text('Download Single Track', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Add only this song to queue', style: TextStyle(fontSize: 12, color: PulseColors.textZinc)),
                onTap: () => Navigator.pop(ctx, 'single'),
              ),
              const SizedBox(height: 10),
              ListTile(
                tileColor: PulseColors.surfaceContainerLowest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.playlist_play_rounded, color: PulseColors.primaryMintBright),
                title: const Text('Download Entire Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Queue all songs in this playlist', style: TextStyle(fontSize: 12, color: PulseColors.textZinc)),
                onTap: () => Navigator.pop(ctx, 'playlist'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'playlist') {
      _triggerPlaylistDownload(playlistId, playlistUrl: url);
    } else if (choice == 'single') {
      _triggerDirectMp3Download(videoId);
    }
  }

  void _checkUrlForVideo(String url) {
    final videoId = YouTubeService.instance.extractVideoId(url);
    if (mounted) {
      if (videoId != null && !url.contains('results?search_query')) {
        setState(() {
          _detectedVideoId = videoId;
        });
        YouTubeService.instance.fetchVideoMetadata(videoId).then((meta) {
          if (mounted && _detectedVideoId == videoId) {
            setState(() {
              _detectedTitle = meta['title'];
            });
          }
        });
      } else {
        setState(() {
          _detectedVideoId = null;
          _detectedTitle = null;
        });
      }
    }
  }

  void _searchOrNavigate(String query) {
    query = query.trim();
    if (query.isEmpty) return;

    final videoId = YouTubeService.instance.extractVideoId(query);
    if (videoId != null) {
      controller.loadRequest(Uri.parse('https://m.youtube.com/watch?v=$videoId'));
    } else if (query.startsWith('http://') || query.startsWith('https://')) {
      controller.loadRequest(Uri.parse(query));
    } else {
      final encoded = Uri.encodeComponent(query);
      controller.loadRequest(Uri.parse('https://m.youtube.com/results?search_query=$encoded'));
    }
    _performQuickSearch(query);
    setState(() {
      _showQuickCards = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Integrated Search & URL Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: PulseColors.surface,
            border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: PulseColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(9999),
                    border: Border.all(color: const Color(0x26FFFFFF), width: 1),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: PulseColors.textWhite, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search YouTube or paste URL...',
                      hintStyle: const TextStyle(color: PulseColors.textMuted, fontSize: 12.5),
                      prefixIcon: const Icon(Icons.search, color: PulseColors.primaryMint, size: 18),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, color: PulseColors.textMuted, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, color: PulseColors.primaryMint, size: 18),
                            onPressed: () => _searchOrNavigate(_searchController.text),
                          ),
                        ],
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: _searchOrNavigate,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Instant Grab Cards Toggle Button
              Container(
                decoration: BoxDecoration(
                  color: _showQuickCards ? PulseColors.primaryMint : PulseColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: Icon(
                    _showQuickCards ? Icons.view_stream : Icons.dashboard_outlined,
                    color: _showQuickCards ? PulseColors.onPrimary : PulseColors.textWhite,
                    size: 20,
                  ),
                  tooltip: 'Toggle Instant Grab Feed',
                  onPressed: () {
                    if (!_showQuickCards && _quickSearchResults.isEmpty && _searchController.text.isNotEmpty) {
                      _performQuickSearch(_searchController.text);
                    }
                    setState(() {
                      _showQuickCards = !_showQuickCards;
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.refresh, color: PulseColors.textWhite, size: 20),
                onPressed: () => controller.reload(),
              ),
            ],
          ),
        ),

        // WebView Load Progress Bar
        if (_isLoading)
          LinearProgressIndicator(
            value: _loadProgress,
            minHeight: 2.5,
            backgroundColor: PulseColors.surfaceContainerLowest,
            valueColor: const AlwaysStoppedAnimation<Color>(PulseColors.primaryMint),
          ),

        // Body: WebView or Instant Grab Card Feed
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: controller),

              // Instant Grab Cards Overlay (when toggled)
              if (_showQuickCards)
                Container(
                  color: PulseColors.background.withOpacity(0.96),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.asset('assets/logo.png', width: 18, height: 18, fit: BoxFit.cover),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'INSTANT AUDIO GRAB FEED',
                                  style: TextStyle(
                                    color: PulseColors.primaryMint,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: PulseColors.textMuted, size: 20),
                              onPressed: () => setState(() => _showQuickCards = false),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _quickSearchResults.isEmpty
                            ? Center(
                                child: Text(
                                  _searchController.text.isEmpty
                                      ? 'Search any song or artist in the search bar above'
                                      : 'No search results found',
                                  style: const TextStyle(color: PulseColors.textMuted, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _quickSearchResults.length,
                                itemBuilder: (context, index) {
                                  final item = _quickSearchResults[index];
                                  return _buildInstantGrabCard(item);
                                },
                              ),
                      ),
                    ],
                  ),
                ),

              // Floating "⚡ Grab Audio as MP3" Button when a video page is active
              if (_detectedVideoId != null && !_showQuickCards)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PulseColors.surfaceContainerHigh.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: PulseColors.primaryMint, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: PulseColors.primaryMint.withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset('assets/logo.png', width: 36, height: 36, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _detectedTitle ?? 'Detected YouTube Video',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PulseColors.textWhite, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Text(
                                'Tap to extract pure audio (320k)',
                                style: TextStyle(color: PulseColors.primaryMint, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            if (_detectedVideoId != null) {
                              _triggerDirectMp3Download(_detectedVideoId!, defaultTitle: _detectedTitle);
                            }
                          },
                          icon: const Icon(Icons.download, size: 16, color: PulseColors.onPrimary),
                          label: const Text('Grab MP3', style: TextStyle(color: PulseColors.onPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: PulseColors.primaryMint,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstantGrabCard(YouTubeVideoItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: PulseColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1AFFFFFF), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _triggerDirectMp3Download(item.id, defaultTitle: item.title, defaultChannel: item.channel);
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.network(
                    item.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: PulseColors.surfaceContainerLowest,
                      child: const Icon(Icons.music_note, color: PulseColors.primaryMint),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PulseColors.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.channel} • ${item.duration}',
                      style: const TextStyle(color: PulseColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: PulseColors.primaryMint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download, color: PulseColors.onPrimary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
