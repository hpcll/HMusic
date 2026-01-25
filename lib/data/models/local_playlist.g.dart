// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_playlist.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalPlaylist _$LocalPlaylistFromJson(Map<String, dynamic> json) =>
    LocalPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      songs:
          (json['songs'] as List<dynamic>)
              .map((e) => LocalPlaylistSong.fromJson(e as Map<String, dynamic>))
              .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$LocalPlaylistToJson(LocalPlaylist instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'songs': instance.songs.map((e) => e.toJson()).toList(),
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

LocalPlaylistSong _$LocalPlaylistSongFromJson(Map<String, dynamic> json) =>
    LocalPlaylistSong(
      title: json['title'] as String,
      artist: json['artist'] as String,
      platform: json['platform'] as String?,
      songId: json['songId'] as String?,
      localPath: json['localPath'] as String?,
      coverUrl: json['coverUrl'] as String?,
      cachedUrl: json['cachedUrl'] as String?,
      urlExpireTime:
          json['urlExpireTime'] == null
              ? null
              : DateTime.parse(json['urlExpireTime'] as String),
    );

Map<String, dynamic> _$LocalPlaylistSongToJson(LocalPlaylistSong instance) =>
    <String, dynamic>{
      'title': instance.title,
      'artist': instance.artist,
      'platform': instance.platform,
      'songId': instance.songId,
      'localPath': instance.localPath,
      'coverUrl': instance.coverUrl,
      'cachedUrl': instance.cachedUrl,
      'urlExpireTime': instance.urlExpireTime?.toIso8601String(),
    };
