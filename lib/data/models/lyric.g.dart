// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyric.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LyricLine _$LyricLineFromJson(Map<String, dynamic> json) => LyricLine(
  timestamp: (json['timestamp'] as num).toInt(),
  text: json['text'] as String,
);

Map<String, dynamic> _$LyricLineToJson(LyricLine instance) => <String, dynamic>{
  'timestamp': instance.timestamp,
  'text': instance.text,
};

Lyric _$LyricFromJson(Map<String, dynamic> json) => Lyric(
  lines:
      (json['lines'] as List<dynamic>)
          .map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
          .toList(),
  songName: json['songName'] as String?,
  artist: json['artist'] as String?,
);

Map<String, dynamic> _$LyricToJson(Lyric instance) => <String, dynamic>{
  'lines': instance.lines,
  'songName': instance.songName,
  'artist': instance.artist,
};
