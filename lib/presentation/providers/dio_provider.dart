import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../data/services/music_api_service.dart';
import 'auth_provider.dart';

/// 基于 `authProvider` 的鉴权信息暴露 `DioClient` 实例，供其它 Provider 组合使用
final dioClientProvider = Provider<DioClient?>((ref) {
  final authState = ref.watch(authProvider);
  if (authState is AuthAuthenticated) return authState.client;
  return null;
});

/// 基于 `dioClientProvider` 构建 `MusicApiService`
final apiServiceProvider = Provider<MusicApiService?>((ref) {
  final dio = ref.watch(dioClientProvider);
  if (dio == null) return null;
  return MusicApiService(dio);
});
