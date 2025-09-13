import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/online_music_result.dart';

/// Native (non-JS) search service stubs for QQ / Kuwo / Netease.
/// Replace the TODOs with your real implementations.
class NativeMusicSearchService {
  const NativeMusicSearchService();

  Future<List<OnlineMusicResult>> searchQQ({
    required String query,
    required int page,
  }) async {
    // TODO: integrate real QQ search
    return <OnlineMusicResult>[];
  }

  Future<List<OnlineMusicResult>> searchKuwo({
    required String query,
    required int page,
  }) async {
    // TODO: integrate real Kuwo search
    return <OnlineMusicResult>[];
  }

  Future<List<OnlineMusicResult>> searchNetease({
    required String query,
    required int page,
  }) async {
    // TODO: integrate real Netease search
    return <OnlineMusicResult>[];
  }
}

final nativeMusicSearchServiceProvider = Provider<NativeMusicSearchService>((
  ref,
) {
  return const NativeMusicSearchService();
});
