import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/picacg.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/res.dart';

void main() {
  test(
    'Picacg home loads three independent sections with matching queries',
    () async {
      final calls = <String>[];
      final result = await loadPicacgHomeSections((sort) async {
        calls.add(sort);
        return Res<List<BaseComic>>(<BaseComic>[_Comic(sort)]);
      });

      expect(calls, <String>['dd', 'ld', 'ua']);
      expect(result.error, isFalse);
      expect(result.data.map((section) => section.key), <String>[
        'latest',
        'popular',
        'recommended',
      ]);
      expect(result.data.map((section) => section.moreQuery?.sort), <String>[
        'dd',
        'ld',
        'ua',
      ]);
      expect(
        result.data.map((section) => section.moreQuery?.categoryKey),
        everyElement(''),
      );
    },
  );

  test(
    'Picacg home retains successful sections after a local failure',
    () async {
      final result = await loadPicacgHomeSections((sort) async {
        if (sort == 'ld') return const Res.error('popular failed');
        return Res<List<BaseComic>>(<BaseComic>[_Comic(sort)]);
      });

      expect(result.error, isFalse);
      expect(result.data.map((section) => section.key), <String>[
        'latest',
        'recommended',
      ]);
    },
  );

  test('Picacg home reports an error when every section fails', () async {
    final result = await loadPicacgHomeSections(
      (sort) async => Res<List<BaseComic>>.error('$sort failed'),
    );

    expect(result.error, isTrue);
    expect(result.errorMessage, contains('dd failed'));
    expect(result.errorMessage, contains('ld failed'));
    expect(result.errorMessage, contains('ua failed'));
  });
}

class _Comic extends BaseComic {
  const _Comic(this.id);

  @override
  final String id;

  @override
  String get title => id;

  @override
  String get subTitle => '';

  @override
  String get cover => '';

  @override
  List<String> get tags => const <String>[];

  @override
  String get description => '';
}
