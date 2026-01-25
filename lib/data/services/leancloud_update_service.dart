import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LeanCloudUpdateService {
  final Dio _dio;
  final String baseUrl;
  final String appId;
  final String appKey;

  LeanCloudUpdateService._(this._dio, this.baseUrl, this.appId, this.appKey);

  static Future<LeanCloudUpdateService?> create() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('lc_base_url');
    final appId = prefs.getString('lc_app_id');
    final appKey = prefs.getString('lc_app_key');
    if (baseUrl == null || appId == null || appKey == null) return null;

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'X-LC-Id': appId,
        'X-LC-Key': appKey,
        'Content-Type': 'application/json',
      },
    ));
    return LeanCloudUpdateService._(dio, baseUrl, appId, appKey);
  }

  Future<List<Map<String, dynamic>>> fetchConfig() async {
    final resp = await _dio.get('/1.1/classes/AppConfig');
    final data = resp.data;
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    final results = (data['results'] as List?) ?? [];
    return results.cast<Map<String, dynamic>>();
  }
}
