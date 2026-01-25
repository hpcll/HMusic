import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MainPage 的 Tab 索引 Provider
///
/// Tab 索引定义：
/// - 0: 控制面板 (ControlPanelPage)
/// - 1: 音乐搜索 (MusicSearchPage)
/// - 2: 歌单列表 (PlaylistPage)
/// - 3: 音乐库 (MusicLibraryPage)
final mainTabIndexProvider = StateProvider<int>((ref) => 0);

/// Tab 索引常量
class MainTabIndex {
  static const int controlPanel = 0;
  static const int musicSearch = 1;
  static const int playlist = 2;
  static const int musicLibrary = 3;
}
