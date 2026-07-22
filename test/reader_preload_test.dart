import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/views/reader_v2/core/reader_v2_scheduler.dart';
import 'package:joycomic/views/reader_v2/reader_v2_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reader v2 window uses configured preload count without whole chapter load',
    () async {
      SharedPreferences.setMockInitialValues({'preloadImageCount': 7});
      ReaderConf.instance.inject(await SharedPreferences.getInstance());
      final runtime = ReaderV2Runtime();
      addTearDown(runtime.dispose);

      final selected = [
        for (var index = 0; index < 45; index++)
          if (runtime.shouldLoad(index, 0)) index,
      ];

      expect(selected, List.generate(8, (index) => index));
      expect(selected.length, lessThan(45));
      expect(runtime.priorityFor(0, 0), ReaderV2Priority.visible);
      expect(runtime.priorityFor(1, 0), ReaderV2Priority.preload);
    },
  );

  test(
    'production viewports use the shared v2 page widget compatibility path',
    () {
      final vertical = File(
        'lib/views/reader/widgets/vertical_list/vertical_list.dart',
      ).readAsStringSync();
      final horizontal = File(
        'lib/views/reader/widgets/horizontal_list/horizontal_list.dart',
      ).readAsStringSync();
      final image = File(
        'lib/views/reader/widgets/reader_image.dart',
      ).readAsStringSync();

      expect(vertical, contains('ReaderImage('));
      expect(horizontal, contains('img_widget.ReaderImage('));
      expect(image, contains('ReaderV2PageImage('));
      expect(vertical, isNot(contains('ImagePreloadController')));
      expect(horizontal, isNot(contains('ImagePreloadController')));
      expect(horizontal, isNot(contains('createPageImageProvider(')));
      expect(vertical, isNot(contains('minCacheExtent:')));
    },
  );
}
