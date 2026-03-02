/// 小米设备硬件检测工具类
/// 基于 xiaomusic NEED_USE_PLAY_MUSIC_API + miservice _USE_PLAY_MUSIC_API 合并
class MiHardwareDetector {
  /// 必须使用 player_play_music API 的设备硬件列表
  /// 合并来源：
  ///   xiaomusic const.py NEED_USE_PLAY_MUSIC_API
  ///   miservice minaservice.py _USE_PLAY_MUSIC_API
  /// 这些设备使用 player_play_url 会无效或不稳定
  static const List<String> NEED_USE_PLAY_MUSIC_API = [
    // --- 来自 xiaomusic NEED_USE_PLAY_MUSIC_API ---
    'X08C',   // 小爱音箱 Play 增强版 (触屏)
    'X08E',   // 小爱音箱 Play (触屏)
    'X8F',    // 小爱音箱 Pro (触屏)
    'X4B',    // 小爱音箱
    'LX05',   // 小爱音箱 Play (2019款)
    'OH2',    // XIAOMI 智能音箱
    'OH2P',   // XIAOMI 智能音箱 Pro
    'X6A',    // 小爱音箱 Art 电池版
    // --- 来自 miservice _USE_PLAY_MUSIC_API (补充) ---
    'LX04',   // 小爱音箱 (触屏)
    'L05B',   // 小爱音箱 Play
    'L05C',   // 小米小爱音箱 Play 增强版
    'L06',    // 小爱音箱
    'L06A',   // 小爱音箱
    'X08A',   // 小爱音箱 (触屏)
    'X10A',   // 小爱音箱 (触屏)
  ];

  /// 暂停后必须重新发送完整播放命令（不支持 player_play_operation('play') 恢复）的设备列表
  ///
  /// 背景：
  ///   大多数设备暂停后可以用 player_play_operation('play') 恢复播放。
  ///   但 OH2P 等设备的 player_play_operation('play') 静默失效（API 返回 200 但无声音），
  ///   必须重新发送完整的 player_play_music 命令才能让音箱重新发声。
  ///
  /// 注意：
  ///   此列表独立于 NEED_USE_PLAY_MUSIC_API！
  ///   NEED_USE_PLAY_MUSIC_API 表示"播放新歌时需要用 player_play_music"，
  ///   而本列表表示"连 resume 也需要重新播放"，范围更窄。
  ///   例如 L05B 在 NEED_USE_PLAY_MUSIC_API 中但不在此列表，它支持正常 resume。
  static const List<String> _NEED_FULL_REPLAY_ON_RESUME = [
    'OH2P',   // XIAOMI 智能音箱 Pro：已确认 player_play_operation('play') 静默失效
    // 'OH2', // XIAOMI 智能音箱：未验证，暂不列入，如发现同样问题再添加
  ];

  /// 不支持 player_play_music 的 startOffset 参数的设备列表
  ///
  /// 背景：
  ///   player_play_music 支持 startOffset 参数（毫秒），理论上可从指定位置开始播放。
  ///   但 OH2P 等设备会忽略该参数，始终从 0 秒开始播放，导致 APP 端计时器与实际进度脱节。
  ///
  /// 影响：
  ///   resume 时不传 startOffset，APP 端计时器也从 0 开始，保持一致。
  static const List<String> _NO_START_OFFSET_SUPPORT = [
    'OH2P',   // 已确认 startOffset 被忽略，实际从头播放
    // 'OH2', // 未验证，暂不列入
  ];

  /// 不支持 player_set_positon (seek) 的设备列表
  ///
  /// 背景：
  ///   OH2P 的 player_get_play_status 始终返回 position=null，
  ///   说明固件未实现精确进度跟踪，seek 命令极大概率同样无效。
  ///   用户反馈拖动进度条无任何反应，与此一致。
  static const List<String> _NO_SEEK_SUPPORT = [
    'OH2P',   // 已通过用户反馈确认 seek 无效；position 永远 null 佐证固件无此能力
    // 'OH2', // 未验证，暂不列入
  ];

  /// 检查设备硬件是否需要使用 player_play_music API
  static bool needsPlayMusicApi(String hardware) {
    if (hardware.isEmpty) return false;

    final upperHardware = hardware.toUpperCase();
    return NEED_USE_PLAY_MUSIC_API.any((need) => upperHardware.contains(need));
  }

  /// 检查设备暂停后是否需要重新发送完整播放命令才能恢复播放
  ///
  /// 返回 true 的设备：player_play_operation('play') 静默失效，
  /// 需要重新调用 player_play_music 才能让音箱发声。
  ///
  /// 注意：与 needsPlayMusicApi() 是独立的概念！
  static bool needsFullReplayOnResume(String hardware) {
    if (hardware.isEmpty) return false;

    final upperHardware = hardware.toUpperCase();
    return _NEED_FULL_REPLAY_ON_RESUME
        .any((need) => upperHardware.contains(need));
  }

  /// 检查设备是否支持 player_play_music 的 startOffset 参数
  ///
  /// 返回 false 的设备：startOffset 被固件忽略，始终从 0 秒开始播放。
  /// 这类设备 resume 时不应传入 startOffset，APP 端计时器也应从 0 开始，保持一致。
  static bool supportsStartOffset(String hardware) {
    if (hardware.isEmpty) return true; // 未知设备乐观假设支持

    final upperHardware = hardware.toUpperCase();
    return !_NO_START_OFFSET_SUPPORT.any((h) => upperHardware.contains(h));
  }

  /// 检查设备是否支持 seek (player_set_positon)
  ///
  /// 返回 false 的设备：进度跳转无效，UI 应禁用进度条拖动。
  static bool supportsSeek(String hardware) {
    if (hardware.isEmpty) return true; // 未知设备乐观假设支持

    final upperHardware = hardware.toUpperCase();
    return !_NO_SEEK_SUPPORT.any((h) => upperHardware.contains(h));
  }

  /// 获取设备的推荐播放方式
  static String getRecommendedPlayMethod(String hardware) {
    if (needsPlayMusicApi(hardware)) {
      return 'player_play_music';
    }
    return 'player_play_url';
  }

  /// 获取设备硬件类型描述
  static String getHardwareDescription(String hardware) {
    if (hardware.isEmpty) return '未知设备';

    final upperHardware = hardware.toUpperCase();

    if (upperHardware.contains('X08C')) return '小爱音箱 Play 增强版';
    if (upperHardware.contains('X08E')) return '小爱音箱 Play';
    if (upperHardware.contains('X8F')) return '小爱音箱 Pro';
    if (upperHardware.contains('X4B')) return '小爱音箱';
    if (upperHardware.contains('LX05')) return '小爱音箱 Play (LX05)';
    if (upperHardware.contains('OH2')) return '小爱音箱 HD';
    if (upperHardware.contains('OH2P')) return '小爱音箱 HD Plus';
    if (upperHardware.contains('X6A')) return '小爱音箱 Art 电池版';

    return '小爱音箱';
  }

  /// 检查设备是否支持高级功能
  static bool supportsAdvancedFeatures(String hardware) {
    if (hardware.isEmpty) return false;

    final upperHardware = hardware.toUpperCase();
    // HD系列和Pro系列支持更多功能
    return upperHardware.contains('PRO') ||
           upperHardware.contains('HD') ||
           upperHardware.contains('ART');
  }
}