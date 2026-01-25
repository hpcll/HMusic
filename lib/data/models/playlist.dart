import 'package:json_annotation/json_annotation.dart';

part 'playlist.g.dart';

@JsonSerializable()
class Playlist {
  final String name;
  final List<String>? musicList;
  final int? count;
  
  const Playlist({
    required this.name,
    this.musicList,
    this.count,
  });
  
  factory Playlist.fromJson(Map<String, dynamic> json) => _$PlaylistFromJson(json);
  Map<String, dynamic> toJson() => _$PlaylistToJson(this);
}