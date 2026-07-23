import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/video_backend.dart';

void main() {
  test('iOS selects and registers FVP only for iOS', () {
    dynamic receivedOptions;

    final backend = registerVideoBackend(
      platform: TargetPlatform.iOS,
      registrar: ({dynamic options}) => receivedOptions = options,
    );

    expect(backend, VideoBackend.fvp);
    expect(receivedOptions, <String, dynamic>{
      'platforms': <String>['ios'],
    });
  });

  test('non-iOS platforms retain the official backend', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      var registerCalls = 0;
      final backend = registerVideoBackend(
        platform: platform,
        registrar: ({dynamic options}) => registerCalls++,
      );

      expect(backend, VideoBackend.official, reason: platform.name);
      expect(registerCalls, 0, reason: platform.name);
    }
  });

  test('FVP registration failure preserves the official backend', () {
    final backend = registerVideoBackend(
      platform: TargetPlatform.iOS,
      registrar: ({dynamic options}) => throw StateError('register failed'),
    );

    expect(backend, VideoBackend.official);
  });

  test('main initializes logging before video backend registration', () {
    final source = File('lib/main.dart').readAsStringSync();
    final logIndex = source.indexOf('await Log.initialize();');
    final backendIndex = source.indexOf('registerVideoBackend();');

    expect(logIndex, greaterThanOrEqualTo(0));
    expect(backendIndex, greaterThan(logIndex));
    expect(backendIndex, lessThan(source.indexOf('runApp(')));
  });
}
