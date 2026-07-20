# Azure Unsigned IPA Pipeline Design

## Goal

Add an Azure Pipelines build that produces the same unsigned iOS artifact as the existing Codemagic workflow. The pipeline must run on a Microsoft-hosted macOS agent, require no Apple credentials, and conserve the free monthly build allowance.

## Scope

The change adds one Azure pipeline definition and a focused configuration contract test. It does not change application code, replace `codemagic.yaml`, sign the IPA, publish to TestFlight, or upload credentials.

## Triggering And Source

- Disable continuous integration and pull-request triggers with `trigger: none` and `pr: none`.
- Builds are started manually from Azure Pipelines so normal pushes do not consume macOS minutes.
- Checkout the full Git history because the existing build-number convention uses the repository commit count.
- Build the selected Azure branch or commit without mirroring the repository into Azure Repos.

## Build Environment

- Use the Microsoft-hosted `macOS-latest` image.
- Clone the Flutter `stable` channel directly during the job and add it to `PATH`.
- Avoid marketplace extensions and persistent SDK caches. This adds some download time but removes third-party setup and stale-cache failure modes.
- Run `flutter doctor -v` so environment details are visible in failed build logs.

## Build Flow

1. Check out the repository with full history.
2. Install Flutter stable and resolve Dart dependencies.
3. Generate the iOS project when it is absent.
4. Apply the existing camera and photo-library usage descriptions.
5. Regenerate application icons.
6. Derive the build name from `pubspec.yaml` and the build number from the Git commit count.
7. Reuse the Codemagic unsigned-build settings: a dummy development team and disabled code-signing requirements in `ios/Flutter/Release.xcconfig`.
8. Run the release iOS build without Apple credentials.
9. Package the generated `.app` directory as `Payload/*.app` inside `joycomic-unsigned.ipa`.
10. Publish the IPA as an Azure Pipeline Artifact named `joycomic-unsigned-ipa`.

Each shell step uses strict failure handling. Missing iOS output or a missing `.app` bundle fails the job with a clear error instead of publishing an empty artifact.

## Security

The pipeline contains no certificates, provisioning profiles, Apple IDs, passwords, API keys, secure-file references, or signing secrets. The resulting IPA is explicitly unsigned and must be signed separately before installation on a physical iPhone.

## Verification

A Dart configuration contract test reads `azure-pipelines.yml` and verifies the durable requirements:

- manual-only triggering;
- `macOS-latest` execution;
- full-history checkout;
- Flutter stable installation;
- disabled code signing;
- unsigned IPA packaging;
- Azure artifact publication.

Local verification consists of the focused contract test, `flutter analyze --no-pub`, `git diff --check`, and YAML parsing when a compatible parser is available. The actual Xcode build can only be proven by manually running the pipeline on Azure's macOS agent.

## Failure Handling And Operations

- Flutter installation, dependency resolution, project generation, compilation, packaging, and artifact publication remain separate named steps for readable logs.
- The generated artifact is downloaded from the completed Azure run's Artifacts section.
- A failed run consumes some Azure minutes but cannot publish a misleading IPA.
- Codemagic remains available as an independent fallback and is not modified.
