import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/mi_iot_service.dart';
import '../../data/services/audio_proxy_server.dart';
import 'audio_proxy_provider.dart';
import 'source_settings_provider.dart'; // 🎯 导入音源设置（用于获取公共代理URL）

/// 播放模式类型
enum PlaybackMode {
  /// xiaomusic服务端模式（需要NAS/服务器）
  xiaomusic,

  /// 小米IoT直连模式（无需服务器）
  miIoTDirect,
}

extension PlaybackModeExtension on PlaybackMode {
  String get displayName {
    switch (this) {
      case PlaybackMode.xiaomusic:
        return 'xiaomusic 模式';
      case PlaybackMode.miIoTDirect:
        return '直连模式';
    }
  }

  String get description {
    switch (this) {
      case PlaybackMode.xiaomusic:
        return '适合有NAS或服务器的用户';
      case PlaybackMode.miIoTDirect:
        return '适合普通手机用户，无需服务器';
    }
  }
}

/// 直连模式配置状态
sealed class DirectModeState {
  const DirectModeState();
}

/// 未登录
class DirectModeInitial extends DirectModeState {
  const DirectModeInitial();
}

/// 登录中
class DirectModeLoading extends DirectModeState {
  const DirectModeLoading();
}

/// 已登录
class DirectModeAuthenticated extends DirectModeState {
  final MiIoTService miService;
  final String account;
  final List<MiDevice> devices;
  final String? selectedDeviceId; // 🎯 当前选中的小爱音箱设备ID（用于获取设备列表）
  final String playbackDeviceType; // 🎵 播放设备类型：'local' 表示本地播放，其他值表示小爱音箱的 deviceId

  const DirectModeAuthenticated({
    required this.miService,
    required this.account,
    required this.devices,
    this.selectedDeviceId,
    this.playbackDeviceType = 'local', // 🎵 默认本地播放
  });

  /// 复制并更新状态
  DirectModeAuthenticated copyWith({
    MiIoTService? miService,
    String? account,
    List<MiDevice>? devices,
    String? selectedDeviceId,
    String? playbackDeviceType,
  }) {
    return DirectModeAuthenticated(
      miService: miService ?? this.miService,
      account: account ?? this.account,
      devices: devices ?? this.devices,
      selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
      playbackDeviceType: playbackDeviceType ?? this.playbackDeviceType,
    );
  }
}

/// 登录失败（🎯 特殊：需要验证码）
class DirectModeNeedsCaptcha extends DirectModeState {
  final String captchaUrl;
  final String account; // 保存账号用于重新登录
  final String password; // 保存密码用于重新登录
  final String message;

  const DirectModeNeedsCaptcha({
    required this.captchaUrl,
    required this.account,
    required this.password,
    this.message = '需要输入验证码',
  });
}

/// 登录失败
class DirectModeError extends DirectModeState {
  final String message;
  const DirectModeError(this.message);
}

/// 直连模式配置管理 Notifier
class DirectModeNotifier extends StateNotifier<DirectModeState> {
  final Ref _ref;

  DirectModeNotifier(this._ref) : super(const DirectModeInitial()) {
    _loadSavedCredentials();
  }

  static const String _keyAccount = 'direct_mode_account';
  static const String _keyPassword = 'direct_mode_password';
  static const String _keySelectedDeviceId = 'direct_mode_selected_device_id'; // 🎯 新增：保存选中的设备ID
  static const String _keyPlaybackDeviceType = 'direct_mode_playback_device_type'; // 🎵 新增：保存播放设备类型

  /// 自动加载保存的凭证
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final account = prefs.getString(_keyAccount);
      final password = prefs.getString(_keyPassword);

      if (account != null && password != null) {
        debugPrint('🔐 [DirectMode] 尝试自动登录: $account');
        await _silentLogin(account: account, password: password);
      }
    } catch (e) {
      debugPrint('❌ [DirectMode] 自动登录失败: $e');
    }
  }

  /// 静默登录（不显示 Loading 状态）
  Future<void> _silentLogin({
    required String account,
    required String password,
  }) async {
    try {
      final miService = MiIoTService();

      // 登录小米账号
      final success = await miService.login(account, password);

      if (!success) {
        debugPrint('❌ [DirectMode] 静默登录失败');
        state = const DirectModeInitial();
        return;
      }

      // 获取设备列表
      final devices = await miService.getDevices();

      if (devices.isEmpty) {
        debugPrint('⚠️ [DirectMode] 未找到设备');
      }

      // 🎯 加载保存的选中设备ID和播放设备类型
      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString(_keySelectedDeviceId);
      final savedPlaybackDeviceType = prefs.getString(_keyPlaybackDeviceType) ?? 'local'; // 默认本地播放

      state = DirectModeAuthenticated(
        miService: miService,
        account: account,
        devices: devices,
        selectedDeviceId: savedDeviceId, // 恢复选中的设备
        playbackDeviceType: savedPlaybackDeviceType, // 🎵 恢复播放设备类型
      );

      // 🎯 自动设置代理服务器
      await _setupProxyServer(miService);

      debugPrint('✅ [DirectMode] 自动登录成功，找到 ${devices.length} 个设备');
      if (savedDeviceId != null) {
        debugPrint('✅ [DirectMode] 已恢复选中的设备: $savedDeviceId');
      }
      debugPrint('✅ [DirectMode] 已恢复播放设备类型: $savedPlaybackDeviceType');
    } catch (e) {
      debugPrint('❌ [DirectMode] 静默登录异常: $e');
      state = const DirectModeInitial();
    }
  }

  /// 登录小米账号
  Future<void> login({
    required String account,
    required String password,
    String? captchaCode, // 🎯 新增：验证码参数
    bool saveCredentials = true,
  }) async {
    state = const DirectModeLoading();

    try {
      final miService = MiIoTService();

      // 登录小米账号（🎯 传入验证码）
      final success = await miService.login(account, password, captchaCode: captchaCode);

      if (!success) {
        // 🎯 检查是否需要验证码
        final lastResponse = miService.lastLoginResponse;
        if (lastResponse != null && lastResponse['code'] == 70016) {
          final captchaUrl = lastResponse['captchaUrl'] as String?;
          if (captchaUrl != null && captchaUrl.isNotEmpty) {
            debugPrint('⚠️ [DirectMode] 需要验证码登录');
            state = DirectModeNeedsCaptcha(
              captchaUrl: captchaUrl,
              account: account,
              password: password,
              message: '需要输入验证码',
            );
            return;
          }
        }

        // 其他登录失败情况
        state = const DirectModeError(
          '登录失败\n\n'
          '可能原因：\n'
          '1. 账号密码错误\n'
          '2. 验证码错误\n'
          '3. 登录频繁，请稍后再试'
        );
        return;
      }

      // 获取设备列表
      final devices = await miService.getDevices();

      if (devices.isEmpty) {
        state = const DirectModeError('登录成功，但未找到小爱音箱设备');
        return;
      }

      // 保存凭证
      if (saveCredentials) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyAccount, account);
        await prefs.setString(_keyPassword, password);
        debugPrint('💾 [DirectMode] 凭证已保存');
      }

      state = DirectModeAuthenticated(
        miService: miService,
        account: account,
        devices: devices,
      );

      // 🎯 自动设置代理服务器
      await _setupProxyServer(miService);

      debugPrint('✅ [DirectMode] 登录成功，找到 ${devices.length} 个设备');
    } catch (e) {
      debugPrint('❌ [DirectMode] 登录异常: $e');
      state = DirectModeError('登录失败: $e');
    }
  }

  /// 刷新设备列表
  Future<void> refreshDevices() async {
    final currentState = state;
    if (currentState is! DirectModeAuthenticated) {
      debugPrint('⚠️ [DirectMode] 未登录，无法刷新设备');
      return;
    }

    try {
      final devices = await currentState.miService.getDevices();

      state = currentState.copyWith(devices: devices);

      debugPrint('✅ [DirectMode] 设备列表已刷新，找到 ${devices.length} 个设备');
    } catch (e) {
      debugPrint('❌ [DirectMode] 刷新设备失败: $e');
    }
  }

  /// 选择设备
  Future<void> selectDevice(String deviceId) async {
    final currentState = state;
    if (currentState is! DirectModeAuthenticated) {
      debugPrint('⚠️ [DirectMode] 未登录，无法选择设备');
      return;
    }

    // 检查设备是否存在
    final device = currentState.devices.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );

    state = currentState.copyWith(selectedDeviceId: deviceId);

    // 🎯 保存选中的设备ID
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedDeviceId, deviceId);

    debugPrint('✅ [DirectMode] 已选择设备: ${device.name} ($deviceId)');
  }

  /// 🎵 选择播放设备类型（本地播放 or 小爱音箱）
  /// [deviceType] 可以是 'local' 表示本地播放，或者小爱音箱的 deviceId
  Future<void> selectPlaybackDevice(String deviceType) async {
    final currentState = state;
    if (currentState is! DirectModeAuthenticated) {
      debugPrint('⚠️ [DirectMode] 未登录，无法选择播放设备');
      return;
    }

    // 如果选择的是小爱音箱，验证设备是否存在
    if (deviceType != 'local') {
      final exists = currentState.devices.any((d) => d.deviceId == deviceType);
      if (!exists) {
        debugPrint('⚠️ [DirectMode] 设备不存在: $deviceType');
        return;
      }
    }

    state = currentState.copyWith(playbackDeviceType: deviceType);

    // 🎯 保存播放设备类型
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlaybackDeviceType, deviceType);

    final deviceName = deviceType == 'local'
        ? '本地播放'
        : currentState.devices.firstWhere((d) => d.deviceId == deviceType).name;
    debugPrint('✅ [DirectMode] 已选择播放设备: $deviceName ($deviceType)');
  }

  /// 登出
  Future<void> logout() async {
    final currentState = state;
    if (currentState is DirectModeAuthenticated) {
      currentState.miService.logout();
    }

    // 清除保存的凭证
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccount);
    await prefs.remove(_keyPassword);

    state = const DirectModeInitial();
    debugPrint('👋 [DirectMode] 已登出');
  }

  /// 🎯 设置代理服务器（用于音频流转发）
  /// 必须在登录成功后调用，将代理服务器传递给 MiIoTService
  void setProxyServer(AudioProxyServer? proxyServer) {
    final currentState = state;
    if (currentState is DirectModeAuthenticated) {
      currentState.miService.setProxyServer(proxyServer);
      debugPrint('✅ [DirectMode] 已将代理服务器设置到 MiIoTService');
    } else {
      debugPrint('⚠️ [DirectMode] 未登录，无法设置代理服务器');
    }
  }

  /// 🎯 自动设置代理服务器（内部方法）
  Future<void> _setupProxyServer(MiIoTService miService) async {
    try {
      // 🎯 等待 SourceSettings 加载完成（最多等待 3 秒）
      final notifier = _ref.read(sourceSettingsProvider.notifier);
      int waitCount = 0;
      while (!notifier.isLoaded && waitCount < 30) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
      }

      // 🎯 优先使用公共代理（Cloudflare Workers）
      final sourceSettings = _ref.read(sourceSettingsProvider);
      debugPrint('🔧 [DirectMode] 代理设置检查: useAudioProxy=${sourceSettings.useAudioProxy}, url=${sourceSettings.audioProxyUrl}');

      if (sourceSettings.useAudioProxy && sourceSettings.audioProxyUrl.isNotEmpty) {
        miService.setPublicProxyUrl(sourceSettings.audioProxyUrl);
        debugPrint('✅ [DirectMode] 已设置公共音频代理: ${sourceSettings.audioProxyUrl}');
      } else {
        miService.setPublicProxyUrl(null); // 清除公共代理
        debugPrint('⚠️ [DirectMode] 公共音频代理未启用 (useAudioProxy=${sourceSettings.useAudioProxy}, url=${sourceSettings.audioProxyUrl})');
      }

      // 本地代理（作为备选，需要同一局域网）
      final proxyServer = _ref.read(audioProxyServerProvider);
      if (proxyServer != null && proxyServer.isRunning) {
        miService.setProxyServer(proxyServer);
        debugPrint('✅ [DirectMode] 已设置本地代理服务器: ${proxyServer.serverUrl}');
      } else {
        debugPrint('⚠️ [DirectMode] 本地代理服务器未运行');
      }
    } catch (e) {
      debugPrint('❌ [DirectMode] 设置代理服务器失败: $e');
    }
  }

  /// 🎯 刷新代理设置（供外部调用，如设置更新后）
  Future<void> refreshProxySettings() async {
    final currentState = state;
    if (currentState is DirectModeAuthenticated) {
      await _setupProxyServer(currentState.miService);
      debugPrint('✅ [DirectMode] 代理设置已刷新');
    } else {
      debugPrint('⚠️ [DirectMode] 未登录，无法刷新代理设置');
    }
  }
}

/// 直连模式配置Provider
final directModeProvider =
    StateNotifierProvider<DirectModeNotifier, DirectModeState>((ref) {
  return DirectModeNotifier(ref);
});

/// 播放模式选择Provider
/// 保存用户选择的播放模式（xiaomusic / 直连）
class PlaybackModeNotifier extends StateNotifier<PlaybackMode> {
  PlaybackModeNotifier() : super(PlaybackMode.xiaomusic) {
    _loadSavedMode();
  }

  static const String _keyMode = 'playback_mode';

  Future<void> _loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_keyMode);

      if (savedMode != null) {
        if (savedMode == PlaybackMode.miIoTDirect.name) {
          state = PlaybackMode.miIoTDirect;
        } else {
          state = PlaybackMode.xiaomusic;
        }
        debugPrint('📱 [PlaybackMode] 加载保存的模式: ${state.displayName}');
      }
    } catch (e) {
      debugPrint('❌ [PlaybackMode] 加载模式失败: $e');
    }
  }

  Future<void> setMode(PlaybackMode mode) async {
    state = mode;

    // 保存选择
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);

    debugPrint('✅ [PlaybackMode] 模式已切换: ${mode.displayName}');
  }

  /// 清除模式选择（用于切换模式功能）
  Future<void> clearMode() async {
    // 清除保存的模式选择
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyMode);

    // 重置为默认模式（但不保存，让用户重新选择）
    state = PlaybackMode.xiaomusic;

    debugPrint('🔄 [PlaybackMode] 模式选择已清除，等待用户重新选择');
  }
}

final playbackModeProvider =
    StateNotifierProvider<PlaybackModeNotifier, PlaybackMode>((ref) {
  return PlaybackModeNotifier();
});
