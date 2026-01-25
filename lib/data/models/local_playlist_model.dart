import 'package:flutter/foundation.dart';

/// 🎵 本地歌单模型
///
/// 用于直连模式的本地歌单管理
class LocalPlaylistModel {
  final String id; // 歌单ID（唯一标识）
  final String name; // 歌单名称
  final List<String> songs; // 歌曲列表
  final String? coverUrl; // 歌单封面URL
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 最后更新时间
  final String? description; // 歌单描述

  const LocalPlaylistModel({
    required this.id,
    required this.name,
    required this.songs,
    this.coverUrl,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  /// 从JSON创建
  factory LocalPlaylistModel.fromJson(Map<String, dynamic> json) {
    return LocalPlaylistModel(
      id: json['id'] as String,
      name: json['name'] as String,
      songs: (json['songs'] as List<dynamic>).cast<String>(),
      coverUrl: json['coverUrl'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      description: json['description'] as String?,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songs': songs,
      'coverUrl': coverUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'description': description,
    };
  }

  /// 复制并修改
  LocalPlaylistModel copyWith({
    String? id,
    String? name,
    List<String>? songs,
    String? coverUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
  }) {
    return LocalPlaylistModel(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      coverUrl: coverUrl ?? this.coverUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
    );
  }

  @override
  String toString() {
    return 'LocalPlaylistModel(id: $id, name: $name, songs: ${songs.length}首)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is LocalPlaylistModel &&
        other.id == id &&
        other.name == name &&
        listEquals(other.songs, songs) &&
        other.coverUrl == coverUrl &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.description == description;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        songs.hashCode ^
        coverUrl.hashCode ^
        createdAt.hashCode ^
        updatedAt.hashCode ^
        description.hashCode;
  }
}
