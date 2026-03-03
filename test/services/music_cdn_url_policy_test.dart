import 'package:flutter_test/flutter_test.dart';
import 'package:hmusic/data/services/music_cdn_url_policy.dart';

void main() {
  group('MusicCdnUrlPolicy', () {
    test('CDN 识别与 URL 协议无关（http/https 都可识别）', () {
      const neteaseHttp = 'http://m801.music.126.net/path/song.mp3';
      const neteaseHttps = 'https://m801.music.126.net/path/song.mp3';
      const qqHttp = 'http://ws.stream.qqmusic.qq.com/path/song.mp3';
      const qqHttps = 'https://ws.stream.qqmusic.qq.com/path/song.mp3';
      const kuwoHttp = 'http://antiserver.kuwo.cn/path/song.mp3';
      const kuwoHttps = 'https://antiserver.kuwo.cn/path/song.mp3';

      expect(MusicCdnUrlPolicy.isNeteaseCdn(neteaseHttp), isTrue);
      expect(MusicCdnUrlPolicy.isNeteaseCdn(neteaseHttps), isTrue);
      expect(MusicCdnUrlPolicy.isQqCdn(qqHttp), isTrue);
      expect(MusicCdnUrlPolicy.isQqCdn(qqHttps), isTrue);
      expect(MusicCdnUrlPolicy.isKuwoCdn(kuwoHttp), isTrue);
      expect(MusicCdnUrlPolicy.isKuwoCdn(kuwoHttps), isTrue);
    });

    test('MiIoT 直连判定: 网易默认直连，QQ 受开关控制', () {
      const netease = 'https://m801.music.126.net/path/song.mp3';
      const qq = 'https://ws.stream.qqmusic.qq.com/path/song.mp3';
      const kuwo = 'https://antiserver.kuwo.cn/path/song.mp3';

      expect(
        MusicCdnUrlPolicy.shouldForceDirectForMiIoT(netease),
        isTrue,
      );
      expect(
        MusicCdnUrlPolicy.shouldForceDirectForMiIoT(qq),
        isFalse,
      );
      expect(
        MusicCdnUrlPolicy.shouldForceDirectForMiIoT(
          qq,
          enableQqDirect: true,
        ),
        isTrue,
      );
      expect(
        MusicCdnUrlPolicy.shouldForceDirectForMiIoT(
          kuwo,
          enableQqDirect: true,
        ),
        isFalse,
      );
    });

    test('MiIoT 代理判定: QQ和酷我默认要求走代理', () {
      const qq = 'https://ws.stream.qqmusic.qq.com/path/song.mp3';
      const kuwo = 'https://antiserver.kuwo.cn/path/song.mp3';
      const kuwoHttp = 'http://lv.sycdn.kuwo.cn/path/song.mp3';
      const netease = 'https://m801.music.126.net/path/song.mp3';

      expect(MusicCdnUrlPolicy.shouldRequireProxyForMiIoT(qq), isTrue);
      expect(MusicCdnUrlPolicy.shouldRequireProxyForMiIoT(kuwo), isTrue);
      expect(MusicCdnUrlPolicy.shouldRequireProxyForMiIoT(kuwoHttp), isTrue);
      expect(MusicCdnUrlPolicy.shouldRequireProxyForMiIoT(netease), isFalse);
    });
  });
}
