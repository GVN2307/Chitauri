class Track {
  final String id;
  final String title;
  final String artist;
  final String filePath;
  final int durationSecs;
  final int fileSize;
  final String? thumbnailUrl;
  final String? description;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.filePath,
    required this.durationSecs,
    required this.fileSize,
    this.thumbnailUrl,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'filePath': filePath,
    'durationSecs': durationSecs,
    'fileSize': fileSize,
    'thumbnailUrl': thumbnailUrl,
    'description': description,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    filePath: json['filePath'] as String,
    durationSecs: (json['durationSecs'] as num?)?.toInt() ?? 0,
    fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    description: json['description'] as String?,
  );

  String get durationFormatted {
    if (durationSecs <= 0) return '--:--';
    final m = durationSecs ~/ 60;
    final s = durationSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class YouTubeVideoItem {
  final String id;
  final String title;
  final String channel;
  final String duration;
  final String views;
  final String thumbnailUrl;
  final String url;

  YouTubeVideoItem({
    required this.id,
    required this.title,
    required this.channel,
    required this.duration,
    required this.views,
    required this.thumbnailUrl,
    required this.url,
  });
}

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class PidManager {
  static int _counter = 1000;
  static int nextPid() => ++_counter;
}

class DownloadTask {
  final int pid;
  final String videoId;
  String title;
  String channel;
  double progress;
  DownloadStatus status;
  String statusText;
  String? errorMessage;
  String? localPath;
  final DateTime createdAt;

  DownloadTask({
    int? pid,
    required this.videoId,
    required this.title,
    required this.channel,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
    this.statusText = 'Queued',
    this.errorMessage,
    this.localPath,
    DateTime? createdAt,
  })  : pid = pid ?? PidManager.nextPid(),
        createdAt = createdAt ?? DateTime.now();

  String get processIdentifier => 'PID_${pid}_$videoId';
}

enum RepeatMode { off, all, one }

class Playlist {
  final String id;
  final String name;
  final DateTime createdAt;
  final List<String> trackIds;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.trackIds,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'trackIds': trackIds,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    trackIds: (json['trackIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
  );
}
