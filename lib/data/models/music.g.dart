// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Music _$MusicFromJson(Map<String, dynamic> json) => Music(
  name: json['name'] as String,
  title: json['title'] as String?,
  artist: json['artist'] as String?,
  album: json['album'] as String?,
  duration: json['duration'] as String?,
  picture: json['picture'] as String?,
);

Map<String, dynamic> _$MusicToJson(Music instance) => <String, dynamic>{
  'name': instance.name,
  'title': instance.title,
  'artist': instance.artist,
  'album': instance.album,
  'duration': instance.duration,
  'picture': instance.picture,
};
