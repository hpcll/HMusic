import 'package:json_annotation/json_annotation.dart';

part 'local_playlist.g.dart';

/// 本地播放列表（用于直连模式）
/// 存储在 SharedPreferences 中，使用 JSON 序列化
@JsonSerializable(explicitToJson: true)
class LocalPlaylist {
  final String id; // 播放列表唯一标识
  final String name; // 播放列表名称
  final List<LocalPlaylistSong> songs; // 歌曲列表
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 更新时间

  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalPlaylist.fromJson(Map<String, dynamic> json) =>
      _$LocalPlaylistFromJson(json);

  Map<String, dynamic> toJson() => _$LocalPlaylistToJson(this);

  /// 创建新的播放列表
  factory LocalPlaylist.create({required String name}) {
    final now = DateTime.now();
    return LocalPlaylist(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      songs: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 复制并更新部分字段
  LocalPlaylist copyWith({
    String? id,
    String? name,
    List<LocalPlaylistSong>? songs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LocalPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 歌曲数量
  int get count => songs.length;

  @override
  String toString() {
    return 'LocalPlaylist(id: $id, name: $name, count: $count)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPlaylist && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// 本地播放列表中的歌曲信息（简化版）
/// 只存储必要信息，避免冗余
@JsonSerializable()
class LocalPlaylistSong {
  final String title; // 歌曲名称
  final String artist; // 艺术家
  final String? platform; // 平台（在线音乐：qq/netease/kuwo等）
  final String? songId; // 歌曲ID（在线音乐）
  final String? localPath; // 本地路径（本地音乐）
  final String? coverUrl; // 封面图URL
  final String? cachedUrl; // 🎯 缓存的播放链接
  final DateTime? urlExpireTime; // 🎯 链接过期时间（6小时有效期）
  final int? duration; // 🎯 歌曲时长（秒），用于进度条显示

  const LocalPlaylistSong({
    required this.title,
    required this.artist,
    this.platform,
    this.songId,
    this.localPath,
    this.coverUrl,
    this.cachedUrl,
    this.urlExpireTime,
    this.duration,
  });

  factory LocalPlaylistSong.fromJson(Map<String, dynamic> json) =>
      _$LocalPlaylistSongFromJson(json);

  Map<String, dynamic> toJson() => _$LocalPlaylistSongToJson(this);

  /// 从在线搜索结果创建
  factory LocalPlaylistSong.fromOnlineMusic({
    required String title,
    required String artist,
    required String platform,
    required String songId,
    String? coverUrl,
    int? duration,
  }) {
    return LocalPlaylistSong(
      title: title,
      artist: artist,
      platform: platform,
      songId: songId,
      coverUrl: coverUrl,
      duration: duration,
    );
  }

  /// 从本地音乐创建
  factory LocalPlaylistSong.fromLocalMusic({
    required String title,
    required String artist,
    required String localPath,
    String? coverUrl,
  }) {
    return LocalPlaylistSong(
      title: title,
      artist: artist,
      localPath: localPath,
      coverUrl: coverUrl,
    );
  }

  /// 显示名称（歌名 - 歌手）
  String get displayName => '$title - $artist';

  /// 是否为在线音乐
  bool get isOnline => platform != null && songId != null;

  /// 是否为本地音乐
  bool get isLocal => localPath != null;

  /// 🎯 检查缓存的播放链接是否有效（6小时内）
  bool get isCacheValid {
    if (cachedUrl == null || cachedUrl!.isEmpty) return false;
    if (urlExpireTime == null) return false;
    return DateTime.now().isBefore(urlExpireTime!);
  }

  /// 🎯 复制并更新缓存信息
  LocalPlaylistSong copyWith({
    String? title,
    String? artist,
    String? platform,
    String? songId,
    String? localPath,
    String? coverUrl,
    String? cachedUrl,
    DateTime? urlExpireTime,
    int? duration,
  }) {
    return LocalPlaylistSong(
      title: title ?? this.title,
      artist: artist ?? this.artist,
      platform: platform ?? this.platform,
      songId: songId ?? this.songId,
      localPath: localPath ?? this.localPath,
      coverUrl: coverUrl ?? this.coverUrl,
      cachedUrl: cachedUrl ?? this.cachedUrl,
      urlExpireTime: urlExpireTime ?? this.urlExpireTime,
      duration: duration ?? this.duration,
    );
  }

  @override
  String toString() {
    return 'LocalPlaylistSong(title: $title, artist: $artist, platform: $platform, songId: $songId)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPlaylistSong &&
        other.title == title &&
        other.artist == artist &&
        other.platform == platform &&
        other.songId == songId &&
        other.localPath == localPath &&
        other.cachedUrl == cachedUrl &&
        other.urlExpireTime == urlExpireTime;
  }

  @override
  int get hashCode {
    return Object.hash(
      title,
      artist,
      platform,
      songId,
      localPath,
      cachedUrl,
      urlExpireTime,
    );
  }
}
