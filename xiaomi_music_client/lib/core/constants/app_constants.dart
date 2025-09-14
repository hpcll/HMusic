class AppConstants {
  static const String appName = '小爱音乐盒';
  static const String version = '1.0.0';

  // 网络配置
  static const int connectTimeout = 20;
  static const int receiveTimeout = 25;
  static const int sendTimeout = 20;

  // 默认配置
  static const String defaultServerUrl = 'http://localhost:58090';

  // SharedPreferences keys
  static const String prefsServerUrl = 'server_url';
  static const String prefsUsername = 'username';
  static const String prefsPassword = 'password';
  static const String prefsSelectedDevice = 'selected_device';

  // 功能开关
  static const bool enableSeek = false; // 已禁用：服务端不支持 /seek
}
