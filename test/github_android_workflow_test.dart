import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GitHub workflow builds an installable Android APK', () {
    final workflow = File(
      '.github/workflows/build-android.yml',
    ).readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('contents: write'));
    expect(workflow, contains('flutter create . --empty --platforms=android'));
    expect(
      workflow,
      contains(
        '--org io.github.xiaoqi419 --project-name joycomic',
      ),
    );
    expect(workflow, contains('android.permission.INTERNET'));
    expect(workflow, contains('flutter_launcher_icons_android.yaml'));
    expect(workflow, contains('flutter analyze'));
    expect(
      workflow,
      contains('test/github_android_workflow_test.dart'),
    );
    expect(workflow, contains('test/android_font_fallback_test.dart'));
    expect(workflow, contains('test/detail_header_overlap_test.dart'));
    expect(workflow, contains('test/detail_download_action_test.dart'));
    expect(workflow, contains('test/reader_v2_route_test.dart'));
    expect(workflow, contains('test/collection_stats_test.dart'));
    expect(workflow, contains('continue-on-error: true'));
    expect(workflow, contains('secrets.ANDROID_KEYSTORE_BASE64'));
    expect(workflow, contains('secrets.ANDROID_KEYSTORE_PASSWORD'));
    expect(workflow, contains('secrets.ANDROID_KEY_ALIAS'));
    expect(workflow, contains('secrets.ANDROID_KEY_PASSWORD'));
    expect(workflow, contains('joycomic-release.jks'));
    expect(workflow, contains('storeType=JKS'));
    expect(workflow, contains('Android signing secrets unavailable'));
    expect(workflow, contains('Verify Android release keystore'));
    expect(workflow, contains('keytool -list'));
    expect(workflow, contains('-storepass:env ANDROID_KEYSTORE_PASSWORD'));
    expect(
      workflow,
      contains('signingConfigs.getByName("release")'),
    );
    expect(workflow, contains('flutter build apk --release'));
    expect(workflow, contains('github.run_number'));
    expect(workflow, contains('Resolve next release version'));
    expect(workflow, contains('git tag --list'));
    expect(workflow, contains('NEXT_PATCH'));
    expect(workflow, contains('steps.release_version.outputs.version'));
    expect(workflow, contains('apksigner'));
    expect(workflow, contains('--print-certs'));
    expect(workflow, contains('actions/upload-artifact@v7'));
    expect(workflow, contains('gh release create'));
    expect(workflow, contains('--generate-notes'));

    final main = File('lib/main.dart').readAsStringSync();
    final mine = File('lib/views/mine/mine_page.dart').readAsStringSync();
    final favorites = File(
      'lib/views/favorites/favorites_page.dart',
    ).readAsStringSync();
    expect(main, contains("path: '/stats'"));
    expect(main, contains("path: 'artists'"));
    expect(main, contains("path: 'tags'"));
    expect(mine, contains("label: '收藏洞察'"));
    expect(favorites, contains("tooltip: '收藏洞察'"));
  });
}
