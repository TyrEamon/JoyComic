// 纯 Dart 单元测试：验证核心加密/分段逻辑的正确性与确定性。
// 不依赖 Flutter 运行时，任何装了 dart 的环境可执行 `flutter test` 或 `dart test`。

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/picacg/picacg_headers.dart';
import 'package:joycomic/foundation/jm_image_recombine.dart';

void main() {
  group('哔咔请求签名', () {
    test('相同输入应产生相同签名（确定性）', () {
      final a = createSignature(
        'comics/1/eps?page=1',
        '4ce7a7aa759b40f794d189a88b84aba8',
        '1700000000',
        'GET',
      );
      final b = createSignature(
        'comics/1/eps?page=1',
        '4ce7a7aa759b40f794d189a88b84aba8',
        '1700000000',
        'GET',
      );
      expect(a, equals(b));
    });

    test('签名为 64 位十六进制字符串', () {
      final sig = createSignature(
        'comics',
        'nonce'.padLeft(32, '0'),
        '1700000001',
        'POST',
      );
      expect(sig.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(sig), isTrue);
    });

    test('输入不同则签名不同', () {
      final a = createSignature('comics', '0'.padLeft(32, 'a'), '1', 'GET');
      final b = createSignature('comics', '0'.padLeft(32, 'b'), '1', 'GET');
      expect(a, isNot(equals(b)));
    });
  });

  group('禁漫图片分段数', () {
    const scramble = '220980';

    test('旧作（epsId < scrambleId）不分割 → 0', () {
      expect(getSegmentationNum('100', scramble, 'img1'), 0);
    });

    test('中段固定 10 段', () {
      expect(getSegmentationNum('268000', scramble, 'cover01'), 10);
    });

    test('最新段落在 % 8 分支 → 2~16 之间的偶数', () {
      for (var eps = 421927; eps < 422000; eps++) {
        final n = getSegmentationNum(eps.toString(), scramble, 'pic$eps');
        expect(n >= 2 && n <= 16, isTrue);
        expect(n % 2, 0);
      }
    });

    test('中后段落在 % 10 分支 → 2~20 之间的偶数', () {
      for (var eps = 268850; eps <= 421926; eps += 1000) {
        final n = getSegmentationNum(eps.toString(), scramble, 'x$eps');
        expect(n >= 2 && n <= 20, isTrue);
        expect(n % 2, 0);
      }
    });
  });
}
