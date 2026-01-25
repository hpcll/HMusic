import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../errors/app_exception.dart';
import '../constants/app_constants.dart';

class DioClient {
  late final Dio _dio;
  final String _baseUrl;

  // 公共getter，供其他类访问baseUrl
  String get baseUrl => _baseUrl;

  DioClient({
    required String baseUrl,
    required String username,
    required String password,
  }) : _baseUrl = baseUrl {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: Duration(seconds: AppConstants.connectTimeout),
        receiveTimeout: Duration(seconds: AppConstants.receiveTimeout),
        sendTimeout: Duration(seconds: AppConstants.sendTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    final credentials = base64Encode(utf8.encode('$username:$password'));
    _dio.options.headers['Authorization'] = 'Basic $credentials';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          print('🔵 请求: ${options.method} ${options.baseUrl}${options.path}');
          if (options.queryParameters.isNotEmpty) {
            print('🔵 查询参数: ${options.queryParameters}');
          }
          if (options.data != null) {
            print('🔵 请求体完整数据: ${options.data}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          print(
            '🟢 响应: ${response.statusCode} ${response.requestOptions.path}',
          );
          print('🟢 响应数据: ${response.data}');
          handler.next(response);
        },
        onError: (error, handler) {
          print('🔴 网络错误详情:');
          print('🔴 错误类型: ${error.type}');
          print('🔴 错误消息: ${error.message}');
          print('🔴 响应状态码: ${error.response?.statusCode}');
          print('🔴 响应数据: ${error.response?.data}');
          print('🔴 请求URL: ${error.requestOptions.uri}');

          final exception = _handleError(error);
          handler.reject(
            DioException(
              requestOptions: error.requestOptions,
              error: exception,
              message: exception.message,
            ),
          );
        },
      ),
    );
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  // Convenience for endpoints returning plain text (e.g., log files)
  Future<Response<String>> getPlain(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get<String>(
        path,
        queryParameters: queryParameters,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  AppException _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException('连接超时，请检查网络连接。服务器地址: $_baseUrl');

      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        switch (statusCode) {
          case 401:
            return const AuthException('认证失败，请检查用户名密码');
          case 404:
            return ServerException('接口不存在: ${error.requestOptions.path}');
          case 422:
            return const ValidationException('请求参数错误');
          case 500:
            return const ServerException('服务器内部错误');
          default:
            return ServerException('HTTP错误: $statusCode');
        }

      case DioExceptionType.cancel:
        return const NetworkException('请求已取消');

      case DioExceptionType.connectionError:
        return NetworkException('无法连接到服务器: $_baseUrl，请检查服务器是否运行');

      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return NetworkException('网络连接失败，无法访问: $_baseUrl');
        }
        return NetworkException('未知错误: ${error.message}');

      default:
        return NetworkException('网络错误: ${error.message}');
    }
  }
}
