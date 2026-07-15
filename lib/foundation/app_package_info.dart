import 'package:package_info_plus/package_info_plus.dart';

class AppPackageInfo {
  const AppPackageInfo({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String version;
  final String buildNumber;

  String get versionLabel =>
      buildNumber.isEmpty ? '版本 $version' : '版本 $version ($buildNumber)';

  String get licenseVersion =>
      buildNumber.isEmpty ? version : '$version+$buildNumber';

  static const fallback = AppPackageInfo(
    appName: 'JoyComic',
    version: '未知',
    buildNumber: '',
  );
}

typedef AppPackageInfoLoader = Future<AppPackageInfo> Function();

Future<AppPackageInfo> loadAppPackageInfo() async {
  final info = await PackageInfo.fromPlatform();
  return AppPackageInfo(
    appName: info.appName.isEmpty ? 'JoyComic' : info.appName,
    version: info.version.isEmpty ? '未知' : info.version,
    buildNumber: info.buildNumber,
  );
}
