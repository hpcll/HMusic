class AppConstants {
  static const String appName = 'HMusic';
  // 版本号从 package_info_plus 动态获取，不在此硬编码
  // 使用时通过 PackageInfo.fromPlatform() 获取实际版本

  // 网络配置
  static const int connectTimeout = 20;
  static const int receiveTimeout = 25;
  static const int sendTimeout = 20;

  // 默认配置
  static const String defaultServerUrl = 'http://192.168.31.2:8090';

  // SharedPreferences keys
  static const String prefsServerUrl = 'server_url';
  static const String prefsUsername = 'username';
  static const String prefsPassword = 'password';
  static const String prefsSelectedDevice = 'selected_device';

  // 功能开关
  static const bool enableSeek = true; // ✅ 已启用：本地播放支持 seek
}
