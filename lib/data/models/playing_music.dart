import 'package:json_annotation/json_annotation.dart';

part 'playing_music.g.dart';

@JsonSerializable()
class PlayingMusic {
  final String ret;
  @JsonKey(name: 'is_playing')
  final bool isPlaying;
  @JsonKey(name: 'cur_music')
  final String curMusic;
  @JsonKey(name: 'cur_playlist')
  final String curPlaylist;
  final int offset;
  final int duration;
  
  const PlayingMusic({
    required this.ret,
    required this.isPlaying,
    required this.curMusic,
    required this.curPlaylist,
    required this.offset,
    required this.duration,
  });
  
  factory PlayingMusic.fromJson(Map<String, dynamic> json) => _$PlayingMusicFromJson(json);
  Map<String, dynamic> toJson() => _$PlayingMusicToJson(this);
}