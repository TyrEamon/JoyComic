import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/source_state.dart';
import 'package:joycomic/views/settings/source_settings_page.dart';

void main() {
  testWidgets(
    'JM source settings restore and persist real selections and speeds',
    (tester) async {
      final state = _FakeJmState(
        selectedShuntKey: 2,
        preferredDomain: 'jmcomic2.me',
        shunts: const <JmShunt>[
          JmShunt(key: 1, title: '线路一'),
          JmShunt(key: 2, title: '线路二'),
        ],
      );
      final selected = <int>[];
      final testedDomains = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: SourceSettingsPage(
            sourceKey: 'jm',
            jmState: state,
            testShunts: (_) async => const <JmShuntSpeed>[
              JmShuntSpeed(
                key: 0,
                title: '快速通道',
                latency: 21,
                imgHost: 'express.example',
              ),
              JmShuntSpeed(key: 1, title: '线路一', latency: -1, imgHost: ''),
              JmShuntSpeed(
                key: 2,
                title: '线路二',
                latency: 42,
                imgHost: 'line2.example',
              ),
            ],
            selectShunt: (key) async {
              selected.add(key);
              state.setSelectedShuntKey(key);
              return true;
            },
            testDomain: (domain) async {
              testedDomains.add(domain);
              return domain == 'jmcomic1.cc' ? -1 : 35;
            },
          ),
        ),
      );

      expect(find.byKey(const Key('jm-shunt-selected-2')), findsOneWidget);
      expect(
        find.byKey(const Key('jm-domain-selected-jmcomic2.me')),
        findsOneWidget,
      );

      await tester.tap(find.text('线路一'));
      await tester.pump();
      expect(selected, <int>[1]);
      expect(state.selectedShuntKey, 1);

      await tester.tap(find.text('开始测速'));
      await tester.pump();
      await tester.pump();

      expect(find.text('21ms'), findsOneWidget);
      expect(find.text('42ms'), findsOneWidget);
      expect(find.text('失败'), findsWidgets);
      expect(testedDomains.toSet(), containsAll(jmBuiltInDomains));

      await tester.scrollUntilVisible(
        find.text('jmcomic3.pw'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('jmcomic3.pw'));
      await tester.pump();
      await tester.tap(find.text('jmcomic3.pw').hitTestable());
      await tester.pump();
      expect(state.preferredDomain, 'jmcomic3.pw');
      expect(state.apiBaseUrl, 'https://jmcomic3.pw');
    },
  );

  testWidgets('Picacg API base selection is restored and persisted', (
    tester,
  ) async {
    final state = _FakePicacgState('https://picaapi.picacomic.com');
    await tester.pumpWidget(
      MaterialApp(
        home: SourceSettingsPage(sourceKey: 'picacg', picacgState: state),
      ),
    );

    expect(
      find.byKey(const Key('pica-domain-selected-picacomic')),
      findsOneWidget,
    );
    await tester.tap(find.text('go2778 中转（默认）'));
    await tester.pump();

    expect(state.apiBaseUrl, 'https://picaapi.go2778.com');
    expect(
      find.byKey(const Key('pica-domain-selected-go2778')),
      findsOneWidget,
    );
  });
}

class _FakeJmState implements JmState {
  _FakeJmState({
    required this.selectedShuntKey,
    required this.preferredDomain,
    required this.shunts,
  }) : apiBaseUrl = 'https://$preferredDomain';

  @override
  String avs = '';
  @override
  String apiBaseUrl;
  @override
  String imageBaseUrl = '';
  @override
  String preferredDomain;
  @override
  List<JmShunt> shunts;
  @override
  int selectedShuntKey;
  @override
  String? username;

  @override
  Future<void> clearAvs() async => avs = '';
  @override
  List<String>? getAccount() => null;
  @override
  Future<bool> reLogin() async => true;
  @override
  Future<void> setAvs(String value) async => avs = value;
  @override
  void setApiBaseUrl(String url) => apiBaseUrl = url;
  @override
  void setImageBaseUrl(String url) => imageBaseUrl = url;
  @override
  void setPreferredDomain(String domain) => preferredDomain = domain;
  @override
  void setSelectedShuntKey(int key) => selectedShuntKey = key;
  @override
  void setShunts(List<JmShunt> value) => shunts = value;
}

class _FakePicacgState implements PicacgState {
  _FakePicacgState(this.apiBaseUrl);

  @override
  String apiBaseUrl;
  @override
  String get channel => '3';
  @override
  String get imageQuality => 'original';
  @override
  String get token => '';
  @override
  List<String>? getAccount() => null;
  @override
  Future<bool> reLogin() async => true;
  @override
  void setApiBaseUrl(String url) => apiBaseUrl = url;
}
