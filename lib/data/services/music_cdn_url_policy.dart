class MusicCdnUrlPolicy {
  static const List<String> _neteaseHostHints = <String>[
    'music.126.net',
    'music.163.com',
    '126.net',
  ];

  static const List<String> _qqHostHints = <String>[
    'music.tc.qq.com',
    'qqmusic.qq.com',
    'ws.stream.qqmusic.qq.com',
    'wx.music.tc.qq.com',
    'isure.stream.qqmusic.qq.com',
  ];

  static const List<String> _kuwoHostHints = <String>[
    'kuwo.cn',
    'kuwo.com',
    'antiserver.kuwo.cn',
    'nmobi.kuwo.cn',
  ];

  static bool isNeteaseCdn(String url) {
    final host = _parseHost(url);
    if (host.isEmpty) return false;
    return _neteaseHostHints.any(host.contains);
  }

  static bool isQqCdn(String url) {
    final host = _parseHost(url);
    if (host.isEmpty) return false;
    return _qqHostHints.any(host.contains);
  }

  static bool isKuwoCdn(String url) {
    final host = _parseHost(url);
    if (host.isEmpty) return false;
    return _kuwoHostHints.any(host.contains);
  }

  static bool shouldForceDirectForMiIoT(
    String url, {
    bool enableQqDirect = false,
  }) {
    if (isNeteaseCdn(url)) return true;
    if (enableQqDirect && isQqCdn(url)) return true;
    return false;
  }

  static bool shouldRequireProxyForMiIoT(String url) {
    if (isQqCdn(url)) return true;
    if (isKuwoCdn(url)) return true;
    return false;
  }

  static String _parseHost(String url) {
    final uri = Uri.tryParse(url);
    return (uri?.host ?? '').toLowerCase();
  }
}
