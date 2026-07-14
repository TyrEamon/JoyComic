import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/app_data.dart';
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

  Future<AppData> initializeAppData(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await AppData.instance.init();
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
  });

  test('all theme modes persist by enum name', () async {
    final appData = await initializeAppData({});

    for (final mode in ThemeMode.values) {
      appData.themeMode = mode;
      expect(appData.prefs.getString('themeMode'), mode.name);
    }
  });

  test('changing theme mode notifies listeners immediately', () async {
    final appData = await initializeAppData({});
    var notifications = 0;
    void listener() => notifications++;
    appData.themeNotifier.addListener(listener);
    addTearDown(() => appData.themeNotifier.removeListener(listener));

    appData.themeMode = ThemeMode.dark;

    expect(appData.themeNotifier.value, ThemeMode.dark);
    expect(notifications, 1);
  });

  test('legacy dark mode accessors delegate to theme mode', () async {
    final appData = await initializeAppData({});

    appData.enableDarkMode = true;
    expect(appData.themeMode, ThemeMode.dark);
    expect(appData.enableDarkMode, isTrue);

    appData.enableDarkMode = false;
    expect(appData.themeMode, ThemeMode.light);
    expect(appData.enableDarkMode, isFalse);
  });

  testWidgets('settings offers and persists the three real theme modes', (
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
    await tester.pump();

    expect(appData.themeMode, ThemeMode.dark);
    expect(appData.prefs.getString('themeMode'), ThemeMode.dark.name);
  });
}
