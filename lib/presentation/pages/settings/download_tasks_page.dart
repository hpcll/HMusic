import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/dio_provider.dart';

class DownloadTasksPage extends ConsumerStatefulWidget {
  const DownloadTasksPage({super.key});

  @override
  ConsumerState<DownloadTasksPage> createState() => _DownloadTasksPageState();
}

class _DownloadTasksPageState extends ConsumerState<DownloadTasksPage> {
  String _status = '暂无下载任务';
  bool _loading = false;
  List<Map<String, dynamic>> _recentDownloads = [];

  Future<void> _load() async {
    final api = ref.read(apiServiceProvider);
    if (api == null) {
      if (mounted) {
        setState(() {
          _status = '未连接到服务器';
          _loading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _loading = true);
    try {
      // 获取音乐库信息，从中推断最近的下载
      final musicListResp = await api.getMusicList();

      // 从返回的数据中提取下载列表和最近新增列表
      List<String> downloadList = [];
      List<String> recentList = [];

      if (musicListResp['下载'] is List) {
        downloadList = (musicListResp['下载'] as List).cast<String>();
      }
      if (musicListResp['最近新增'] is List) {
        recentList = (musicListResp['最近新增'] as List).cast<String>();
      }

      // 将字符串列表转换为显示格式，优先显示最近新增的
      final displayList = recentList.isNotEmpty ? recentList : downloadList;
      _recentDownloads =
          displayList
              .take(10)
              .map(
                (name) => {'name': name, 'isRecent': recentList.contains(name)},
              )
              .toList();

      if (mounted) {
        setState(() {
          if (downloadList.isEmpty && recentList.isEmpty) {
            _status = '暂无下载的音乐文件';
          } else {
            final totalCount = downloadList.length;
            final recentCount = recentList.length;
            _status =
                '共有 $totalCount 首下载的歌曲' +
                (recentCount > 0 ? '，最近新增 $recentCount 首' : '');
          }
        });
      }
    } catch (e) {
      if (mounted)
        setState(
          () =>
              _status =
                  '获取信息失败: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e}',
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(title: const Text('下载任务')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: onSurface.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '下载任务',
                        style: TextStyle(
                          color: onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: _load,
                          tooltip: '刷新',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                  if (_recentDownloads.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '最近添加的音乐文件',
                      style: TextStyle(
                        color: onSurface,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_recentDownloads.map(
                      (music) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: onSurface.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: onSurface.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              music['isRecent'] == true
                                  ? Icons.fiber_new
                                  : Icons.music_note,
                              size: 16,
                              color:
                                  music['isRecent'] == true
                                      ? Colors.green.withOpacity(0.8)
                                      : onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                music['name'] ?? '未知歌曲',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight:
                                      music['isRecent'] == true
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (music['isRecent'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '新',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )),
                  ] else
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: onSurface.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: onSurface.withOpacity(0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '如何创建下载任务？',
                            style: TextStyle(
                              color: onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• 在搜索结果里选择"下载到服务器"\n'
                            '• 在设置菜单选择"从链接下载"\n'
                            '• 下载完成后会出现在音乐库中',
                            style: TextStyle(
                              color: onSurface.withOpacity(0.7),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
