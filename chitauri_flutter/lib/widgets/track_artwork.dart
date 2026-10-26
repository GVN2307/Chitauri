import 'dart:io';
import 'package:flutter/material.dart';

class TrackArtwork extends StatelessWidget {
  final String? thumbUrl;
  final double? width;
  final double? height;
  final double borderRadius;
  final BoxFit fit;
  final Widget? fallback;

  const TrackArtwork({
    super.key,
    required this.thumbUrl,
    this.width,
    this.height,
    this.borderRadius = 8.0,
    this.fit = BoxFit.cover,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final defaultFallback = fallback ??
        Image.asset(
          'assets/logo.png',
          width: width,
          height: height,
          fit: fit,
        );

    Widget imageWidget = defaultFallback;

    if (thumbUrl != null && thumbUrl!.isNotEmpty) {
      if (thumbUrl!.startsWith('/') || !thumbUrl!.startsWith('http')) {
        final f = File(thumbUrl!);
        if (f.existsSync()) {
          imageWidget = Image.file(
            f,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => defaultFallback,
          );
        }
      } else {
        imageWidget = Image.network(
          thumbUrl!,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => defaultFallback,
        );
      }
    }

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: width,
          height: height,
          child: imageWidget,
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: imageWidget,
    );
  }
}
