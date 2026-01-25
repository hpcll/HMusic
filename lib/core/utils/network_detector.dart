import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// 网络环境检测工具
/// 用于智能判断当前网络类型，优化代理选择策略
class NetworkDetector {
  static final NetworkDetector _instance = NetworkDetector._internal();
  factory NetworkDetector() => _instance;
  NetworkDetector._internal();

  final Connectivity _connectivity = Connectivity();

  /// 检查当前是否为 WiFi 环境
  /// 返回 true 表示 WiFi，false 表示移动网络或其他
  Future<bool> isWiFiConnected() async {
    try {
      final List<ConnectivityResult> connectivityResult =
          await _connectivity.checkConnectivity();

      // 检查是否包含 WiFi 连接
      final isWiFi = connectivityResult.contains(ConnectivityResult.wifi);

      if (isWiFi) {
        debugPrint('📶 [NetworkDetector] 当前网络: WiFi');
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        debugPrint('📱 [NetworkDetector] 当前网络: 移动网络');
      } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        debugPrint('🔌 [NetworkDetector] 当前网络: 以太网');
      } else {
        debugPrint('❌ [NetworkDetector] 当前网络: 未连接或其他');
      }

      return isWiFi;
    } catch (e) {
      debugPrint('⚠️ [NetworkDetector] 检测网络类型失败: $e');
      // 检测失败时，保守策略：假设不是 WiFi
      return false;
    }
  }

  /// 获取当前网络类型描述
  Future<String> getNetworkTypeDescription() async {
    try {
      final List<ConnectivityResult> connectivityResult =
          await _connectivity.checkConnectivity();

      if (connectivityResult.contains(ConnectivityResult.wifi)) {
        return 'WiFi';
      } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
        return '移动网络';
      } else if (connectivityResult.contains(ConnectivityResult.ethernet)) {
        return '以太网';
      } else if (connectivityResult.contains(ConnectivityResult.none)) {
        return '未连接';
      } else {
        return '其他';
      }
    } catch (e) {
      debugPrint('⚠️ [NetworkDetector] 获取网络类型失败: $e');
      return '未知';
    }
  }

  /// 监听网络变化
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}
