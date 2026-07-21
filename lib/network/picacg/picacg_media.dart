/// Browser User-Agent for Picacg **media CDN** requests.
///
/// Media downloads inject a desktop Chrome UA before Dio. API requests still
/// use `okhttp/3.8.1` via [buildHeaders]; media must not reuse API signature
/// headers. No `Connection` hop-by-hop header (HttpClient manages that).
const picacgMediaUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// Minimal safe headers for chapter/cover media GETs.
Map<String, String> picacgImageHeaders() => <String, String>{
  'User-Agent': picacgMediaUserAgent,
};

/// Normalizes Pica media hosts to the reachable go2778 mirror.
///
/// Only rewrites the host (e.g. `storage1.picacomic.com` →
/// `storage1.go2778.com`). Path segments are left untouched so a path that
/// happens to contain the substring "picacomic" is not corrupted.
String normalizePicacgMediaUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    return value.contains('picacomic')
        ? value.replaceFirst('picacomic', 'go2778')
        : value;
  }
  if (!uri.host.contains('picacomic')) return value;
  return uri
      .replace(host: uri.host.replaceFirst('picacomic', 'go2778'))
      .toString();
}

/// Restores the official picacomic media host from a go2778 mirror URL.
String picacgOriginalMediaUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    return value.contains('go2778')
        ? value.replaceFirst('go2778', 'picacomic')
        : value;
  }
  if (!uri.host.contains('go2778')) return value;
  return uri
      .replace(host: uri.host.replaceFirst('go2778', 'picacomic'))
      .toString();
}
