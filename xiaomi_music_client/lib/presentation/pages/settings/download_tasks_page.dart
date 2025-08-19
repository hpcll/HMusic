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
      if (musicListResp['ret'] == 'OK' && musicListResp['data'] is List) {
        final musicList = (musicListResp['data'] as List).cast<Map<String, dynamic>>();
        
        // 按文件修改时间排序，获取最近的10首歌曲作为"最近下载"
        musicList.sort((a, b) {
          final aTime = a['mtime'] ?? 0;
          final bTime = b['mtime'] ?? 0;
          return bTime.compareTo(aTime);
        });
        
        _recentDownloads = musicList.take(10).toList();
        
        if (mounted) {
          setState(() {
            _status = _recentDownloads.isEmpty 
                ? '暂无音乐文件' 
                : '显示最近添加的音乐文件（可能包含下载的歌曲）';
          });
        }
      } else {
        if (mounted) setState(() => _status = '获取音乐库信息失败');
      }
    } catch (e) {
      if (mounted) setState(() => _status = '获取信息失败: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e}');
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
                  ...(_recentDownloads.map((music) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: onSurface.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: onSurface.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 16,
                          color: onSurface.withOpacity(0.6),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                music['name'] ?? '未知歌曲',
                                style: TextStyle(
                                  color: onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (music['size'] != null)
                                Text(
                                  '${(music['size'] / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.6),
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ))),
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
    ));
  }
}








