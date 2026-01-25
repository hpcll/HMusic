import 'package:json_annotation/json_annotation.dart';

part 'music.g.dart';

@JsonSerializable()
class Music {
  final String name;
  final String? title;
  final String? artist;
  final String? album;
  final String? duration;
  final String? picture;
  
  const Music({
    required this.name,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.picture,
  });
  
  factory Music.fromJson(Map<String, dynamic> json) => _$MusicFromJson(json);
  Map<String, dynamic> toJson() => _$MusicToJson(this);
}