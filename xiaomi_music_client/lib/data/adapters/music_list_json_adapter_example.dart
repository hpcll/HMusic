/// 音乐列表JSON适配器使用示例
/// 
/// 这个文件展示了如何使用 MusicListJsonAdapter 来处理不同JS脚本返回的各种格式

import 'dart:convert';
import 'music_list_json_adapter.dart';
import '../models/online_music_result.dart';

class MusicListJsonAdapterExample {
  /// 示例1：使用OnlineMusicResult对象
  static void exampleWithOnlineMusicResult() {
    final results = [
      OnlineMusicResult(
        songId: '123',
        title: '爱你没差',
        author: '周杰伦',
        url: 'https://example.com/music.mp3',
        platform: 'qq',
        duration: 240,
        album: '十二新作',
        extra: {'sourceApi': 'js_builtin'},
      ),
    ];

    final jsonString = MusicListJsonAdapter.convertToMusicListJson(
      results: results,
      playlistName: "在线播放",
      defaultHeaders: {'X-Request-Key': 'share-v2'},
    );

    print('OnlineMusicResult转换结果:');
    print(jsonString);
    // 输出: [{"name":"在线播放","musics":[{"name":"爱你没差 - 周杰伦","url":"https://example.com/music.mp3","api":true,"headers":{"X-Request-Key":"share-v2","User-Agent":"Mozilla/5.0...","Referer":"https://y.qq.com/"}}]}]
  }

  /// 示例2：处理JS脚本返回的原始JSON格式
  static void exampleWithRawJson() {
    // 模拟不同JS脚本可能返回的格式

    // 格式1：标准格式
    final rawResults1 = [
      {
        'title': '稻香',
        'artist': '周杰伦',
        'url': 'https://music.example.com/daoxiang.mp3',
        'platform': 'qq',
        'duration': '3:45'
      }
    ];

    // 格式2：字段名不同
    final rawResults2 = [
      {
        'name': '青花瓷',
        'singer': '周杰伦',
        'link': 'https://music.example.com/qinghuaci.mp3',
        'source': 'netease',
        'time': 225
      }
    ];

    // 格式3：嵌套格式
    final rawResults3 = [
      {
        'song_name': '夜曲',
        'author': '周杰伦',
        'play_url': 'https://music.example.com/yequ.mp3',
        'platform': 'kugou',
        'duration': 240
      }
    ];

    // 使用适配器转换所有格式
    final json1 = MusicListJsonAdapter.convertFromRawJson(rawResults: rawResults1);
    final json2 = MusicListJsonAdapter.convertFromRawJson(rawResults: rawResults2);
    final json3 = MusicListJsonAdapter.convertFromRawJson(rawResults: rawResults3);

    print('原始JSON格式1转换结果:');
    print(json1);
    print('\n原始JSON格式2转换结果:');
    print(json2);
    print('\n原始JSON格式3转换结果:');
    print(json3);
  }

  /// 示例3：创建单首歌曲
  static void exampleSingleSong() {
    final jsonString = MusicListJsonAdapter.createSingleSongJson(
      title: '告白气球',
      artist: '周杰伦',
      url: 'https://music.example.com/gaobaiqiqiu.mp3',
      headers: {
        'X-Request-Key': 'share-v2',
        'User-Agent': 'CustomUA/1.0',
      },
    );

    print('单首歌曲JSON:');
    print(jsonString);
  }

  /// 示例4：验证JSON格式
  static void exampleValidation() {
    // 有效的JSON
    final validJson = '''
    [
      {
        "name": "在线播放",
        "musics": [
          {
            "name": "歌曲名 - 艺术家",
            "url": "https://example.com/song.mp3",
            "api": true,
            "headers": {"X-Request-Key": "share-v2"}
          }
        ]
      }
    ]
    ''';

    // 无效的JSON
    final invalidJson = '''
    {
      "name": "在线播放",
      "songs": []
    }
    ''';

    print('有效JSON验证: ${MusicListJsonAdapter.validateMusicListJson(validJson)}'); // true
    print('无效JSON验证: ${MusicListJsonAdapter.validateMusicListJson(invalidJson)}'); // false
  }

  /// 示例5：向现有列表添加歌曲
  static void exampleAddToExisting() {
    final existingJson = '''
    [
      {
        "name": "在线播放",
        "musics": [
          {
            "name": "现有歌曲 - 艺术家",
            "url": "https://example.com/existing.mp3"
          }
        ]
      }
    ]
    ''';

    final newResults = [
      OnlineMusicResult(
        songId: '456',
        title: '新歌曲',
        author: '新艺术家',
        url: 'https://example.com/new.mp3',
        platform: 'qq',
        duration: 200,
        album: '',
        extra: {},
      ),
    ];

    final updatedJson = MusicListJsonAdapter.addToExistingJson(
      existingJson: existingJson,
      newResults: newResults,
    );

    print('添加歌曲后的JSON:');
    print(updatedJson);
  }

  /// 运行所有示例
  static void runAllExamples() {
    print('=== 音乐列表JSON适配器使用示例 ===\n');

    print('1. OnlineMusicResult对象示例:');
    exampleWithOnlineMusicResult();
    print('\n' + '=' * 50 + '\n');

    print('2. 原始JSON格式示例:');
    exampleWithRawJson();
    print('\n' + '=' * 50 + '\n');

    print('3. 单首歌曲示例:');
    exampleSingleSong();
    print('\n' + '=' * 50 + '\n');

    print('4. JSON验证示例:');
    exampleValidation();
    print('\n' + '=' * 50 + '\n');

    print('5. 添加到现有列表示例:');
    exampleAddToExisting();
  }
}

/// 常见JS脚本返回格式的处理示例
class CommonJSFormats {
  /// 处理MusicFree格式
  static String handleMusicFreeFormat(Map<String, dynamic> musicFreeResult) {
    // MusicFree通常返回这样的格式:
    // {
    //   "data": [
    //     {
    //       "title": "歌名",
    //       "artist": "艺术家",
    //       "url": "播放链接"
    //     }
    //   ]
    // }

    final data = musicFreeResult['data'] as List<dynamic>? ?? [];
    final rawResults = data.map((item) => item as Map<String, dynamic>).toList();

    return MusicListJsonAdapter.convertFromRawJson(
      rawResults: rawResults,
      playlistName: "MusicFree播放",
    );
  }

  /// 处理LX Music格式
  static String handleLXMusicFormat(List<dynamic> lxResults) {
    // LX Music通常返回数组格式:
    // [
    //   {
    //     "songmid": "id",
    //     "name": "歌名", 
    //     "singer": "艺术家",
    //     "url": "播放链接"
    //   }
    // ]

    final rawResults = lxResults.map((item) => item as Map<String, dynamic>).toList();

    return MusicListJsonAdapter.convertFromRawJson(
      rawResults: rawResults,
      playlistName: "LX音源播放",
    );
  }

  /// 处理网易云格式
  static String handleNeteaseFormat(Map<String, dynamic> neteaseResult) {
    // 网易云API格式:
    // {
    //   "result": {
    //     "songs": [
    //       {
    //         "name": "歌名",
    //         "ar": [{"name": "艺术家"}],
    //         "al": {"name": "专辑"}
    //       }
    //     ]
    //   }
    // }

    final songs = neteaseResult['result']?['songs'] as List<dynamic>? ?? [];
    final rawResults = songs.map((song) {
      final artists = (song['ar'] as List<dynamic>?)
          ?.map((ar) => ar['name'])
          .join(', ') ?? '未知艺术家';

      return {
        'title': song['name'],
        'artist': artists,
        'album': song['al']?['name'] ?? '',
        'platform': 'netease',
        // 注意：实际使用时需要通过其他API获取播放链接
        'url': '', // 需要额外调用获取播放链接的API
      };
    }).toList();

    return MusicListJsonAdapter.convertFromRawJson(
      rawResults: rawResults,
      playlistName: "网易云播放",
      defaultHeaders: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://music.163.com/',
      },
    );
  }
}
