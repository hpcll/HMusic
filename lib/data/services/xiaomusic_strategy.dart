import 'playback_strategy_interface.dart';
import 'music_api_service.dart';
import '../models/device.dart';

/// xiaomusic服务端策略
/// 通过xiaomusic服务端控制小爱音箱（保留原有功能）
class XiaoMusicStrategy implements PlaybackStrategy {
  final MusicApiService _apiService;
  List<Device> _cachedDevices = [];

  XiaoMusicStrategy(this._apiService);

  @override
  PlaybackStrategyType get type => PlaybackStrategyType.xiaomusic;

  @override
  bool get isConnected => true; // 假设已通过DioClient连接

  @override
  Future<bool> connect({
    String? serverUrl,
    String? username,
    String? password,
  }) async {
    // xiaomusic模式通过DioClient已经处理了连接
    // 这里只需要验证连接是否有效
    try {
      await _apiService.getVersion();
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 连接验证失败: $e');
      return false;
    }
  }

  @override
  Future<List<PlaybackDevice>> getDevices() async {
    try {
      final response = await _apiService.getDeviceList();
      final devicesData = response['data'] as Map<String, dynamic>? ?? {};

      _cachedDevices = devicesData.entries.map((entry) {
        final deviceData = entry.value as Map<String, dynamic>;
        return Device.fromJson(deviceData);
      }).toList();

      return _cachedDevices.map((device) {
        return PlaybackDevice(
          deviceId: device.deviceId,
          did: device.did,
          name: device.name,
          hardware: device.hardware,
          strategyType: PlaybackStrategyType.xiaomusic,
        );
      }).toList();
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 获取设备列表失败: $e');
      return [];
    }
  }

  @override
  Future<bool> playMusic({
    required String deviceId,
    required String musicUrl,
    String? musicName,
  }) async {
    try {
      // 使用xiaomusic的播放接口
      if (musicName != null && musicName.isNotEmpty) {
        await _apiService.playMusic(
          did: deviceId,
          musicName: musicName,
        );
      } else {
        // 如果没有歌曲名，直接播放URL
        await _apiService.playUrl(did: deviceId, url: musicUrl);
      }
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 播放失败: $e');
      return false;
    }
  }

  @override
  Future<bool> pause(String deviceId) async {
    try {
      await _apiService.pauseMusic(did: deviceId);
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 暂停失败: $e');
      return false;
    }
  }

  @override
  Future<bool> resume(String deviceId) async {
    try {
      await _apiService.resumeMusic(did: deviceId);
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 继续播放失败: $e');
      return false;
    }
  }

  @override
  Future<bool> stop(String deviceId) async {
    try {
      await _apiService.shutdown(did: deviceId);
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 停止失败: $e');
      return false;
    }
  }

  @override
  Future<bool> previous(String deviceId) async {
    try {
      await _apiService.executeCommand(did: deviceId, command: '上一首');
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 上一曲失败: $e');
      return false;
    }
  }

  @override
  Future<bool> next(String deviceId) async {
    try {
      await _apiService.executeCommand(did: deviceId, command: '下一首');
      return true;
    } catch (e) {
      print('❌ [XiaoMusicStrategy] 下一曲失败: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    // xiaomusic模式不需要特别的断开操作
    _cachedDevices.clear();
  }
}
