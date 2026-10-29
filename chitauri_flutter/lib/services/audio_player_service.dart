import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import 'storage_service.dart';
import 'taste_profiler.dart';

class AudioPlayerService {
  static final AudioPlayerService instance = AudioPlayerService._internal();
  AudioPlayerService._internal() {
    _init();
  }

  final AudioPlayer _player = AudioPlayer();
  static const MethodChannel _nativeMediaSession = MethodChannel('com.chitauri.audio/media_session');

  List<Track> _originalQueue = [];
  List<Track> _playbackQueue = [];
  int _currentIndex = -1;

  bool _isPlaying = false;
  bool _isShuffled = false;
  RepeatMode _repeatMode = RepeatMode.off;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  Timer? _positionTicker;

  // Stream controllers for UI reactivity
  final _stateController = StreamController<bool>.broadcast();
  final _trackController = StreamController<Track?>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _shuffleController = StreamController<bool>.broadcast();
  final _repeatController = StreamController<RepeatMode>.broadcast();
  final _queueController = StreamController<List<Track>>.broadcast();

  Stream<bool> get isPlayingStream => _stateController.stream;
  Stream<Track?> get currentTrackStream => _trackController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<bool> get isShuffledStream => _shuffleController.stream;
  Stream<RepeatMode> get repeatModeStream => _repeatController.stream;
  Stream<List<Track>> get queueStream => _queueController.stream;

  bool get isPlaying => _isPlaying;
  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  Track? get currentTrack => (_currentIndex >= 0 && _currentIndex < _playbackQueue.length)
      ? _playbackQueue[_currentIndex]
      : null;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => List.unmodifiable(_playbackQueue);
  double get volume => _volume;

  void updateTrackMetadata(Track updated) {
    bool notify = false;
    for (int i = 0; i < _playbackQueue.length; i++) {
      if (_playbackQueue[i].id == updated.id) {
        _playbackQueue[i] = updated;
        notify = true;
      }
    }
    for (int i = 0; i < _originalQueue.length; i++) {
      if (_originalQueue[i].id == updated.id) {
        _originalQueue[i] = updated;
      }
    }
    if (_currentIndex >= 0 && _currentIndex < _playbackQueue.length && _playbackQueue[_currentIndex].id == updated.id) {
      _trackController.add(_playbackQueue[_currentIndex]);
    }
    if (notify) {
      _queueController.add(_playbackQueue);
    }
    _syncWithNativeMediaSession();
  }

  void _syncWithNativeMediaSession() {
    final t = currentTrack;
    if (t == null) {
      try {
        _nativeMediaSession.invokeMethod('stop');
      } catch (_) {}
      return;
    }

    try {
      _nativeMediaSession.invokeMethod('updatePlayback', {
        'title': t.title,
        'artist': t.artist,
        'isPlaying': _isPlaying,
        'positionMs': _position.inMilliseconds,
        'durationMs': _duration.inMilliseconds > 0 ? _duration.inMilliseconds : (t.durationSecs * 1000),
        'thumbnailUrl': t.thumbnailUrl,
      });
    } catch (_) {}
  }

  void _init() {
    try {
      AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.defaultToSpeaker},
        ),
      ));
    } catch (_) {}

    _nativeMediaSession.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAction':
          final action = call.arguments as String?;
          if (action == 'play') {
            await play();
          } else if (action == 'pause') {
            await pause();
          } else if (action == 'next') {
            await next();
          } else if (action == 'previous') {
            await previous();
          } else if (action == 'stop') {
            await stop();
          }
          break;
        case 'onActionSeek':
          final posMs = (call.arguments as num?)?.toInt() ?? 0;
          await seek(Duration(milliseconds: posMs));
          break;
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _stateController.add(_isPlaying);
      _syncWithNativeMediaSession();
      if (_isPlaying) {
        _startTicker();
      } else {
        _stopTicker();
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (pos > Duration.zero) {
        _position = pos;
        _positionController.add(pos);
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (dur > Duration.zero) {
        _duration = dur;
        _durationController.add(dur);
        _syncWithNativeMediaSession();
        final t = currentTrack;
        if (t != null && (t.durationSecs <= 0 || t.durationSecs == 213 || t.durationSecs == 215 || t.durationSecs == 228 || (t.durationSecs - dur.inSeconds).abs() > 2)) {
          final updated = Track(
            id: t.id,
            title: t.title,
            artist: t.artist,
            filePath: t.filePath,
            durationSecs: dur.inSeconds,
            fileSize: t.fileSize,
            thumbnailUrl: t.thumbnailUrl,
            description: t.description,
          );
          updateTrackMetadata(updated);
          StorageService.instance.updateTrack(updated);
        }
      }
    });

    _player.onPlayerComplete.listen((_) {
      _onTrackComplete();
    });
  }

  void _startTicker() {
    _positionTicker?.cancel();
    _positionTicker = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isPlaying) {
        final nextPos = _position + const Duration(milliseconds: 500);
        if (_duration > Duration.zero && nextPos >= _duration) {
          _position = _duration;
          _positionController.add(_position);
          // Do NOT artificially call _onTrackComplete() here! Let hardware _player.onPlayerComplete trigger actual track completion to prevent halfway-skips
        } else {
          _position = nextPos;
          _positionController.add(_position);
        }
      }
    });
  }

  void _stopTicker() {
    _positionTicker?.cancel();
    _positionTicker = null;
  }

  void _onTrackComplete() async {
    if (_repeatMode == RepeatMode.one) {
      final cur = currentTrack;
      if (cur != null) {
        try {
          await _player.stop();
          await _player.play(DeviceFileSource(cur.filePath));
        } catch (_) {
          await seek(Duration.zero);
          await play();
        }
      }
    } else {
      next();
    }
  }

  Future<void> setQueue(List<Track> tracks, {int startIndex = 0}) async {
    _originalQueue = List.from(tracks);
    _playbackQueue = List.from(tracks);
    _currentIndex = startIndex;
    _queueController.add(_playbackQueue);

    if (_isShuffled) {
      _applyShuffle();
    }

    if (currentTrack != null) {
      await _loadAndPlay(currentTrack!);
    }
  }

  Future<void> playTrack(Track track, List<Track> allTracks) async {
    _originalQueue = List.from(allTracks);
    _playbackQueue = List.from(allTracks);
    _currentIndex = _playbackQueue.indexWhere((t) => t.id == track.id);
    if (_currentIndex == -1) {
      _playbackQueue.insert(0, track);
      _currentIndex = 0;
    }

    if (_isShuffled) {
      _applyShuffle();
    }

    _queueController.add(_playbackQueue);
    await _loadAndPlay(track);
  }

  Future<void> _loadAndPlay(Track track) async {
    _stopTicker();
    _position = Duration.zero;
    _duration = Duration(seconds: track.durationSecs > 0 ? track.durationSecs : 0);
    _positionController.add(_position);
    _durationController.add(_duration);
    _trackController.add(track);

    try {
      await _player.stop();
      if (File(track.filePath).existsSync()) {
        await _player.setSource(DeviceFileSource(track.filePath));
        final trueDur = await _player.getDuration();
        if (trueDur != null && trueDur > Duration.zero) {
          _duration = trueDur;
          _durationController.add(_duration);
          if (track.durationSecs <= 0 || track.durationSecs == 213 || track.durationSecs == 215 || track.durationSecs == 228 || (track.durationSecs - trueDur.inSeconds).abs() > 2) {
            final updated = Track(
              id: track.id,
              title: track.title,
              artist: track.artist,
              filePath: track.filePath,
              durationSecs: trueDur.inSeconds,
              fileSize: track.fileSize,
              thumbnailUrl: track.thumbnailUrl,
              description: track.description,
            );
            updateTrackMetadata(updated);
            StorageService.instance.updateTrack(updated);
          }
        }
      }
      await _player.resume();
      _isPlaying = true;
      _stateController.add(true);
      _startTicker();
      unawaited(TasteProfiler.instance.recordPlay(track));
    } catch (e) {
      _isPlaying = true;
      _stateController.add(true);
      _startTicker();
    }
    _syncWithNativeMediaSession();
  }

  Future<void> play() async {
    try {
      await _player.resume();
    } catch (_) {}
    _isPlaying = true;
    _stateController.add(true);
    _startTicker();
    _syncWithNativeMediaSession();
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
    _isPlaying = false;
    _stateController.add(false);
    _stopTicker();
    _syncWithNativeMediaSession();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_playbackQueue.isEmpty) return;

    if (_currentIndex + 1 < _playbackQueue.length) {
      _currentIndex++;
      await _loadAndPlay(_playbackQueue[_currentIndex]);
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = 0;
      await _loadAndPlay(_playbackQueue[_currentIndex]);
    } else {
      await seek(Duration.zero);
      await pause();
    }
  }

  Future<void> previous() async {
    if (_playbackQueue.isEmpty) return;

    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      await _loadAndPlay(_playbackQueue[_currentIndex]);
    } else {
      await seek(Duration.zero);
    }
  }

  Future<void> seek(Duration position) async {
    _position = position;
    _positionController.add(_position);
    try {
      await _player.seek(position);
    } catch (_) {}
    _syncWithNativeMediaSession();
  }

  Future<void> rewind10() async {
    final newPos = _position - const Duration(seconds: 10);
    await seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  Future<void> forward10() async {
    final newPos = _position + const Duration(seconds: 10);
    await seek(_duration > Duration.zero && newPos > _duration ? _duration : newPos);
  }

  void cycleRepeatMode() {
    toggleRepeatMode();
  }

  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    _shuffleController.add(_isShuffled);

    if (_isShuffled) {
      _applyShuffle();
    } else {
      final cur = currentTrack;
      _playbackQueue = List.from(_originalQueue);
      if (cur != null) {
        _currentIndex = _playbackQueue.indexWhere((t) => t.id == cur.id);
      }
    }
    _queueController.add(_playbackQueue);
  }

  void _applyShuffle() {
    if (_playbackQueue.isEmpty) return;
    final cur = currentTrack;
    final others = _originalQueue.where((t) => t.id != cur?.id).toList();

    final rng = Random();
    for (int i = others.length - 1; i > 0; i--) {
      int j = rng.nextInt(i + 1);
      final temp = others[i];
      others[i] = others[j];
      others[j] = temp;
    }

    if (cur != null) {
      _playbackQueue = [cur, ...others];
      _currentIndex = 0;
    } else {
      _playbackQueue = others;
      _currentIndex = 0;
    }
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
    }
    _repeatController.add(_repeatMode);
  }

  Future<void> setVolume(double val) async {
    _volume = val.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_volume);
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopTicker();
    try {
      await _player.stop();
    } catch (_) {}
    _isPlaying = false;
    _stateController.add(false);
    _syncWithNativeMediaSession();
  }

  void dispose() {
    _stopTicker();
    _player.dispose();
    _stateController.close();
    _trackController.close();
    _positionController.close();
    _durationController.close();
    _shuffleController.close();
    _repeatController.close();
    _queueController.close();
  }
}
