/// 禁漫请求头与响应解密。
///
/// 禁漫 API 鉴权与哔咔不同：不用 HMAC 签名，而是用 `token = md5(时间戳 + 鉴权盐)`
/// 作为头，配合 `tokenparam = "时间戳,App版本"`。响应体的业务数据是经
/// AES-ECB 加密后再 base64 编码的字符串，客户端需用 `md5(时间戳 + 数据盐)`
/// 作为 AES 密钥进行 ECB 解密，再 UTF8 解码并裁掉尾部乱码。
library jm_headers;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/ecb.dart';

/// 鉴权 token 盐（用于 `md5(time + 该盐)`）。
const _jmAuthKey = '18comicAPPContent';

/// 响应数据解密盐（用于 `md5(time + 该盐)` 作为 AES 密钥）。
const jmDataSecret = '185Hcomic3PAPP7R';

/// 动态域名解密盐（字节序列，复原为字符串后用于解密域名清单 TXT）。
const _domainSecret = <int>[
  100, 105, 111, 115, 102, 106, 99, 107, 119, 112, 113, 112, 100, 102, 106,
  107, 118, 110, 113, 81, 106, 115, 105, 107
];

String get domainSecretString => String.fromCharCodes(_domainSecret);

/// 客户端伪装标识与 UA。
const _jmPkgName = 'com.example.app';
const jmAppVersion = '1.6.3';
const _jmUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.0.0 Mobile Safari/537.36';

/// 基础请求头（非加密接口通用部分）。
Map<String, String> baseHeaders() => {
      'Accept': '*/*',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Connection': 'keep-alive',
      'Origin': 'https://localhost',
      'Referer': 'https://localhost/',
      'Sec-Fetch-Dest': 'empty',
      'Sec-Fetch-Mode': 'cors',
      'Sec-Fetch-Site': 'cross-site',
      'X-Requested-With': _jmPkgName,
    };

/// 构造禁漫 API 请求的 [BaseOptions]。
///
/// [time] 当前秒级时间戳（与 token 计算保持同一值，后续响应解密也复用此值）；
/// [post] 是否为 POST（决定 Content-Type）；[byte] 是否以字节方式接收响应。
BaseOptions buildApiOptions(int time, {bool post = false, bool byte = true}) {
  final token = md5.convert(utf8.encode('$time$_jmAuthKey'));
  return BaseOptions(
    receiveDataWhenStatusError: true,
    connectTimeout: const Duration(seconds: 8),
    responseType: byte ? ResponseType.bytes : null,
    headers: {
      ...baseHeaders(),
      'Authorization': 'Bearer',
      'Sec-Fetch-Storage-Access': 'active',
      'token': token.toString(),
      'tokenparam': '$time,$jmAppVersion',
      'user-agent': _jmUserAgent,
      if (post) 'Content-Type': 'application/x-www-form-urlencoded',
    },
  );
}

/// 图片请求头（仿浏览器图片请求）。
Map<String, String> imageHeaders() => {
      ...baseHeaders(),
      'user-agent': _jmUserAgent,
      'Sec-Fetch-Dest': 'image',
      'Sec-Fetch-Mode': 'no-cors',
      'Sec-Fetch-Site': 'cross-site',
    };

/// 解密禁漫 API 响应体中的加密 data 字段。
///
/// [input] 响应里 base64 编码的密文字符串；[secret] 形如 `"$time$jmDataSecret"`。
/// 流程：取 `md5(secret)` 的十六进制字符串（32 字符）的 UTF8 字节作为
/// AES 密钥（恰好 32 字节，对应 AES-256） → base64 解码 → AES-ECB 分块解密 →
/// UTF8 解码 → 裁掉末尾乱码（保留到最后一个 `}` 或 `]`）。
String convertData(String input, String secret) {
  final keyHex = md5.convert(utf8.encode(secret));
  // md5 摘要为 32 位十六进制字符串，取其 UTF8 字节作为 AES 密钥（32 字节 = AES-256）。
  final keyBytes = utf8.encode(keyHex.toString());
  final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(keyBytes));

  final data = base64Decode(input);
  final padded = Uint8List(data.length);
  var offset = 0;
  while (offset < data.length) {
    offset += cipher.processBlock(data, offset, padded, offset);
  }

  final res = utf8.decode(padded);

  var i = res.length - 1;
  for (; i >= 0; i--) {
    if (res[i] == '}' || res[i] == ']') break;
  }
  return res.substring(0, i + 1);
}
