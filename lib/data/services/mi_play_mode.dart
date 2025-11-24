/// 播放模式工具类
/// 基于xiaomusic项目的播放模式逻辑
class MiPlayMode {
  /// 播放模式常量
  static const String PLAY_TYPE_ONE = 'ONE';        // 单曲循环
  static const String PLAY_TYPE_ALL = 'ALL';        // 全部循环
  static const String PLAY_TYPE_RND = 'RND';        // 随机播放
  static const String PLAY_TYPE_SIN = 'SIN';        // 单曲播放
  static const String PLAY_TYPE_SEQ = 'SEQ';        // 顺序播放

  /// 播放模式描述
  static const Map<String, String> MODE_DESCRIPTIONS = {
    PLAY_TYPE_ONE: '单曲循环',
    PLAY_TYPE_ALL: '全部循环',
    PLAY_TYPE_RND: '随机播放',
    PLAY_TYPE_SIN: '单曲播放',
    PLAY_TYPE_SEQ: '顺序播放',
  };

  /// 获取播放模式描述
  static String getModeDescription(String mode) {
    return MODE_DESCRIPTIONS[mode] ?? '未知模式';
  }

  /// 验证播放模式是否有效
  static bool isValidMode(String mode) {
    return MODE_DESCRIPTIONS.containsKey(mode);
  }

  /// 获取所有可用的播放模式
  static List<String> getAvailableModes() {
    return MODE_DESCRIPTIONS.keys.toList();
  }

  /// 检查播放模式是否支持循环
  static bool supportsLoop(String mode) {
    return mode == PLAY_TYPE_ONE || mode == PLAY_TYPE_ALL;
  }

  /// 检查播放模式是否支持随机
  static bool supportsRandom(String mode) {
    return mode == PLAY_TYPE_RND;
  }

  /// 检查播放模式是否支持顺序
  static bool supportsSequential(String mode) {
    return mode == PLAY_TYPE_SEQ || mode == PLAY_TYPE_ALL;
  }
}