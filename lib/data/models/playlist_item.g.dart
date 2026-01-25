// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaylistItem _$PlaylistItemFromJson(Map<String, dynamic> json) => PlaylistItem(
  title: json['title'] as String,
  artist: json['artist'] as String,
  album: json['album'] as String?,
  duration: (json['duration'] as num).toInt(),
  sourceType: json['sourceType'] as String,
  platform: json['platform'] as String?,
  songId: json['songId'] as String?,
  coverUrl: json['coverUrl'] as String?,
  lrc: json['lrc'] as String?,
  localPath: json['localPath'] as String?,
);

Map<String, dynamic> _$PlaylistItemToJson(PlaylistItem instance) =>
    <String, dynamic>{
      'title': instance.title,
      'artist': instance.artist,
      'album': instance.album,
      'duration': instance.duration,
      'sourceType': instance.sourceType,
      'platform': instance.platform,
      'songId': instance.songId,
      'coverUrl': instance.coverUrl,
      'lrc': instance.lrc,
      'localPath': instance.localPath,
    };
