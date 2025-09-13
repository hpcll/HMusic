import 'dart:async';
import 'dart:io';
import 'package:flutter_js/flutter_js.dart';
import 'package:dio/dio.dart';
import '../../presentation/providers/source_settings_provider.dart';
import '../models/js_script.dart';
import 'dart:convert';
// grass 支持已移除

class LocalJsSourceService {
  final JavascriptRuntime _rt;
  final Dio _http;
  bool _loaded = false;

  LocalJsSourceService._(this._rt, this._http);

  static Future<LocalJsSourceService> create() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 45),
        validateStatus: (status) => status != null && status < 500,
        headers: {
          'Accept': 'text/javascript,application/javascript;q=0.9,*/*;q=0.1',
          'User-Agent': 'xiaoaitongxue-localjs-loader',
        },
      ),
    );

    // 设置transformer为处理任意响应类型，避免content-type解析问题
    dio.transformer = BackgroundTransformer();

    return LocalJsSourceService._(getJavascriptRuntime(), dio);
  }

  // 内置脚本加载已完全移除

  /// 从本地文件读取脚本内容
  Future<String?> _readLocalScript(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        print('[XMC] ❌ [LocalJsSource] 本地文件不存在: $filePath');
        return null;
      }

      final script = await file.readAsString();
      if (script.isEmpty) {
        print('[XMC] ⚠️ [LocalJsSource] 本地脚本内容为空: $filePath');
        return null;
      }

      print('[XMC] ✅ [LocalJsSource] 成功读取本地脚本: $filePath');
      return script;
    } catch (e) {
      print('[XMC] ❌ [LocalJsSource] 读取本地脚本失败 $filePath: $e');
      return null;
    }
  }

  /// 下载远程脚本
  Future<String?> _downloadScript(String url) async {
    try {
      final resp = await _http.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 45),
          validateStatus: (code) => code != null && code >= 200 && code < 400,
          headers: {
            'Accept': 'text/javascript,application/javascript;q=0.9,*/*;q=0.1',
            'Cache-Control': 'no-cache',
            'Pragma': 'no-cache',
          },
        ),
      );
      final script = resp.data ?? '';
      if (script.isEmpty) {
        print('[XMC] ⚠️ [LocalJsSource] 脚本内容为空: $url');
        return null;
      }
      return script;
    } catch (e) {
      print('[XMC] ❌ [LocalJsSource] 下载脚本失败 $url: $e');
      return null;
    }
  }

  Future<void> loadScript(
    SourceSettings settings, [
    JsScript? selectedScript,
  ]) async {
    print('[XMC] 🔧 [LocalJsSource] 开始加载JS音源');
    print('[XMC] 🔧 [LocalJsSource] 启用状态: ${settings.enabled}');
    print('[XMC] 🔧 [LocalJsSource] 主要音源: ${settings.primarySource}');
    print('[XMC] 🔧 [LocalJsSource] 选中脚本: ${selectedScript?.name ?? '无'}');

    if (!settings.enabled || settings.primarySource != 'js_external') {
      print('[XMC] ❌ [LocalJsSource] JS音源未启用');
      _loaded = false;
      return;
    }

    if (selectedScript == null) {
      print('[XMC] ❌ [LocalJsSource] 未选择脚本');
      _loaded = false;
      return;
    }

    // 获取脚本内容
    String? scriptContent;

    switch (selectedScript.source) {
      case JsScriptSource.builtin:
      case JsScriptSource.url:
        // 从URL下载脚本
        print('🌐 [LocalJsSource] 从URL加载脚本: ${selectedScript.content}');
        final urls = [selectedScript.content];
        for (final url in urls) {
          print('🌐 [LocalJsSource] 正在请求: $url');
          scriptContent = await _downloadScript(url);
          if (scriptContent != null && scriptContent.isNotEmpty) {
            print('[XMC] ✅ [LocalJsSource] 脚本加载成功: $url');
            break;
          }
        }
        break;

      case JsScriptSource.localFile:
        // 从本地文件加载
        print('📁 [LocalJsSource] 从本地文件加载脚本: ${selectedScript.content}');
        scriptContent = await _readLocalScript(selectedScript.content);
        break;
    }

    if (scriptContent == null || scriptContent.isEmpty) {
      print('[XMC] ❌ [LocalJsSource] 所有脚本源都加载失败');
      _loaded = false;
      return;
    }

    // 预处理脚本内容，检测和修复常见问题
    scriptContent = _preprocessScript(scriptContent);

    // 执行脚本
    try {
      print('🍪 [LocalJsSource] 注入Cookie变量');
      // 注入 cookie 变量
      final cookieInit =
          "var MUSIC_U='${settings.cookieNetease}'; var ts_last='${settings.cookieTencent}';";
      _rt.evaluate(cookieInit);

      print('🔄 [LocalJsSource] 开始执行JS脚本...');
      // 注入简易 LX 环境以兼容为 LX 定制的音源脚本
      const String lxShim = r'''(function(){
          try{
            var g = (typeof globalThis !== 'undefined') ? globalThis : (this||{});
            // 基础 polyfill
            if (typeof g.atob !== 'function') {
              g.atob = function(input){
                var chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                input = String(input).replace(/=+$/, '');
                var str='';
                for (var bc=0, bs, buffer, idx=0; buffer = input.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? str += String.fromCharCode(255 & (bs >> (-2 * bc & 6))) : 0) {
                  buffer = chars.indexOf(buffer);
                }
                return str;
              };
            }
            if (typeof g.btoa !== 'function') {
              g.btoa = function(input){
                var chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
                var str = String(input);
                var output='';
                for (var block, charCode, idx=0, map=chars; str.charAt(idx | 0) || (map='=', idx % 1); output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
                  charCode = str.charCodeAt(idx += 3/4);
                  if (charCode > 0xFF) throw new Error('btoa polyfill: invalid char');
                  block = block << 8 | charCode;
                }
                return output;
              };
            }
            if (typeof g.Buffer === 'undefined') {
              g.Buffer = {
                from: function(input, enc){
                  if (enc === 'base64') {
                    var bin = g.atob(String(input||''));
                    var len = bin.length;
                    var out = new Uint8Array(len);
                    for (var i=0;i<len;i++) out[i] = bin.charCodeAt(i) & 0xff;
                    return out;
                  }
                  if (typeof input === 'string') {
                    var utf8 = unescape(encodeURIComponent(input));
                    var out2 = new Uint8Array(utf8.length);
                    for (var j=0;j<utf8.length;j++) out2[j] = utf8.charCodeAt(j);
                    return out2;
                  }
                  // 支持 ArrayBuffer / TypedArray / Array
                  if (input && (input.byteLength !== undefined)) return new Uint8Array(input);
                  if (input && (input.buffer && input.byteLength !== undefined)) return new Uint8Array(input);
                  if (Array.isArray(input)) return new Uint8Array(input);
                  return new Uint8Array(0);
                },
                alloc: function(size, fill){ var buf = new Uint8Array(size|0); if (fill!==undefined) buf.fill(typeof fill==='number'?fill:0); return buf; },
                allocUnsafe: function(size){ return new Uint8Array(size|0); },
                concat: function(list, totalLength){
                  if (!Array.isArray(list) || list.length===0) return new Uint8Array(0);
                  var length = totalLength==null? list.reduce(function(a,b){ return a + (b? (b.length||0):0); }, 0) : totalLength;
                  var res = new Uint8Array(length);
                  var pos = 0;
                  for (var i=0;i<list.length;i++){ var it=list[i]; if (it && it.length){ res.set(it, pos); pos += it.length; } }
                  return res;
                }
              };
            }

            // LX 运行时最小模拟
            g.__lx_events = g.__lx_events || {};
            var evt = {
              SOURCE_LIST: 'SOURCE_LIST',
              SOURCE_SEARCH: 'SOURCE_SEARCH',
              SOURCE_SONG_URL: 'SOURCE_SONG_URL',
              SOURCE_LRC: 'SOURCE_LRC',
              SOURCE_ALBUM: 'SOURCE_ALBUM',
              SOURCE_ARTIST: 'SOURCE_ARTIST',
              request: 'request',
              inited: 'inited',
              REQUEST: 'request'
            };
            if(!g.lx){
              g.lx = {
                EVENT_NAMES: evt,
                APP_EVENT_NAMES: {},
                CURRENT_PLATFORM: 'desktop',
                APP_SETTING: {},
                version: '2.4.0',
                isDev: false,
                on: function(name, handler){ try{ g.__lx_events[name]=handler; }catch(_){} },
                off: function(name){ try{ delete g.__lx_events[name]; }catch(_){} },
                emit: function(name, payload){ try{ var h=g.__lx_events[name]; if (typeof h==='function') return h(payload); }catch(_){} },
                request: function(url, options, cb){
                  try{
                    var opts = options || {};
                    if (typeof fetch === 'function') {
                      fetch(url, opts).then(function(r){
                        return r.text().then(function(t){
                          var body; try{ body = JSON.parse(t); }catch(_){ body = t; }
                          var headers = {}; try{ if (r.headers && r.headers.forEach) { r.headers.forEach(function(v,k){ headers[k]=v; }); } }catch(_){ }
                          var resp = { statusCode: r.status, status: r.status, headers: headers, body: body };
                          if (typeof cb === 'function') cb(null, resp);
                        });
                      }).catch(function(err){ if (typeof cb === 'function') cb(err); });
                    } else {
                      // 简易回退：使用XHR
                      var xhr = new XMLHttpRequest();
                      xhr.open(opts && opts.method ? opts.method : 'GET', url, true);
                      if (opts && opts.headers){ try{ Object.keys(opts.headers).forEach(function(k){ xhr.setRequestHeader(k, String(opts.headers[k])); }); }catch(_){} }
                      xhr.onload = function(){ var t = xhr.responseText||''; var body; try{ body = JSON.parse(t);}catch(_){ body=t; } var resp = { statusCode: xhr.status, status: xhr.status, headers: {}, body: body }; if (typeof cb==='function') cb(null, resp); };
                      xhr.onerror = function(err){ if (typeof cb==='function') cb(err||new Error('xhr error')); };
                      xhr.send(opts && opts.body ? opts.body : null);
                    }
                  }catch(e){ if (typeof cb === 'function') cb(e); }
                },
                send: function(){},
              };
            }
          }catch(e){}
        })()''';
      _rt.evaluate(lxShim);

      // 为LocalJS注入网络请求和Promise支持
      const String networkShim = r'''(function(){
          try{
            var g = (typeof globalThis !== 'undefined') ? globalThis : (typeof window !== 'undefined' ? window : this);

            // 仅拦截指定的脚本更新检测地址，避免触发连接拒绝
            if (typeof g.XMLHttpRequest !== 'undefined') {
              var OriginalXHR = g.XMLHttpRequest;
              g.XMLHttpRequest = function() {
                var xhr = new OriginalXHR();
                var _url = '';
                var originalOpen = xhr.open;
                var originalSend = xhr.send;
                xhr.open = function(method, url, async, user, password) {
                  try { _url = String(url||''); } catch(_) { _url = ''; }
                  // 仅拦截 43.143.63.234:9763 的脚本检查请求
                  if (_url.indexOf('http://43.143.63.234:9763/script') === 0) {
                    xhr.__intercepted = true;
                    setTimeout(function(){
                      try {
                        xhr.readyState = 4;
                        xhr.status = 200;
                        xhr.responseText = '{"code":0,"data":[],"list":[]}';
                        if (typeof xhr.onreadystatechange === 'function') xhr.onreadystatechange();
                        if (typeof xhr.onload === 'function') xhr.onload();
                      } catch(_) {}
                    }, 10);
                    return; // 不调用原始open
                  }
                  return originalOpen.call(xhr, method, url, async, user, password);
                };
                xhr.send = function(data) {
                  if (xhr.__intercepted) return; // 被拦截则不真正发送
                  return originalSend.call(xhr, data);
                };
                return xhr;
              };
            }

            // Promise 最小实现（如环境缺失）
            if (typeof g.Promise !== 'function') {
              g.Promise = function(executor){
                var self=this; self.state='pending'; self.value=void 0; self.handlers=[];
                function resolve(v){ if(self.state==='pending'){ self.state='fulfilled'; self.value=v; self.handlers.forEach(function(h){ h.onFulfilled(v); }); } }
                function reject(e){ if(self.state==='pending'){ self.state='rejected'; self.value=e; self.handlers.forEach(function(h){ h.onRejected(e); }); } }
                try{ executor(resolve,reject); }catch(e){ reject(e); }
              };
              g.Promise.prototype.then = function(onF,onR){ var self=this; return new g.Promise(function(res,rej){ function run(){ if(self.state==='fulfilled'){ try{ res(typeof onF==='function'? onF(self.value): self.value);}catch(e){ rej(e);} } else if(self.state==='rejected'){ try{ if(typeof onR==='function'){ res(onR(self.value)); } else { rej(self.value);} }catch(e){ rej(e);} } else { self.handlers.push({onFulfilled:function(v){ try{ res(typeof onF==='function'? onF(v): v);}catch(e){ rej(e);} }, onRejected:function(e){ try{ if(typeof onR==='function'){ res(onR(e)); } else { rej(e);} }catch(err){ rej(err);} }}); } } run(); }); };
              g.Promise.resolve = function(v){ return new g.Promise(function(r){ r(v); }); };
              g.Promise.reject = function(e){ return new g.Promise(function(_,r){ r(e); }); };
            }

            // 提供最小可用的 axios（基于 XHR），避免依赖 fetch
            if (typeof g.axios !== 'function') {
              g.axios = function(config){
                if (typeof config === 'string') config = { url: config, method: 'GET' };
                config = config || {};
                return new g.Promise(function(resolve, reject){
                  try{
                    var xhr = new XMLHttpRequest();
                    var method = (config.method||'GET').toUpperCase();
                    xhr.open(method, config.url||'', true);
                    if (config.headers){ try{ Object.keys(config.headers).forEach(function(k){ xhr.setRequestHeader(k, String(config.headers[k])); }); }catch(_){} }
                    xhr.responseType = 'text';
                    xhr.onload = function(){ resolve({ data: xhr.responseText, status: xhr.status, statusText: xhr.statusText, headers: {} }); };
                    xhr.onerror = function(){ reject(new Error('Network Error')); };
                    xhr.send(config.data!=null ? (typeof config.data==='string'? config.data : JSON.stringify(config.data)) : null);
                  }catch(e){ reject(e); }
                });
              };
              g.axios.get = function(url, cfg){ cfg = cfg||{}; cfg.url=url; cfg.method='GET'; return g.axios(cfg); };
              g.axios.post = function(url, data, cfg){ cfg = cfg||{}; cfg.url=url; cfg.method='POST'; cfg.data=data; return g.axios(cfg); };
              g.axios.default = g.axios;
            }

            console.log('[LocalJS] 网络和Promise shim已注入');
          }catch(e){
            try{ console.warn && console.warn('LocalJS NetworkShim error:', e); }catch(_){}
          }
        })()''';
      _rt.evaluate(networkShim);

      // 优先注入CommonJS环境，确保exports和module在脚本执行前就存在
      const String commonJsShim = r'''(function(){
          try{
            var g = (typeof globalThis !== 'undefined') ? globalThis : (typeof window !== 'undefined' ? window : this);
            
            // 优先确保exports和module存在
            if (!g.exports) {
              g.exports = {};
            }
            if (!g.module) {
              g.module = { exports: g.exports };
            }
            
            if (typeof require !== 'function'){
              function __axios(opts){
                opts = opts || {};
                var method = (opts.method || 'GET').toUpperCase();
                var headers = opts.headers || {};
                var body = (opts.data!=null) ? (typeof opts.data==='string' ? opts.data : JSON.stringify(opts.data)) : undefined;
                return new Promise(function(resolve, reject){
                  try{
                    if (typeof XMLHttpRequest === 'undefined') { return resolve({ data: '', status: 0, statusText: 'NO_XHR' }); }
                    var xhr = new XMLHttpRequest();
                    xhr.open(method, opts.url||'', true);
                    Object.keys(headers).forEach(function(k){ try{ xhr.setRequestHeader(k, String(headers[k])); }catch(_){} });
                    xhr.onload = function(){ var t = xhr.responseText||''; var d; try{ d = JSON.parse(t);}catch(_){ d=t; } resolve({ data: d, status: xhr.status, statusText: xhr.statusText }); };
                    xhr.onerror = function(){ reject(new Error('Network Error')); };
                    xhr.send(body);
                  }catch(e){ reject(e); }
                });
              }
              __axios.get = function(url, opts){ opts=opts||{}; return __axios({ url: url, method: 'GET', headers: (opts.headers||{}) }); };
              __axios.post = function(url, data, opts){ opts=opts||{}; return __axios({ url: url, method: 'POST', headers: (opts.headers||{}), data: data }); };
              __axios.default = __axios;
              
              var CryptoJs = { 
                enc: { 
                  Base64: { 
                    parse: function(s){ 
                      return { 
                        toString: function(){ 
                          try{ return atob(s);}catch(e){ return ''; } 
                        } 
                      }; 
                    },
                    stringify: function(obj) {
                      try {
                        if (obj && typeof obj.toString === 'function') {
                          return btoa(obj.toString());
                        }
                        return btoa(String(obj || ''));
                      } catch(e) { 
                        return ''; 
                      }
                    }
                  }, 
                  Utf8: {
                    parse: function(s){ return { toString: function(){ return s || ''; } }; },
                    stringify: function(obj) {
                      try {
                        return String(obj || '');
                      } catch(e) {
                        return '';
                      }
                    }
                  },
                  Hex: {
                    parse: function(s) {
                      return { toString: function() { return s || ''; } };
                    },
                    stringify: function(obj) {
                      try {
                        return String(obj || '');
                      } catch(e) {
                        return '';
                      }
                    }
                  }
                },
                AES: {
                  decrypt: function(ciphertext, key, cfg) { 
                    // 简单的模拟解密，实际项目中应该使用真正的加密库
                    return { toString: function(encoding) { 
                      if (encoding && encoding.stringify) {
                        return encoding.stringify({ toString: function() { return 'decrypted'; } });
                      }
                      return 'decrypted'; 
                    } }; 
                  },
                  encrypt: function(message, key, cfg) {
                    return { toString: function() { return 'encrypted'; } };
                  }
                },
                DES: {
                  decrypt: function(ciphertext, key, cfg) { 
                    return { toString: function(encoding) { 
                      if (encoding && encoding.stringify) {
                        return encoding.stringify({ toString: function() { return 'decrypted'; } });
                      }
                      return 'decrypted'; 
                    } }; 
                  }
                },
                MD5: function(message) {
                  return { toString: function() { return 'md5hash'; } };
                },
                SHA1: function(message) {
                  return { toString: function() { return 'sha1hash'; } };
                },
                SHA256: function(message) {
                  return { toString: function() { return 'sha256hash'; } };
                },
                HmacSHA1: function(message, key) {
                  return { toString: function() { return 'hmacsha1'; } };
                },
                HmacSHA256: function(message, key) {
                  return { toString: function() { return 'hmacsha256'; } };
                },
                mode: {
                  ECB: {},
                  CBC: {}
                },
                pad: {
                  Pkcs7: {},
                  NoPadding: {}
                }
              };
              var he = { 
                decode: function(s){ 
                  try{ 
                    return s.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&#39;/g,'\'').replace(/&quot;/g,'"'); 
                  }catch(e){ 
                    return s; 
                  } 
                } 
              };
              
              var __cjs_cache = {};
              function __wrapDefault(obj){ try{ obj.default = obj.default || obj; }catch(_){} return obj; }
               function require(name){
                if (__cjs_cache[name]) return __cjs_cache[name];
                if (name === 'axios') { __cjs_cache[name] = __axios; return __axios; }
                if (name === 'crypto-js') { var c = __wrapDefault(CryptoJs); __cjs_cache[name]=c; return c; }
                if (name === 'he') { var h = __wrapDefault(he); __cjs_cache[name]=h; return h; }
                var empty = {}; __wrapDefault(empty); __cjs_cache[name]=empty; return empty;
              }
              
              try{ g.require = require; }catch(_){ }
            }
          }catch(e){
            console.warn && console.warn('LocalJS CommonJS shim error:', e);
          }
        })()''';
      _rt.evaluate(commonJsShim);
      _rt.evaluate(scriptContent);

      // 跳过额外插件加载，只使用用户指定的单一脚本源
      print('[XMC] 🔒 [LocalJsSource] 只加载用户指定的脚本，跳过额外插件加载');

      // 验证脚本加载结果
      final validation = await _validateScriptLoading();

      if (validation['success']) {
        print('[XMC] ✅ [LocalJsSource] JS脚本加载和验证成功！');
        print('[XMC] ✅ [LocalJsSource] 可用功能: ${validation['functions']}');
        _loaded = true;
      } else {
        print('[XMC] ⚠️ [LocalJsSource] 脚本加载但验证失败: ${validation['error']}');
        _loaded = false;
      }
    } catch (e) {
      print('[XMC] ❌ [LocalJsSource] 脚本执行失败，错误: $e');
      _loaded = false;

      // 尝试错误恢复
      try {
        print('[XMC] 🔄 [LocalJsSource] 尝试错误恢复...');
        await _attemptErrorRecovery(e.toString(), scriptContent);
      } catch (recoveryError) {
        print('[XMC] ❌ [LocalJsSource] 错误恢复失败: $recoveryError');
      }
    }
  }

  bool get isReady => _loaded;

  /// 预处理脚本内容，修复常见问题
  String _preprocessScript(String script) {
    // 移除潜在的BOM标记
    if (script.startsWith('\uFEFF')) {
      script = script.substring(1);
    }

    // 修复常见的编码问题
    script = script.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 添加严格模式保护
    if (!script.contains('use strict') && !script.contains('"use strict"')) {
      script = '"use strict";\n' + script;
    }

    // 包装在IIFE中以避免全局变量污染
    script = '(function() {\n' + script + '\n})();';

    return script;
  }

  /// 验证脚本加载结果
  Future<Map<String, dynamic>> _validateScriptLoading() async {
    try {
      // 检查基本函数可用性
      final checkResult = await detectAdapterFunctions();
      if (checkResult['ok'] == true) {
        final functions = checkResult['functions'] as List<String>;
        return {'success': true, 'functions': functions};
      }

      return {'success': false, 'error': '未找到可用的搜索函数'};
    } catch (e) {
      return {'success': false, 'error': '验证过程异常: $e'};
    }
  }

  /// 尝试错误恢复
  Future<void> _attemptErrorRecovery(String error, String scriptContent) async {
    print('[XMC] 🔄 [LocalJsSource] 分析错误类型: $error');

    if (error.contains('SyntaxError') || error.contains('Unexpected token')) {
      print('[XMC] 🔄 [LocalJsSource] 检测到语法错误，尝试兼容性修复');

      // 尝试简化的脚本执行
      try {
        final simpleScript = '''
          // 简化的搜索函数
          function search(platform, keyword, page) {
            try {
              return [{
                id: 'fallback_' + Date.now(),
                title: '搜索功能暂不可用',
                artist: '系统提示',
                url: '',
                platform: platform || 'unknown'
              }];
            } catch (e) {
              return [];
            }
          }
          
          // 导出函数
          if (typeof module !== 'undefined' && module.exports) {
            module.exports = { search: search };
          }
        ''';

        _rt.evaluate(simpleScript);
        print('[XMC] ✅ [LocalJsSource] 错误恢复成功，加载了简化版本');
        _loaded = true;
      } catch (e) {
        print('[XMC] ❌ [LocalJsSource] 错误恢复失败: $e');
      }
    }
  }

  /// 构建智能搜索脚本
  String _buildSearchScript(
    String functionName,
    List<String> platforms,
    String keyword,
    int page,
  ) {
    return """
      (function(){ 
        try { 
          var plats = ${jsonEncode(platforms)};
          
          // 智能平台映射
          function mapPlat(p) { 
            p = (p || '').toLowerCase(); 
            if (p === 'qq' || p === 'tencent') return 'tx'; 
            if (p === 'netease' || p === '163') return 'wy'; 
            if (p === 'kuwo') return 'kw'; 
            if (p === 'kugou') return 'kg'; 
            if (p === 'migu') return 'mg'; 
            return p; 
          }
          
          // 智能结果标准化
          function normalizeResult(x) { 
            try { 
              console.log && console.log('[LocalJS] 标准化处理:', typeof x, Array.isArray(x)); 
              
              function safeItem(item, idx) { 
                try { 
                  var safe = {}; 
                  if (item.title || item.name) safe.title = item.title || item.name; 
                  if (item.artist || item.singer) safe.artist = item.artist || item.singer; 
                  if (item.album) safe.album = item.album; 
                  if (item.duration) safe.duration = item.duration; 
                  if (item.url || item.link) safe.url = item.url || item.link; 
                  if (item.id) safe.id = item.id; 
                  if (item.platform) safe.platform = item.platform; 
                  return safe; 
                } catch (e) { 
                  console.warn && console.warn('[LocalJS] 项目', idx, '处理失败:', e); 
                  return { title: 'Unknown', artist: 'Unknown' }; 
                } 
              } 
              
              // 直接数组
              if (Array.isArray(x)) { 
                return x.map(safeItem); 
              } 
              
              // 检查常见的数据字段
              var dataFields = ['data', 'list', 'songs', 'result', 'items'];
              for (var i = 0; i < dataFields.length; i++) {
                var field = dataFields[i];
                if (x && Array.isArray(x[field])) { 
                  console.log && console.log('[LocalJS] 发现', field, '字段，长度:', x[field].length); 
                  return x[field].map(safeItem); 
                } 
              }
              
              // 检查对象的所有数组字段
              if (typeof x === 'object' && x !== null) { 
                var keys = Object.keys(x); 
                for (var j = 0; j < keys.length; j++) { 
                  if (Array.isArray(x[keys[j]])) { 
                    console.log && console.log('[LocalJS] 找到数组字段:', keys[j], '长度:', x[keys[j]].length); 
                    return x[keys[j]].map(safeItem); 
                  } 
                } 
              } 
            } catch (e) {
              console.warn && console.warn('[LocalJS] 标准化错误:', e);
            } 
            
            console.log && console.log('[LocalJS] 无法提取数组，返回空'); 
            return []; 
          } 
          
          // 尝试多个平台
          for (var i = 0; i < plats.length; i++) { 
            try { 
              var p = mapPlat(plats[i]); 
              console.log && console.log('[LocalJS] 尝试平台:', p); 
              
              var r = $functionName(p, '$keyword', $page); 
              console.log && console.log('[LocalJS] 平台原始结果:', p, typeof r); 
              
              // 处理Promise
              if (r && typeof r.then === 'function') { 
                console.log && console.log('[LocalJS] 检测到Promise，检查状态'); 
                if (r.state === 'fulfilled' && r.value) { 
                  r = r.value; 
                } else { 
                  console.log && console.log('[LocalJS] Promise未完成，跳过'); 
                  continue; 
                } 
              } 
              
              var normalized = normalizeResult(r); 
              if (normalized && normalized.length > 0) { 
                console.log && console.log('[LocalJS] 平台', p, '找到结果:', normalized.length, '条'); 
                return JSON.stringify(normalized); 
              } else { 
                console.log && console.log('[LocalJS] 平台', p, '无有效结果'); 
              } 
            } catch (e) { 
              console.warn && console.warn('[LocalJS] 平台搜索失败:', p, e); 
            } 
          } 
          
          // MusicFree格式支持
          try { 
            if (typeof module !== 'undefined' && module && module.exports) { 
              var exp = module.exports; 
              if (exp.platform && (exp.search || exp.searchMusic)) { 
                console.log && console.log('[LocalJS] 检测到MusicFree格式，尝试搜索'); 
                var searchFn = exp.search || exp.searchMusic; 
                if (typeof searchFn === 'function') { 
                  var query = { keyword: '$keyword', page: $page, type: 'music' }; 
                  try { 
                    var res = searchFn(query); 
                    console.log && console.log('[LocalJS] MusicFree搜索结果类型:', typeof res); 
                    
                    if (res && typeof res.then === 'function') { 
                      if (res.state === 'fulfilled') { 
                        var n = normalizeResult(res.value); 
                        if (n && n.length > 0) { 
                          return JSON.stringify(n); 
                        } 
                      } 
                    } else { 
                      var n = normalizeResult(res); 
                      if (n && n.length > 0) { 
                        return JSON.stringify(n); 
                      } 
                    } 
                  } catch (fe) { 
                    console.warn && console.warn('[LocalJS] MusicFree函数调用失败:', fe); 
                  } 
                } 
              } 
            } 
          } catch (e) { 
            console.warn && console.warn('[LocalJS] MusicFree格式搜索失败:', e); 
          } 
          
          console.log && console.log('[LocalJS] 所有平台都失败'); 
          return '[]'; 
        } catch (e) { 
          console.error && console.error('[LocalJS] 搜索代码执行失败:', e); 
          return '[]'; 
        } 
      })()
    """;
  }

  // 安全执行小段 JS，返回字符串
  String evaluateToString(String js) {
    final res = _rt.evaluate(js);
    return res.stringResult;
  }

  /// 轻量级能力检测：检查脚本是否已正确注入可用的搜索函数
  /// 不实际发起网络请求，仅检测函数是否存在
  Future<Map<String, dynamic>> detectAdapterFunctions() async {
    if (!_loaded) {
      return {'ok': false, 'functions': <String>[]};
    }

    try {
      // 优先检测常见导出函数名
      final String checkJs = """
        (function(){
          var ok = [];
          try {
            var names = ${jsonEncode(<String>['search', 'musicSearch', 'searchMusic'])};
            for (var i = 0; i < names.length; i++) {
              var n = names[i];
              try {
                var f = (typeof eval === 'function') ? eval(n) : (this && this[n]);
                if (typeof f === 'function') ok.push(n);
              } catch(e) {}
            }
          } catch(e) {}
          return JSON.stringify(ok);
        })()
      """;

      final res = _rt.evaluate(checkJs);
      final String text = res.stringResult;
      final List<dynamic> listDyn = jsonDecode(text) as List<dynamic>;
      final List<String> found = listDyn.map((e) => e.toString()).toList();

      // 若未发现常见函数，再宽松扫描所有包含 search 的全局函数名
      if (found.isEmpty) {
        final String scanJs = """
          (function(){
            var results = [];
            try {
              var g = this || global || {};
              for (var k in g) {
                try {
                  if (typeof g[k] === 'function' && (k+"" ).toLowerCase().indexOf('search') >= 0) {
                    results.push(k);
                  }
                } catch(e) {}
              }
            } catch(e) {}
            return JSON.stringify(results);
          })()
        """;
        final scanRes = _rt.evaluate(scanJs);
        final List<dynamic> scanList =
            jsonDecode(scanRes.stringResult) as List<dynamic>;
        final List<String> scanFound =
            scanList.map((e) => e.toString()).toList();
        return {'ok': scanFound.isNotEmpty, 'functions': scanFound};
      }

      return {'ok': found.isNotEmpty, 'functions': found};
    } catch (_) {
      return {'ok': false, 'functions': <String>[]};
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String keyword, {
    String platform = 'auto',
    int page = 1,
  }) async {
    print('[XMC] 🔍 [LocalJsSource] 开始搜索: $keyword, 平台: $platform, 页面: $page');

    if (!_loaded) {
      print('[XMC] ❌ [LocalJsSource] 脚本未加载，无法搜索');
      return const [];
    }

    // 搜索参数验证和清理
    if (keyword.trim().isEmpty) {
      print('[XMC] ⚠️ [LocalJsSource] 搜索关键词为空');
      return const [];
    }
    // 智能参数处理
    final escapedKw = keyword.replaceAll("'", " ").replaceAll('"', ' ').trim();
    final platforms =
        platform == 'auto'
            ? ["qq", "netease", "kuwo", "kugou", "migu"]
            : [platform];

    // 智能函数检测：按优先级排序
    final candidateFunctions = [
      'search', // 最常见
      'musicSearch', // MusicFree格式
      'searchMusic', // 替代格式
      'doSearch', // 另一种常见格式
    ];

    print('[XMC] 🔍 [LocalJsSource] 尝试平台: ${platforms.join(', ')}');

    String? workingFunction;
    String result = '[]';
    List<String> searchLog = [];

    // 智能函数检测：检查所有可能的函数
    Map<String, bool> functionAvailability = {};
    for (final funcName in candidateFunctions) {
      try {
        final checkJs = "typeof $funcName === 'function' ? 'yes' : 'no'";
        final checkResult = _rt.evaluate(checkJs);
        functionAvailability[funcName] = checkResult.stringResult == 'yes';
        if (checkResult.stringResult == 'yes') {
          workingFunction ??= funcName; // 使用第一个可用的
        }
      } catch (e) {
        functionAvailability[funcName] = false;
        print('[XMC] ⚠️ [LocalJsSource] 检查函数 $funcName 失败: $e');
      }
    }

    print('[XMC] 🔍 [LocalJsSource] 函数可用性: $functionAvailability');

    if (workingFunction != null) {
      print('[XMC] ✅ [LocalJsSource] 使用函数: $workingFunction');
    }

    if (workingFunction != null) {
      // 构建智能搜索JS代码
      final js = _buildSearchScript(
        workingFunction,
        platforms,
        escapedKw,
        page,
      );
      "function norm(x){ " +
          "try{ " +
          "console.log && console.log('[LocalJS] norm处理:', typeof x, Array.isArray(x)); " +
          "function safeItem(item, idx) { " +
          "try{ " +
          "var safe = {}; " +
          "if(item.title || item.name) safe.title = item.title || item.name; " +
          "if(item.artist || item.singer) safe.artist = item.artist || item.singer; " +
          "if(item.album) safe.album = item.album; " +
          "if(item.duration) safe.duration = item.duration; " +
          "if(item.url || item.link) safe.url = item.url || item.link; " +
          "if(item.id) safe.id = item.id; " +
          "if(item.platform) safe.platform = item.platform; " +
          "return safe; " +
          "}catch(e){ " +
          "console.warn && console.warn('[LocalJS] 项目', idx, '处理失败:', e); " +
          "return {title:'Unknown',artist:'Unknown'}; " +
          "} " +
          "} " +
          "if(Array.isArray(x)) { " +
          "console.log && console.log('[LocalJS] 直接数组，长度:', x.length); " +
          "return x.map(safeItem); " +
          "} " +
          "if(x && Array.isArray(x.data)) { " +
          "console.log && console.log('[LocalJS] 发现x.data，长度:', x.data.length); " +
          "return x.data.map(safeItem); " +
          "} " +
          "if(x && Array.isArray(x.list)) { " +
          "console.log && console.log('[LocalJS] 发现x.list，长度:', x.list.length); " +
          "return x.list.map(safeItem); " +
          "} " +
          "if(x && Array.isArray(x.songs)) { " +
          "console.log && console.log('[LocalJS] 发现x.songs，长度:', x.songs.length); " +
          "return x.songs.map(safeItem); " +
          "} " +
          "if(x && Array.isArray(x.result)) { " +
          "console.log && console.log('[LocalJS] 发现x.result，长度:', x.result.length); " +
          "return x.result.map(safeItem); " +
          "} " +
          "if(typeof x === 'object' && x !== null) { " +
          "var keys = Object.keys(x); " +
          "console.log && console.log('[LocalJS] 对象键值:', keys); " +
          "for(var j=0; j<keys.length; j++) { " +
          "if(Array.isArray(x[keys[j]])) { " +
          "console.log && console.log('[LocalJS] 找到数组字段:', keys[j], '长度:', x[keys[j]].length); " +
          "return x[keys[j]].map(safeItem); " +
          "} " +
          "} " +
          "} " +
          "}catch(e){console.warn && console.warn('[LocalJS] norm error:', e);} " +
          "console.log && console.log('[LocalJS] 无法提取数组，返回空'); " +
          "return []; " +
          "} " +
          "for(var i=0;i<plats.length;i++){ " +
          "try { " +
          "var p=mapPlat(plats[i]); " +
          "console.log && console.log('[LocalJS] 尝试平台:', p); " +
          "var r=$workingFunction(p,'" +
          escapedKw +
          "'," +
          page.toString() +
          "); " +
          "console.log && console.log('[LocalJS] 平台原始结果:', p, typeof r); " +
          "if (r && typeof r.then === 'function') { " +
          "console.log && console.log('[LocalJS] 检测到Promise，检查状态'); " +
          "if (r.state === 'fulfilled' && r.value) { " +
          "console.log && console.log('[LocalJS] Promise已完成，使用value'); " +
          "r = r.value; " +
          "} else { " +
          "console.log && console.log('[LocalJS] Promise未完成，跳过'); " +
          "continue; " +
          "} " +
          "} " +
          "var n=norm(r); " +
          "if(n && n.length > 0) { " +
          "console.log && console.log('[LocalJS] 平台', p, '找到结果:', n.length, '条'); " +
          "return JSON.stringify(n); " +
          "} else { " +
          "console.log && console.log('[LocalJS] 平台', p, '无有效结果'); " +
          "} " +
          "} catch(e) { " +
          "console.warn && console.warn('[LocalJS] 平台搜索失败:', p, e); " +
          "} " +
          "} " +
          // 添加MusicFree格式支持
          "try { " +
          "if (typeof module !== 'undefined' && module && module.exports) { " +
          "var exp = module.exports; " +
          "if (exp.platform && (exp.search || exp.searchMusic)) { " +
          "console.log && console.log('[LocalJS] 检测到MusicFree格式，尝试搜索'); " +
          "var searchFn = exp.search || exp.searchMusic; " +
          "if (typeof searchFn === 'function') { " +
          "var query = { keyword: '" +
          escapedKw +
          "', page: " +
          page.toString() +
          ", type: 'music' }; " +
          "try { " +
          "var res = searchFn(query); " +
          "console.log && console.log('[LocalJS] MusicFree搜索结果类型:', typeof res); " +
          "console.log && console.log('[LocalJS] MusicFree搜索结果详情:', res); " +
          // 处理同步和异步结果
          "if (res && typeof res.then === 'function') { " +
          "console.log && console.log('[LocalJS] MusicFree返回Promise，尝试同步等待...'); " +
          "try { " +
          // 尝试检查Promise是否已经resolved
          "if (res.state === 'fulfilled') { " +
          "var n = norm(res.value); " +
          "if(n && n.length > 0) { " +
          "console.log && console.log('[LocalJS] Promise已完成，找到结果:', n.length, '条'); " +
          "return JSON.stringify(n); " +
          "} " +
          "} else { " +
          "console.log && console.log('[LocalJS] Promise未完成，状态:', res.state); " +
          "} " +
          "} catch(pe) { " +
          "console.warn && console.warn('[LocalJS] Promise处理失败:', pe); " +
          "} " +
          "} else { " +
          "var n = norm(res); " +
          "if(n && n.length > 0) { " +
          "console.log && console.log('[LocalJS] MusicFree找到结果:', n.length, '条'); " +
          "return JSON.stringify(n); " +
          "} " +
          "} " +
          "} catch(fe) { " +
          "console.warn && console.warn('[LocalJS] MusicFree函数调用失败:', fe); " +
          "} " +
          "} " +
          "} " +
          "} " +
          "} catch(e) { " +
          "console.warn && console.warn('[LocalJS] MusicFree格式搜索失败:', e); " +
          "} " +
          "console.log && console.log('[LocalJS] 所有平台都失败'); " +
          "return '[]'; " +
          "} catch(e) { " +
          "console.error && console.error('[LocalJS] 搜索代码执行失败:', e); " +
          "return '[]'; " +
          "} " +
          "})()";
      print('🔄 [LocalJsSource] 执行搜索JS代码...');
      try {
        final res = _rt.evaluate(js);
        result = res.stringResult;
        searchLog.add('标准函数执行成功');
        print('📤 [LocalJsSource] JS执行结果: $result');
      } catch (e) {
        searchLog.add('标准函数执行异常: $e');
        print('[XMC] ❌ [LocalJsSource] 标准搜索异常: $e');
        result = '[]';
      }
    } else {
      print('[XMC] ❌ [LocalJsSource] 标准函数未找到，开始混淆函数检测...');

      // 改进的混淆函数检测
      try {
        final obfuscatedScanJs = """
          (function() {
            var candidates = [];
            var global = this || window || {};
            
            // 扫描所有全局函数，寻找可能的搜索函数
            for (var key in global) {
              try {
                if (typeof global[key] === 'function') {
                  var funcStr = global[key].toString();
                  // 检查函数体是否包含音乐搜索相关的特征
                  if (funcStr.length > 100 && (
                    funcStr.indexOf('qq') >= 0 || 
                    funcStr.indexOf('netease') >= 0 || 
                    funcStr.indexOf('music') >= 0 ||
                    funcStr.indexOf('http') >= 0 ||
                    funcStr.indexOf('url') >= 0 ||
                    funcStr.indexOf('search') >= 0
                  )) {
                    candidates.push(key);
                  }
                }
              } catch(e) { 
                continue; 
              }
            }
            
            // 过滤显然无关或会导致异常的函数名
            var blacklist = { 'fetch':1,'XMLHttpRequest':1,'webkit':1,'axios':1,'require':1,'setTimeout':1,'setInterval':1,'atob':1,'btoa':1,'Promise':1,'Buffer':1,'CryptoJs':1,'he':1 };
            var filtered = candidates.filter(function(n){ return !blacklist[n] && String(n).toLowerCase().indexOf('axios') === -1; });
            return JSON.stringify(filtered);
          })()
        """;

        final obfuscatedResult = _rt.evaluate(obfuscatedScanJs);
        final obfuscatedCandidates =
            jsonDecode(obfuscatedResult.stringResult) as List;
        print(
          '[XMC] 🔍 [LocalJsSource] 发现混淆函数候选: ${obfuscatedCandidates.length} 个',
        );

        // 测试每个候选函数
        for (final candidate in obfuscatedCandidates) {
          try {
            print('🧪 [LocalJsSource] 测试混淆函数: $candidate');

            // 简单测试调用（排除 Promise/axios/原生 fetch 等）
            final testJs = """
              (function() {
                try {
                  if (String($candidate).toLowerCase() === 'axios') return 'skip';
                  var result = $candidate('qq', 'test', 1);
                  if (result && typeof result.then === 'function') {
                    return 'promise';
                  }
                  if (result && (Array.isArray(result) || (typeof result === 'object' && typeof result.length === 'number'))) {
                    return 'valid';
                  }
                  return 'invalid';
                } catch(e) {
                  return 'error';
                }
              })()
            """;

            final testResult = _rt.evaluate(testJs);
            if (testResult.stringResult == 'valid') {
              print('[XMC] ✅ [LocalJsSource] 找到可用的混淆函数: $candidate');
              workingFunction = candidate.toString();

              // 使用找到的混淆函数进行搜索
              final searchJs =
                  "(function(){ " +
                  "try { " +
                  "var plats=" +
                  jsonEncode(platforms) +
                  ";" +
                  "function norm(x){ " +
                  "try{ " +
                  "if(Array.isArray(x)) return x; " +
                  "if(x && Array.isArray(x.data)) return x.data; " +
                  "if(x && Array.isArray(x.list)) return x.list; " +
                  "if(x && Array.isArray(x.songs)) return x.songs; " +
                  "if(x && Array.isArray(x.result)) return x.result; " +
                  "if(typeof x === 'object' && x !== null) { " +
                  "var keys = Object.keys(x); " +
                  "for(var j=0; j<keys.length; j++) { " +
                  "if(Array.isArray(x[keys[j]])) return x[keys[j]]; " +
                  "} " +
                  "} " +
                  "}catch(e){console.warn && console.warn('obf norm error:', e);} " +
                  "return []; " +
                  "} " +
                  "for(var i=0;i<plats.length;i++){ " +
                  "try { " +
                  "var p=plats[i]; " +
                  "console.log && console.log('[LocalJS Obf] 尝试平台:', p); " +
                  "var r=$workingFunction(p,'" +
                  escapedKw +
                  "'," +
                  page.toString() +
                  "); " +
                  "console.log && console.log('[LocalJS Obf] 平台结果:', p, r); " +
                  "var n=norm(r); " +
                  "if(n && n.length > 0) { " +
                  "console.log && console.log('[LocalJS Obf] 找到结果:', n.length, '条'); " +
                  "return JSON.stringify(n); " +
                  "} " +
                  "} catch(e) { " +
                  "console.warn && console.warn('[LocalJS Obf] 平台搜索失败:', p, e); " +
                  "continue; " +
                  "} " +
                  "} " +
                  "console.log && console.log('[LocalJS Obf] 所有平台都失败'); " +
                  "return '[]'; " +
                  "} catch(e) { " +
                  "console.error && console.error('[LocalJS Obf] 搜索代码执行失败:', e); " +
                  "return '[]'; " +
                  "} " +
                  "})()";

              final searchRes = _rt.evaluate(searchJs);
              result = searchRes.stringResult;
              print('📤 [LocalJsSource] 混淆函数搜索结果: $result');
              break;
            } else {
              // 跳过 skip/promise/invalid/error
            }
          } catch (e) {
            print('[XMC] ⚠️ [LocalJsSource] 测试函数 $candidate 失败: $e');
            continue;
          }
        }

        if (workingFunction == null) {
          print('[XMC] ❌ [LocalJsSource] 所有混淆函数都不可用');
          result = '[]';
        }
      } catch (e) {
        print('[XMC] ⚠️ [LocalJsSource] 混淆函数检测异常: $e');
        result = '[]';
      }
    }

    final text = result;
    try {
      final dynamic data = jsonDecode(text);
      if (data is List) {
        return data
            .where((e) => e is Map)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
