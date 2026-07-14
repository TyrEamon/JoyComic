/// 哔咔请求签名与请求头构造。
///
/// 哔咔服务端对每个请求做 HMAC-SHA256 签名校验：客户端用内置的 secret 字符串
/// 作为 HMAC 密钥，对"路径+时间戳+nonce+方法+apiKey"（全小写）做摘要，得到
/// 的十六进制串放入 `signature` 头。每次请求生成唯一 nonce 与当前时间戳。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// 哔咔 App 内置公钥（非机密，所有官方客户端共用）。
const picacgApiKey = 'C69BAF41DA5ABD1FFEDC6D2FEA56B';

/// 哔咔 App 内置 HMAC 密钥（与官方客户端一致，固定常量）。
const _picacgSecret =
    '~d}\$Q7\$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn';

/// 生成一次性的 nonce（UUID v1 去横杠，32 位十六进制）。
String createNonce() {
  final uuid = const Uuid().v1();
  return uuid.replaceAll('-', '');
}

/// 计算哔咔请求签名。
///
/// [path] 请求路径（已去除 base url 前缀，如 `comics/...` 或 `comics?page=1`）；
/// [nonce] 本次请求的 nonce；[time] 本次请求的时间戳（秒）；[method] 大写方法名。
/// 返回 HMAC-SHA256 的十六进制摘要字符串。
String createSignature(String path, String nonce, String time, String method) {
  final key = (path + time + nonce + method + picacgApiKey).toLowerCase();
  final hmac = Hmac(sha256, utf8.encode(_picacgSecret));
  final digest = hmac.convert(utf8.encode(key));
  return digest.toString();
}

/// 构造哔咔请求所需的全部头信息，封装为可直接用于 dio 的 [BaseOptions]。
///
/// [method] HTTP 方法；[token] 登录后的 JWT（未登录接口可传空串）；
/// [urlPath] 已去除 base url 前缀的路径，用于参与签名。
/// [channel]/[imageQuality] 可被用户设置覆盖的源内选项。
BaseOptions buildHeaders({
  required String method,
  required String token,
  required String urlPath,
  String channel = '3',
  String imageQuality = 'original',
}) {
  final nonce = createNonce();
  final time = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final signature = createSignature(urlPath, nonce, time, method.toUpperCase());

  return BaseOptions(
    receiveDataWhenStatusError: true,
    responseType: ResponseType.plain,
    headers: {
      'api-key': picacgApiKey,
      'accept': 'application/vnd.picacomic.com.v1+json',
      'app-channel': channel,
      'authorization': token,
      'time': time,
      'nonce': nonce,
      'app-version': '2.2.1.3.3.4',
      'app-uuid': 'defaultUuid',
      'image-quality': imageQuality,
      'app-platform': 'android',
      'app-build-version': '45',
      'Content-Type': 'application/json; charset=UTF-8',
      'user-agent': 'okhttp/3.8.1',
      'version': 'v1.4.1',
      'Host': 'picaapi.picacomic.com',
      'signature': signature,
    },
  );
}
