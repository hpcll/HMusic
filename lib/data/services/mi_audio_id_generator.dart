import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// 音频ID生成工具类
/// 基于xiaomusic项目的音频ID生成逻辑
class MiAudioIdGenerator {
  /// 默认音频ID（当无法从QQ音乐获取时使用）
  static const String DEFAULT_AUDIO_ID = '1582971365183456177';

  /// 生成音频ID
  /// [musicName] 音乐名称
  /// [deviceId] 设备ID（可选）
  /// 返回音频ID字符串
  static Future<String> generateAudioId({
    required String musicName,
    String? deviceId,
  }) async {
    // TODO: 这里需要实现QQ音乐的搜索API来获取真实的音频ID
    // 暂时使用默认ID，后续可以集成QQ音乐搜索API

    if (kDebugMode) {
      debugPrint('🎵 [AudioId] 生成音频ID: 音乐名称=$musicName, 设备ID=$deviceId');
    }

    // 模拟生成过程 - 实际应该调用QQ音乐API
    // 这里可以基于音乐名称生成一个"伪"ID，确保同一首歌总是返回相同ID
    final pseudoId = _generatePseudoAudioId(musicName);

    if (kDebugMode) {
      debugPrint('✅ [AudioId] 音频ID生成结果: $pseudoId');
    }
    return pseudoId;
  }

  /// 基于音乐名称生成伪音频ID（确保一致性）
  static String _generatePseudoAudioId(String musicName) {
    // 使用简单的哈希算法生成一致的伪ID
    final bytes = utf8.encode(musicName.toLowerCase().trim());
    final hash = bytes.fold<int>(0, (prev, byte) => prev + byte);

    // 确保ID在合理范围内（1-9999999999999999999）
    final pseudoId = (hash % 999999999) + 100000000;

    return pseudoId.toString();
  }

  /// 从音乐URL中提取音频ID（如果可能）
  static String? extractAudioIdFromUrl(String url) {
    // QQ音乐URL格式示例：
    // https://dl.stream.qqmusic.qq.com/C400003AY4bI2e5Y0Q.m4a?guid=...
    // https://y.qq.com/n/ryqq/songDetail/003AY4bI2e5Y0Q.html

    try {
      final uri = Uri.parse(url);

      // 从QQ音乐URL中提取ID
      if (uri.host.contains('qqmusic.qq.com')) {
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final lastSegment = pathSegments.last;
          // 处理 C400003AY4bI2e5Y0Q.m4a 格式
          if (lastSegment.startsWith('C400') && lastSegment.endsWith('.m4a')) {
            return lastSegment.substring(3, lastSegment.length - 4); // 去掉 C400 和 .m4a
          }
        }
      }

      // 从y.qq.com页面URL中提取ID
      if (uri.host.contains('y.qq.com')) {
        final path = uri.path;
        if (path.contains('/songDetail/')) {
          final idStart = path.indexOf('/songDetail/') + '/songDetail/'.length;
          final idEnd = path.indexOf('.html');
          if (idStart > 0 && idEnd > idStart) {
            return path.substring(idStart, idEnd);
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ [AudioId] 从URL提取音频ID失败: $e');
      return null;
    }
  }

  /// 验证音频ID格式
  static bool isValidAudioId(String audioId) {
    if (audioId.isEmpty) return false;

    // 音频ID应该是纯数字
    return RegExp(r'^\d+$').hasMatch(audioId);
  }

  /// 获取音频ID类型描述
  static String getAudioIdTypeDescription(String audioId) {
    if (audioId == DEFAULT_AUDIO_ID) {
      return '默认音频ID';
    }

    if (audioId.startsWith('1')) {
      return 'QQ音乐音频ID';
    }

    if (audioId.startsWith('2')) {
      return '网易云音乐音频ID';
    }

    return '自定义音频ID';
  }
}