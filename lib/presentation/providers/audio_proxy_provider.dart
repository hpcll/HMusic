import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/audio_proxy_server.dart';

/// 🎯 全局代理服务器Provider
/// 用于在应用中访问代理服务器实例
final audioProxyServerProvider = Provider<AudioProxyServer?>((ref) {
  // 这个Provider会被main.dart中的overrideWithValue覆盖
  return null;
});
