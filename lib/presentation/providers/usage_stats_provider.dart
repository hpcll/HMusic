import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使用统计状态
class UsageStats {
  final int totalPlays; // 总播放次数
  final int scrapedLyrics; // 刮削的歌词数
  final DateTime firstUseDate; // 首次使用日期
  final DateTime? lastSponsorPromptDate; // 上次显示赞赏提示的日期
  final bool hasShownPlaysMilestone; // 是否已显示播放里程碑
  final bool hasShownLyricsMilestone; // 是否已显示歌词里程碑
  final bool hasShownDaysMilestone; // 是否已显示使用天数里程碑
  final bool neverShowSponsorPrompt; // 用户选择不再提醒

  const UsageStats({
    this.totalPlays = 0,
    this.scrapedLyrics = 0,
    required this.firstUseDate,
    this.lastSponsorPromptDate,
    this.hasShownPlaysMilestone = false,
    this.hasShownLyricsMilestone = false,
    this.hasShownDaysMilestone = false,
    this.neverShowSponsorPrompt = false,
  });

  UsageStats copyWith({
    int? totalPlays,
    int? scrapedLyrics,
    DateTime? firstUseDate,
    DateTime? lastSponsorPromptDate,
    bool? hasShownPlaysMilestone,
    bool? hasShownLyricsMilestone,
    bool? hasShownDaysMilestone,
    bool? neverShowSponsorPrompt,
  }) {
    return UsageStats(
      totalPlays: totalPlays ?? this.totalPlays,
      scrapedLyrics: scrapedLyrics ?? this.scrapedLyrics,
      firstUseDate: firstUseDate ?? this.firstUseDate,
      lastSponsorPromptDate: lastSponsorPromptDate ?? this.lastSponsorPromptDate,
      hasShownPlaysMilestone: hasShownPlaysMilestone ?? this.hasShownPlaysMilestone,
      hasShownLyricsMilestone: hasShownLyricsMilestone ?? this.hasShownLyricsMilestone,
      hasShownDaysMilestone: hasShownDaysMilestone ?? this.hasShownDaysMilestone,
      neverShowSponsorPrompt: neverShowSponsorPrompt ?? this.neverShowSponsorPrompt,
    );
  }

  /// 获取使用天数
  int get usageDays {
    final now = DateTime.now();
    return now.difference(firstUseDate).inDays;
  }

  /// 是否应该显示30天间隔提醒
  bool get shouldShowIntervalPrompt {
    if (neverShowSponsorPrompt) return false;
    if (lastSponsorPromptDate == null) return true;

    final now = DateTime.now();
    final daysSinceLastPrompt = now.difference(lastSponsorPromptDate!).inDays;
    return daysSinceLastPrompt >= 30;
  }
}

/// 使用统计Provider
class UsageStatsNotifier extends StateNotifier<UsageStats> {
  final SharedPreferences _prefs;

  UsageStatsNotifier(this._prefs) : super(_loadFromPrefs(_prefs));

  static UsageStats _loadFromPrefs(SharedPreferences prefs) {
    final firstUseDateMs = prefs.getInt('first_use_date') ?? DateTime.now().millisecondsSinceEpoch;
    final lastPromptDateMs = prefs.getInt('last_sponsor_prompt_date');

    return UsageStats(
      totalPlays: prefs.getInt('total_plays') ?? 0,
      scrapedLyrics: prefs.getInt('scraped_lyrics') ?? 0,
      firstUseDate: DateTime.fromMillisecondsSinceEpoch(firstUseDateMs),
      lastSponsorPromptDate: lastPromptDateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastPromptDateMs)
          : null,
      hasShownPlaysMilestone: prefs.getBool('has_shown_plays_milestone') ?? false,
      hasShownLyricsMilestone: prefs.getBool('has_shown_lyrics_milestone') ?? false,
      hasShownDaysMilestone: prefs.getBool('has_shown_days_milestone') ?? false,
      neverShowSponsorPrompt: prefs.getBool('never_show_sponsor_prompt') ?? false,
    );
  }

  /// 增加播放次数
  Future<void> incrementPlays() async {
    state = state.copyWith(totalPlays: state.totalPlays + 1);
    await _prefs.setInt('total_plays', state.totalPlays);
  }

  /// 增加刮削歌词次数
  Future<void> incrementScrapedLyrics() async {
    state = state.copyWith(scrapedLyrics: state.scrapedLyrics + 1);
    await _prefs.setInt('scraped_lyrics', state.scrapedLyrics);
  }

  /// 标记播放里程碑已显示
  Future<void> markPlaysMilestoneShown() async {
    state = state.copyWith(hasShownPlaysMilestone: true);
    await _prefs.setBool('has_shown_plays_milestone', true);
  }

  /// 标记歌词里程碑已显示
  Future<void> markLyricsMilestoneShown() async {
    state = state.copyWith(hasShownLyricsMilestone: true);
    await _prefs.setBool('has_shown_lyrics_milestone', true);
  }

  /// 标记使用天数里程碑已显示
  Future<void> markDaysMilestoneShown() async {
    state = state.copyWith(hasShownDaysMilestone: true);
    await _prefs.setBool('has_shown_days_milestone', true);
  }

  /// 更新上次显示赞赏提示的时间
  Future<void> updateLastPromptDate() async {
    final now = DateTime.now();
    state = state.copyWith(lastSponsorPromptDate: now);
    await _prefs.setInt('last_sponsor_prompt_date', now.millisecondsSinceEpoch);
  }

  /// 设置不再提醒
  Future<void> setNeverShowPrompt(bool value) async {
    state = state.copyWith(neverShowSponsorPrompt: value);
    await _prefs.setBool('never_show_sponsor_prompt', value);
  }

  /// 检查是否达到播放里程碑 (50首)
  bool checkPlaysMilestone() {
    return !state.hasShownPlaysMilestone && state.totalPlays >= 50;
  }

  /// 检查是否达到歌词里程碑 (20条)
  bool checkLyricsMilestone() {
    return !state.hasShownLyricsMilestone && state.scrapedLyrics >= 20;
  }

  /// 检查是否达到使用天数里程碑 (7天)
  bool checkDaysMilestone() {
    return !state.hasShownDaysMilestone && state.usageDays >= 7;
  }
}

final usageStatsProvider = StateNotifierProvider<UsageStatsNotifier, UsageStats>((ref) {
  throw UnimplementedError('usageStatsProvider must be overridden');
});
