/// WebDAV 客户端。
///
/// 基于 Dio 实现 WebDAV 协议的基础操作：
/// PROPFIND（列目录）、MKCOL（建文件夹）、PUT（上传）、GET（下载）、DELETE（删除）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// WebDAV 服务器连接配置。
class WebDavConfig {
  final String url;
  final String username;
  final String password;

  const WebDavConfig({
    required this.url,
    required this.username,
    required this.password,
  });

  String get baseUrl => url.endsWith('/') ? url : '$url/';
}

/// WebDAV 操作结果。
class WebDavResult<T> {
  final T? data;
  final String? error;
  bool get isSuccess => error == null;

  const WebDavResult({this.data, this.error});
}

/// WebDAV 客户端。
class WebDavClient {
  WebDavClient(this.config);
  final WebDavConfig config;
  late final Dio _dio = _createDio();

  Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    return dio;
  }

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';

  /// 测试连接（列出根目录）。
  Future<WebDavResult<bool>> testConnection() async {
    try {
      final res = await _dio.request(
        '',
        options: Options(
          method: 'PROPFIND',
          headers: {'Authorization': _authHeader, 'Depth': '0'},
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 207) {
        return const WebDavResult(data: true);
      }
      return WebDavResult(error: '状态码: ${res.statusCode}');
    } on DioException catch (e) {
      return WebDavResult(error: _dioError(e));
    }
  }

  /// 创建目录（递归）。
  Future<WebDavResult<bool>> createDirectory(String path) async {
    try {
      final parts = path.split('/').where((p) => p.isNotEmpty);
      var current = '';
      for (final part in parts) {
        current = '$current$part/';
        try {
          await _dio.request(
            current,
            options: Options(
              method: 'MKCOL',
              headers: {'Authorization': _authHeader},
            ),
          );
        } on DioException {
          // Existing parent directories may reject MKCOL; keep creating children.
          continue;
        }
      }
      return const WebDavResult(data: true);
    } on DioException catch (e) {
      return WebDavResult(error: _dioError(e));
    }
  }

  /// 上传文件。
  Future<WebDavResult<bool>> uploadFile({
    required String localPath,
    required String remotePath,
    void Function(int, int)? onProgress,
  }) async {
    try {
      await _dio.put(
        remotePath,
        data: File(localPath).openRead(),
        options: Options(
          headers: {
            'Authorization': _authHeader,
            'Content-Type': 'application/octet-stream',
          },
        ),
        onSendProgress: onProgress,
      );
      return const WebDavResult(data: true);
    } on DioException catch (e) {
      return WebDavResult(error: _dioError(e));
    }
  }

  /// 下载文件。
  Future<WebDavResult<File>> downloadFile({
    required String remotePath,
    required String localPath,
    void Function(int, int)? onProgress,
  }) async {
    try {
      await _dio.download(
        remotePath,
        localPath,
        options: Options(headers: {'Authorization': _authHeader}),
        onReceiveProgress: onProgress,
      );
      return WebDavResult(data: File(localPath));
    } on DioException catch (e) {
      return WebDavResult(error: _dioError(e));
    }
  }

  /// 列出目录内容。
  Future<WebDavResult<List<String>>> listDirectory(String path) async {
    try {
      final res = await _dio.request(
        path,
        options: Options(
          method: 'PROPFIND',
          headers: {'Authorization': _authHeader, 'Depth': '1'},
        ),
      );
      if (res.statusCode != 200 && res.statusCode != 207) {
        return WebDavResult(error: '状态码: ${res.statusCode}');
      }
      final body = res.data?.toString() ?? '';
      final hrefs = <String>[];
      final regExp = RegExp(r'<d:href>(.*?)</d:href>', caseSensitive: false);
      for (final m in regExp.allMatches(body)) {
        hrefs.add(m.group(1) ?? '');
      }
      return WebDavResult(data: hrefs);
    } on DioException catch (e) {
      return WebDavResult(error: _dioError(e));
    }
  }

  String _dioError(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout => '连接超时',
    DioExceptionType.receiveTimeout => '接收超时',
    DioExceptionType.badResponse => '服务器错误: ${e.response?.statusCode}',
    _ => e.message ?? '未知错误',
  };
}
