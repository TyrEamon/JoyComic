import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/views/reader/state/read_mode.dart';
import 'package:joycomic/views/settings/reader_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> injectReaderConf(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    ReaderConf.instance.inject(prefs);
    return prefs;
  }

  test('ReaderConf reads persisted supported settings', () async {
    await injectReaderConf({
      'readMode': ReadMode.rightToLeft.name,
      'enableGesture': false,
      'enablePageAnimation': false,
      'preloadImageCount': 6,
      'showPageNumbers': false,
      'menuLocked': true,
    });

    final conf = ReaderConf.instance;
    expect(conf.readMode, ReadMode.rightToLeft);
    expect(conf.enableGesture, isFalse);
    expect(conf.enablePageAnimation, isFalse);
    expect(conf.preloadImageCount, 6);
    expect(conf.showPageNumbers, isFalse);
    expect(conf.menuLocked, isTrue);
  });

  test('ReaderConf writes supported settings immediately', () async {
    final prefs = await injectReaderConf({});
    final conf = ReaderConf.instance;

    conf.readMode = ReadMode.doubleRightToLeft;
    conf.enableGesture = false;
    conf.enablePageAnimation = false;
    conf.preloadImageCount = 8;
    conf.showPageNumbers = false;
    conf.menuLocked = true;

    expect(prefs.getString('readMode'), ReadMode.doubleRightToLeft.name);
    expect(prefs.getBool('enableGesture'), isFalse);
    expect(prefs.getBool('enablePageAnimation'), isFalse);
    expect(prefs.getInt('preloadImageCount'), 8);
    expect(prefs.getBool('showPageNumbers'), isFalse);
    expect(prefs.getBool('menuLocked'), isTrue);
  });

  testWidgets('reader settings initialize every control from ReaderConf', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await injectReaderConf({
      'readMode': ReadMode.rightToLeft.name,
      'enableGesture': false,
      'enablePageAnimation': false,
      'preloadImageCount': 6,
      'showPageNumbers': false,
      'menuLocked': true,
    });

    await tester.pumpWidget(const MaterialApp(home: ReaderSettingsPage()));

    final gestureSwitch = tester.widget<Switch>(
      find.byKey(const Key('reader-enable-gesture')),
    );
    final animationSwitch = tester.widget<Switch>(
      find.byKey(const Key('reader-page-animation')),
    );
    final pageNumberSwitch = tester.widget<Switch>(
      find.byKey(const Key('reader-show-page-numbers')),
    );
    final autoHideSwitch = tester.widget<Switch>(
      find.byKey(const Key('reader-auto-hide-toolbar')),
    );

    expect(gestureSwitch.value, isFalse);
    expect(animationSwitch.value, isFalse);
    expect(pageNumberSwitch.value, isFalse);
    expect(autoHideSwitch.value, isFalse);
    expect(
      tester
          .widget<Icon>(find.byKey(const Key('reader-mode-rightToLeft')))
          .icon,
      Icons.radio_button_checked,
    );
    expect(
      tester.widget<InkWell>(find.byKey(const Key('reader-preload-6'))).onTap,
      isNotNull,
    );
    expect(find.textContaining('音量键'), findsNothing);
    expect(find.text('图片质量'), findsNothing);
  });

  testWidgets('reader settings persist changes as soon as controls change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final prefs = await injectReaderConf({});

    await tester.pumpWidget(const MaterialApp(home: ReaderSettingsPage()));

    await tester.tap(find.text('双页 右→左'));
    await tester.tap(find.byKey(const Key('reader-preload-8')));
    await tester.tap(find.byKey(const Key('reader-enable-gesture')));
    await tester.tap(find.byKey(const Key('reader-page-animation')));
    await tester.tap(find.byKey(const Key('reader-show-page-numbers')));
    await tester.tap(find.byKey(const Key('reader-auto-hide-toolbar')));
    await tester.pump();

    expect(prefs.getString('readMode'), ReadMode.doubleRightToLeft.name);
    expect(prefs.getInt('preloadImageCount'), 8);
    expect(prefs.getBool('enableGesture'), isFalse);
    expect(prefs.getBool('enablePageAnimation'), isFalse);
    expect(prefs.getBool('showPageNumbers'), isFalse);
    expect(prefs.getBool('menuLocked'), isTrue);
  });
}
