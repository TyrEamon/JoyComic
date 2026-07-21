import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String pipeline;

  setUpAll(() {
    pipeline = File('azure-pipelines.yml').readAsStringSync();
  });

  test('Azure IPA pipeline is manual-only and runs on hosted macOS', () {
    expect(pipeline, contains('trigger: none'));
    expect(pipeline, contains('pr: none'));
    expect(pipeline, contains("vmImage: 'macOS-latest'"));
    expect(pipeline, contains('fetchDepth: 0'));
  });

  test('Azure IPA pipeline installs Flutter stable without an extension', () {
    expect(pipeline, contains('--branch stable'));
    expect(pipeline, contains('flutter doctor -v'));
    expect(pipeline, isNot(contains('FlutterInstall')));
  });

  test('Azure IPA pipeline builds and publishes an unsigned IPA', () {
    expect(pipeline, contains('CODE_SIGNING_ALLOWED=NO'));
    expect(pipeline, contains('CODE_SIGNING_REQUIRED=NO'));
    expect(pipeline, contains('flutter build ios --release'));
    expect(pipeline, contains('joycomic-unsigned.ipa'));
    expect(pipeline, contains('PublishPipelineArtifact@1'));
    expect(pipeline, contains("artifact: 'joycomic-unsigned-ipa'"));
  });
}
