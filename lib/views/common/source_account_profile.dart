import '../../comic_source/comic_source.dart';

/// Account data normalized from a source without exposing stored credentials.
class SourceAccountProfile {
  const SourceAccountProfile({
    required this.sourceKey,
    required this.sourceName,
    required this.isLoggedIn,
    required this.displayName,
    this.level,
    this.avatarUrl,
  });

  final String sourceKey;
  final String sourceName;
  final bool isLoggedIn;
  final String displayName;
  final String? level;
  final String? avatarUrl;

  String get sourceStatus => isLoggedIn ? sourceName : '$sourceName · 未登录';

  String get settingsStatus {
    if (!isLoggedIn) return '未登录';
    return level == null ? displayName : '$displayName · Lv.$level';
  }

  factory SourceAccountProfile.fromSource(ComicSource source) {
    final user = _stringKeyedMap(source.data['user']);
    final accountName = _firstAccountValue(source.data['account']);
    final displayName = _firstText(<Object?>[
      user['name'],
      user['username'],
      user['nickname'],
      source.data['name'],
      accountName,
      source.name,
    ])!;
    final level = _firstText(<Object?>[user['level'], source.data['level']]);
    final avatar = _validImageUrl(
      _firstText(<Object?>[
        user['avatarUrl'],
        user['avatar'],
        source.data['avatarUrl'],
        source.data['avatar'],
      ]),
    );
    return SourceAccountProfile(
      sourceKey: source.key,
      sourceName: source.name,
      isLoggedIn: source.isLogin,
      displayName: displayName,
      level: level,
      avatarUrl: avatar,
    );
  }
}

Map<String, Object?> _stringKeyedMap(Object? value) {
  if (value is! Map) return const <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

Object? _firstAccountValue(Object? value) {
  if (value is List && value.isNotEmpty) return value.first;
  if (value is Map) {
    return value['name'] ?? value['username'] ?? value['email'];
  }
  return null;
}

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
  }
  return null;
}

String? _validImageUrl(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }
  return value;
}
