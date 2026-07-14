import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/app_data.dart';
import 'package:joycomic/foundation/preferences_store.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async => '.');
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  Future<AppData> initializeAppData(
    Map<String, Object> values, {
    PreferencesStore? preferenceStore,
  }) async {
    SharedPreferences.setMockInitialValues(values);
    await AppData.instance.init(preferenceStore: preferenceStore);
    return AppData.instance;
  }

  group('theme mode migration', () {
    test('legacy dark value migrates to the dark string mode', () async {
      final appData = await initializeAppData({'enableDarkMode': true});

      expect(appData.themeMode, ThemeMode.dark);
      expect(appData.prefs.getString('themeMode'), ThemeMode.dark.name);
      expect(appData.prefs.containsKey('enableDarkMode'), isFalse);
    });

    test('legacy light value migrates to the light string mode', () async {
      final appData = await initializeAppData({'enableDarkMode': false});

      expect(appData.themeMode, ThemeMode.light);
      expect(appData.prefs.getString('themeMode'), ThemeMode.light.name);
      expect(appData.prefs.containsKey('enableDarkMode'), isFalse);
    });

    test('missing current and legacy values defaults to system', () async {
      final appData = await initializeAppData({});

      expect(appData.themeMode, ThemeMode.system);
      expect(appData.themeNotifier.value, ThemeMode.system);
    });

    test('failed migration write retains the legacy key', () async {
      final store = _FakePreferencesStore({
        'enableDarkMode': true,
      }, writeResult: false);

      final appData = await initializeAppData({}, preferenceStore: store);

      expect(appData.themeMode, ThemeMode.dark);
      expect(store.containsKey('enableDarkMode'), isTrue);
      expect(store.containsKey('themeMode'), isFalse);
      expect(store.removedKeys, isEmpty);
    });
  });

  test('all theme modes persist by enum name', () async {
    final appData = await initializeAppData({});

    for (final mode in ThemeMode.values) {
      expect(await appData.setThemeMode(mode), isTrue);
      expect(appData.prefs.getString('themeMode'), mode.name);
    }
  });

  test(
    'changing theme mode notifies only after persistence succeeds',
    () async {
      final store = _FakePreferencesStore({
        'themeMode': ThemeMode.light.name,
      }, writeResult: false);
      final appData = await initializeAppData({}, preferenceStore: store);
      var notifications = 0;
      void listener() => notifications++;
      appData.themeNotifier.addListener(listener);
      addTearDown(() => appData.themeNotifier.removeListener(listener));

      final persisted = await appData.setThemeMode(ThemeMode.dark);

      expect(persisted, isFalse);
      expect(appData.themeMode, ThemeMode.light);
      expect(appData.themeNotifier.value, ThemeMode.light);
      expect(notifications, 0);
    },
  );

  test(
    'legacy dark mode API delegates to asynchronous theme persistence',
    () async {
      final appData = await initializeAppData({});

      expect(await appData.setDarkMode(true), isTrue);
      expect(appData.themeMode, ThemeMode.dark);
      expect(appData.enableDarkMode, isTrue);

      expect(await appData.setDarkMode(false), isTrue);
      expect(appData.themeMode, ThemeMode.light);
      expect(appData.enableDarkMode, isFalse);
    },
  );

  testWidgets('settings awaits and persists the three real theme modes', (
    tester,
  ) async {
    final appData = await initializeAppData({'themeMode': 'light'});

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));

    final selector = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(selector.selected, {ThemeMode.light});
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('封面动态取色'), findsNothing);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(appData.themeMode, ThemeMode.dark);
    expect(appData.prefs.getString('themeMode'), ThemeMode.dark.name);
  });
}

class _FakePreferencesStore implements PreferencesStore {
  _FakePreferencesStore(Map<String, Object> values, {this.writeResult = true})
    : _values = Map<String, Object>.of(values);

  final Map<String, Object> _values;
  final bool writeResult;
  final List<String> removedKeys = <String>[];

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

  Future<bool> _write(String key, Object value) async {
    if (writeResult) _values[key] = value;
    return writeResult;
  }

  @override
  Future<bool> setBool(String key, bool value) => _write(key, value);

  @override
  Future<bool> setDouble(String key, double value) => _write(key, value);

  @override
  Future<bool> setInt(String key, int value) => _write(key, value);

  @override
  Future<bool> setString(String key, String value) => _write(key, value);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _write(key, List<String>.of(value));

  @override
  Future<bool> remove(String key) async {
    removedKeys.add(key);
    if (writeResult) _values.remove(key);
    return writeResult;
  }
}
