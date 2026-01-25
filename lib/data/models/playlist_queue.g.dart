// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_queue.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaylistQueue _$PlaylistQueueFromJson(Map<String, dynamic> json) =>
    PlaylistQueue(
      queueId: json['queueId'] as String,
      queueName: json['queueName'] as String,
      source: $enumDecode(_$PlaylistSourceEnumMap, json['source']),
      items:
          (json['items'] as List<dynamic>)
              .map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
              .toList(),
      currentIndex: (json['currentIndex'] as num).toInt(),
      playMode: $enumDecode(_$QueuePlayModeEnumMap, json['playMode']),
    );

Map<String, dynamic> _$PlaylistQueueToJson(PlaylistQueue instance) =>
    <String, dynamic>{
      'queueId': instance.queueId,
      'queueName': instance.queueName,
      'source': _$PlaylistSourceEnumMap[instance.source]!,
      'items': instance.items.map((e) => e.toJson()).toList(),
      'currentIndex': instance.currentIndex,
      'playMode': _$QueuePlayModeEnumMap[instance.playMode]!,
    };

const _$PlaylistSourceEnumMap = {
  PlaylistSource.musicLibrary: 'music_library',
  PlaylistSource.searchResult: 'search_result',
  PlaylistSource.favorites: 'favorites',
  PlaylistSource.customPlaylist: 'custom_playlist',
};

const _$QueuePlayModeEnumMap = {
  QueuePlayMode.listLoop: 'list_loop',
  QueuePlayMode.singleLoop: 'single_loop',
  QueuePlayMode.random: 'random',
  QueuePlayMode.sequence: 'sequence',
};
