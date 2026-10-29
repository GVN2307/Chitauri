import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../theme/pulse_theme.dart';
import 'shimmer_placeholder.dart';

class CachedBannerImage extends StatefulWidget {
  final String? imageUrl;
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final IconData fallbackIcon;

  const CachedBannerImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.music_note_rounded,
  });

  static final Map<String, Uint8List> _memCache = {};

  @override
  State<CachedBannerImage> createState() => _CachedBannerImageState();
}

class _CachedBannerImageState extends State<CachedBannerImage> {
  Uint8List? _imageBytes;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant CachedBannerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  String _hashUrl(String url) {
    return '${url.hashCode.abs().toRadixString(36)}_${url.length}';
  }

  Future<void> _loadImage() async {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    // 1. Check in-memory cache
    if (CachedBannerImage._memCache.containsKey(url)) {
      if (mounted) {
        setState(() {
          _imageBytes = CachedBannerImage._memCache[url];
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // 2. Check local disk cache
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final bannerDir = Directory('${cacheDir.path}/banner_cache');
      if (!await bannerDir.exists()) {
        await bannerDir.create(recursive: true);
      }
      final diskFile = File('${bannerDir.path}/${_hashUrl(url)}.jpg');

      if (await diskFile.exists() && await diskFile.length() > 500) {
        final bytes = await diskFile.readAsBytes();
        CachedBannerImage._memCache[url] = bytes;
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _isLoading = false;
            _hasError = false;
          });
        }
        return;
      }

      // 3. Download from CDN
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 7));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        final bytes = resp.bodyBytes;
        await diskFile.writeAsBytes(bytes, flush: true);
        CachedBannerImage._memCache[url] = bytes;
        if (mounted) {
          setState(() {
            _imageBytes = bytes;
            _isLoading = false;
            _hasError = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(12);

    if (_isLoading) {
      return ShimmerPlaceholder(
        width: widget.width,
        height: widget.height,
        borderRadius: radius,
      );
    }

    if (_hasError || _imageBytes == null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: PulseColors.surfaceContainerHigh,
          borderRadius: radius,
          border: Border.all(color: PulseColors.cardBorder, width: 1),
        ),
        child: Center(
          child: Icon(widget.fallbackIcon, color: PulseColors.primaryMint.withOpacity(0.5), size: 28),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.memory(
        _imageBytes!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
      ),
    );
  }
}
