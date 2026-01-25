// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playing_music.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlayingMusic _$PlayingMusicFromJson(Map<String, dynamic> json) => PlayingMusic(
  ret: json['ret'] as String,
  isPlaying: json['is_playing'] as bool,
  curMusic: json['cur_music'] as String,
  curPlaylist: json['cur_playlist'] as String,
  offset: (json['offset'] as num).toInt(),
  duration: (json['duration'] as num).toInt(),
);

Map<String, dynamic> _$PlayingMusicToJson(PlayingMusic instance) =>
    <String, dynamic>{
      'ret': instance.ret,
      'is_playing': instance.isPlaying,
      'cur_music': instance.curMusic,
      'cur_playlist': instance.curPlaylist,
      'offset': instance.offset,
      'duration': instance.duration,
    };
