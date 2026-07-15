import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/foundation/preferences_store.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/reader/state/read_mode.dart';
import 'package:joycomic/views/settings/reader_settings_page.dart';
import 'package:joycomic/views/settings/settings_page.dart';
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

  test('ReaderConf flush waits until pending writes reach storage', () async {
    final store = _DelayedPreferencesStore();
    final conf = ReaderConf.instance..injectStore(store);

    conf.preloadImageCount = 8;
    var flushed = false;
    final flush = conf.flushPendingWrites().then((value) {
      flushed = true;
      return value;
    });
    await Future<void>.delayed(Duration.zero);

    expect(flushed, isFalse);
    expect(store.getInt('preloadImageCount'), isNull);

    store.completeWrites();

    expect(await flush, isTrue);
    expect(store.getInt('preloadImageCount'), 8);
  });

  test('ReaderConf writes supported settings and can flush them', () async {
    final prefs = await injectReaderConf({});
    final conf = ReaderConf.instance;

    conf.readMode = ReadMode.doubleRightToLeft;
    conf.enableGesture = false;
    conf.enablePageAnimation = false;
    conf.preloadImageCount = 8;
    conf.showPageNumbers = false;
    conf.menuLocked = true;

    expect(await conf.flushPendingWrites(), isTrue);
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

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ReaderSettingsPage()),
    );

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
    final selectedPreload = tester.widget<Container>(
      find.byKey(const Key('reader-preload-container-6')),
    );
    final selectedDecoration = selectedPreload.decoration as BoxDecoration;
    expect(selectedDecoration.gradient, isNull);
    expect(
      selectedDecoration.color,
      AppTheme.light().colorScheme.primaryContainer,
    );
    expect(find.textContaining('音量键'), findsNothing);
    expect(find.text('图片质量'), findsNothing);
  });

  testWidgets('reader settings await persistence before updating controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _DelayedPreferencesStore();
    ReaderConf.instance.injectStore(store);

    await tester.pumpWidget(const MaterialApp(home: ReaderSettingsPage()));
    await tester.tap(find.byKey(const Key('reader-preload-8')));
    await tester.pump();

    expect(store.getInt('preloadImageCount'), isNull);
    store.completeWrites();
    await tester.pumpAndSettle();

    expect(store.getInt('preloadImageCount'), 8);
  });

  testWidgets('settings refreshes reader mode summary after returning', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await injectReaderConf({});
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        GoRoute(
          path: '/settings/reader',
          builder: (_, _) => const ReaderSettingsPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('阅读设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('双页 右→左'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('双页从右到左'), findsOneWidget);
  });
}

class _DelayedPreferencesStore implements PreferencesStore {
  final Map<String, Object> _values = <String, Object>{};
  final List<({String key, Object value, Completer<bool> completer})> _pending =
      [];

  void completeWrites() {
    for (final write in List.of(_pending)) {
      _values[write.key] = write.value;
      write.completer.complete(true);
      _pending.remove(write);
    }
  }

  Future<bool> _delay(String key, Object value) {
    final completer = Completer<bool>();
    _pending.add((key: key, value: value, completer: completer));
    return completer.future;
  }

  @override
  bool containsKey(String key) => _values.containsKey(key);
  @override
  bool? getBool(String key) => _values[key] as bool?;
  @override
  double? getDouble(String key) => _values[key] as double?;
  @override
  int? getInt(String key) => _values[key] as int?;
  @override
  String? getString(String key) => _values[key] as String?;
  @override
  List<String>? getStringList(String key) =>
      (_values[key] as List<String>?)?.toList();
  @override
  Future<bool> remove(String key) => _delay(key, Object());
  @override
  Future<bool> setBool(String key, bool value) => _delay(key, value);
  @override
  Future<bool> setDouble(String key, double value) => _delay(key, value);
  @override
  Future<bool> setInt(String key, int value) => _delay(key, value);
  @override
  Future<bool> setString(String key, String value) => _delay(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _delay(key, List<String>.of(value));
}
