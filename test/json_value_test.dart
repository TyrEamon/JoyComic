import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/json_value.dart';

void main() {
  group('jsonInt', () {
    test('accepts server numeric variants', () {
      expect(jsonInt(12), 12);
      expect(jsonInt('12'), 12);
      expect(jsonInt(12.8), 12);
      expect(jsonInt(null, fallback: 7), 7);
      expect(jsonInt('bad', fallback: 3), 3);
    });
  });

  group('jsonString', () {
    test('uses an explicit default for null and stringifies scalars', () {
      expect(jsonString(null), '');
      expect(jsonString(null, fallback: 'unknown'), 'unknown');
      expect(jsonString('title'), 'title');
      expect(jsonString(42), '42');
      expect(jsonString(true), 'true');
    });
  });

  group('jsonBool', () {
    test('accepts boolean, numeric, and string variants', () {
      expect(jsonBool(true), isTrue);
      expect(jsonBool(1), isTrue);
      expect(jsonBool('true'), isTrue);
      expect(jsonBool(false), isFalse);
      expect(jsonBool(0), isFalse);
      expect(jsonBool('false'), isFalse);
      expect(jsonBool(null, fallback: true), isTrue);
      expect(jsonBool('unknown', fallback: true), isTrue);
    });
  });

  group('jsonStringList', () {
    test('drops null and structured values and stringifies scalars', () {
      expect(
        jsonStringList(['a', 2, true, null, {'nested': 'value'}, ['nested']]),
        ['a', '2', 'true'],
      );
      expect(jsonStringList(null), isEmpty);
      expect(jsonStringList('not a list'), isEmpty);
    });
  });

  group('safe JSON structures', () {
    test('jsonList returns lists and defaults invalid values to empty', () {
      final source = <Object?>['a', 2, null];
      expect(jsonList(source), same(source));
      expect(jsonList(null), isEmpty);
      expect(jsonList({'not': 'a list'}), isEmpty);
    });

    test('jsonMap keeps string keys and defaults invalid values to empty', () {
      final source = <Object?, Object?>{
        'id': '42',
        'count': 3,
        7: 'ignored',
      };
      expect(jsonMap(source), {'id': '42', 'count': 3});
      expect(jsonMap(null), isEmpty);
      expect(jsonMap(['not a map']), isEmpty);
    });
  });
}
