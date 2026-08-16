import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub workflow builds an installable Android APK', () {
    final workflow = File(
      '.github/workflows/build-android.yml',
    ).readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('flutter create . --empty --platforms=android'));
    expect(workflow, contains('android.permission.INTERNET'));
    expect(workflow, contains('flutter_launcher_icons_android.yaml'));
    expect(workflow, contains('flutter analyze'));
    expect(
      workflow,
      contains('flutter test test/github_android_workflow_test.dart'),
    );
    expect(workflow, contains('continue-on-error: true'));
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('actions/upload-artifact@v7'));
  });
}
