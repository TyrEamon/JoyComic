# Azure Unsigned IPA Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manually triggered Azure Pipelines workflow that builds and publishes `joycomic-unsigned.ipa` on a hosted macOS agent without Apple credentials.

**Architecture:** A repository-level `azure-pipelines.yml` installs Flutter stable, reuses the existing Codemagic unsigned-iOS build behavior, packages the generated app bundle, and publishes one pipeline artifact. A focused Dart contract test protects the trigger, host, checkout, signing, packaging, and artifact requirements without coupling tests to incidental YAML formatting.

**Tech Stack:** Azure Pipelines YAML, Microsoft-hosted macOS, Bash, Flutter/Dart, `flutter_test`.

**Design reference:** `docs/superpowers/specs/2026-07-21-azure-unsigned-ipa-pipeline-design.md`

---

## File Structure

- Create `test/azure_pipeline_test.dart` to enforce the durable CI configuration contract.
- Create `azure-pipelines.yml` to build and publish the unsigned IPA.
- Keep `codemagic.yaml` unchanged as an independent fallback.

### Task 1: Add The Azure Pipeline Contract Test

**Files:**
- Create: `test/azure_pipeline_test.dart`

- [ ] **Step 1: Write the failing contract test**

```dart
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
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
flutter test --no-pub test/azure_pipeline_test.dart
```

Expected: FAIL because `azure-pipelines.yml` does not exist.

- [ ] **Step 3: Commit the failing test**

```powershell
git add test/azure_pipeline_test.dart
git commit -m "test: specify Azure unsigned IPA pipeline"
```

### Task 2: Implement The Azure Unsigned IPA Pipeline

**Files:**
- Create: `azure-pipelines.yml`
- Test: `test/azure_pipeline_test.dart`

- [ ] **Step 1: Add the manual hosted-macOS pipeline and Flutter setup**

Create the pipeline with manual triggers, full-history checkout, Flutter stable installation, environment diagnostics, dependency resolution, iOS project generation, usage descriptions, and icon generation:

```yaml
trigger: none
pr: none

pool:
  vmImage: 'macOS-latest'

steps:
  - checkout: self
    fetchDepth: 0

  - bash: |
      set -euo pipefail
      git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$(Agent.ToolsDirectory)/flutter"
      echo "##vso[task.prependpath]$(Agent.ToolsDirectory)/flutter/bin"
    displayName: 'Install Flutter stable'

  - bash: |
      set -euo pipefail
      flutter doctor -v
      flutter pub get
    displayName: 'Resolve Flutter dependencies'

  - bash: |
      set -euo pipefail
      if [ ! -d ios ]; then
        flutter create . --platforms=ios
      fi
      /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string 选择漫画图片用于以图搜图" ios/Runner/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryUsageDescription 选择漫画图片用于以图搜图" ios/Runner/Info.plist
      /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 拍摄漫画图片用于以图搜图" ios/Runner/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription 拍摄漫画图片用于以图搜图" ios/Runner/Info.plist
      dart run flutter_launcher_icons
    displayName: 'Prepare iOS project'
```

- [ ] **Step 2: Add unsigned build, packaging, and artifact publication**

Append steps that derive the same version metadata as Codemagic, disable signing, build the app, validate the output, package the IPA in Azure's staging directory, and publish it:

```yaml
  - bash: |
      set -euo pipefail
      VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
      BUILD_NAME="${VERSION%%+*}"
      BUILD_NUMBER="$(git rev-list --count HEAD)"

      cat >> ios/Flutter/Release.xcconfig <<'EOF'

      DEVELOPMENT_TEAM=0000000000
      CODE_SIGN_STYLE=Manual
      CODE_SIGNING_ALLOWED=NO
      CODE_SIGNING_REQUIRED=NO
      EOF

      flutter build ios --release \
        --build-name="$BUILD_NAME" \
        --build-number="$BUILD_NUMBER"
    displayName: 'Build unsigned iOS app'

  - bash: |
      set -euo pipefail
      APP_PATH="$(find build/ios -name '*.app' -type d -print -quit)"
      if [ -z "$APP_PATH" ]; then
        echo 'No .app bundle was produced.' >&2
        exit 1
      fi

      PACKAGE_DIR="$(Build.ArtifactStagingDirectory)/ipa"
      mkdir -p "$PACKAGE_DIR/Payload"
      cp -R "$APP_PATH" "$PACKAGE_DIR/Payload/"
      cd "$PACKAGE_DIR"
      zip -qry joycomic-unsigned.ipa Payload
      test -s joycomic-unsigned.ipa
      rm -rf Payload
    displayName: 'Package unsigned IPA'

  - task: PublishPipelineArtifact@1
    displayName: 'Publish unsigned IPA'
    inputs:
      targetPath: '$(Build.ArtifactStagingDirectory)/ipa'
      artifact: 'joycomic-unsigned-ipa'
      publishLocation: 'pipeline'
```

- [ ] **Step 3: Run the focused test and verify GREEN**

Run:

```powershell
flutter test --no-pub test/azure_pipeline_test.dart
```

Expected: all three tests pass.

- [ ] **Step 4: Validate YAML structure**

Run a parser available in the workspace dependency runtime against `azure-pipelines.yml`.

Expected: parsing succeeds and the root contains `trigger`, `pr`, `pool`, and `steps`.

- [ ] **Step 5: Commit the implementation**

```powershell
git add azure-pipelines.yml
git commit -m "ci: build unsigned IPA with Azure Pipelines"
```

### Task 3: Verify And Publish

**Files:**
- Verify: `azure-pipelines.yml`
- Verify: `test/azure_pipeline_test.dart`

- [ ] **Step 1: Run fresh focused and repository verification**

```powershell
flutter test --no-pub test/azure_pipeline_test.dart
flutter analyze --no-pub
git diff --check origin/main...HEAD
```

Expected: the focused tests and analyzer pass, and the diff check reports no whitespace errors.

- [ ] **Step 2: Review the committed diff and secret boundary**

```powershell
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- azure-pipelines.yml test/azure_pipeline_test.dart docs/superpowers/specs/2026-07-21-azure-unsigned-ipa-pipeline-design.md docs/superpowers/plans/2026-07-21-azure-unsigned-ipa-pipeline.md
```

Expected: only the planned files are present; the YAML contains no Apple credentials, certificates, provisioning profiles, passwords, or secure-file references.

- [ ] **Step 3: Fast-forward push the branch to `origin/main`**

```powershell
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
git push origin HEAD:main
git fetch origin main
```

Expected: the ancestry check succeeds, the push is a fast-forward, and `git rev-parse HEAD` equals `git rev-parse origin/main`.

