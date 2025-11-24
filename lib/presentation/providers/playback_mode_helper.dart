/// 🎵 播放模式辅助类
/// 用于简化直连模式播放，不修改现有的 playback_provider 复杂逻辑

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/online_music_result.dart';
import '../../data/services/mi_iot_direct_playback_strategy.dart';
import 'direct_mode_provider.dart';

/// 🎵 直连模式播放音乐辅助方法
Future<void> playMusicInDirectMode({
  required Ref ref,
  required OnlineMusicResult music,
  required Function(String) onError,
  required Function() onSuccess,
}) async {
  try {
    // 1. 获取直连模式状态
    final directState = ref.read(directModeProvider);

    if (directState is! DirectModeAuthenticated) {
      onError('直连模式未登录');
      return;
    }

    if (directState.devices.isEmpty) {
      onError('没有可用设备');
      return;
    }

    // 2. 使用第一个设备
    final device = directState.devices.first;

    // 3. 创建直连播放策略
    final strategy = MiIoTDirectPlaybackStrategy(
      miService: directState.miService,
      deviceId: device.deviceId,
      deviceName: device.name,
    );

    // 4. 播放音乐
    await strategy.playMusic(
      musicName: '${music.title} - ${music.author}',
      url: music.url,
      platform: music.platform,
      songId: music.songId,
    );

    onSuccess();
  } catch (e) {
    onError('播放失败: ${e.toString()}');
  }
}
