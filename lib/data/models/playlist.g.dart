// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Playlist _$PlaylistFromJson(Map<String, dynamic> json) => Playlist(
  name: json['name'] as String,
  musicList:
      (json['musicList'] as List<dynamic>?)?.map((e) => e as String).toList(),
  count: (json['count'] as num?)?.toInt(),
);

Map<String, dynamic> _$PlaylistToJson(Playlist instance) => <String, dynamic>{
  'name': instance.name,
  'musicList': instance.musicList,
  'count': instance.count,
};
