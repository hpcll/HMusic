import 'dart:async';

/// 🔄 歌单刷新控制器
///
/// 用于在添加歌曲后通知歌单页面刷新数据
/// 使用 Stream 广播模式，多个页面可以同时监听
class PlaylistRefreshController {
  // 私有构造函数，防止实例化
  PlaylistRefreshController._();

  // 广播控制器，允许多个监听者
  static final _controller = StreamController<void>.broadcast();

  /// 获取刷新事件流
  static Stream<void> get stream => _controller.stream;

  /// 触发刷新事件
  /// 调用此方法后，所有监听者都会收到通知
  static void refresh() {
    _controller.add(null);
  }

  /// 销毁控制器（通常不需要调用，除非 app 退出）
  static void dispose() {
    _controller.close();
  }
}
