import 'package:flutter/services.dart';

class AudioFxService {
  static final AudioFxService instance = AudioFxService._internal();
  AudioFxService._internal();

  static const _channel = MethodChannel('com.chitauri.audio/hardware_fx');

  Future<void> setBandLevel(int band, double dB) async {
    try {
      // Android equalizer accepts millibels (1 dB = 100 mB)
      final millibels = (dB * 100).round().clamp(-1200, 1200);
      await _channel.invokeMethod('setBandLevel', {
        'band': band,
        'level': millibels,
      });
    } catch (_) {}
  }

  Future<void> setBassBoost(bool enabled, double strength) async {
    try {
      // Strength range: 0 to 1000
      final s = (strength * 1000).round().clamp(0, 1000);
      await _channel.invokeMethod('setBassBoost', {
        'enabled': enabled,
        'strength': s,
      });
    } catch (_) {}
  }

  Future<void> setVirtualizer(bool enabled, double strength) async {
    try {
      // Strength range: 0 to 1000
      final s = (strength * 1000).round().clamp(0, 1000);
      await _channel.invokeMethod('setVirtualizer', {
        'enabled': enabled,
        'strength': s,
      });
    } catch (_) {}
  }

  Future<bool> shareAudioFile(String filePath, String title) async {
    try {
      final res = await _channel.invokeMethod<bool>('shareAudioFile', {
        'path': filePath,
        'title': title,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
