/// Normalizes Pica media hosts to the reachable go2778 mirror.
String normalizePicacgMediaUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return value;
  return value.replaceFirst('picacomic', 'go2778');
}

String picacgOriginalMediaUrl(String url) {
  final value = url.trim();
  if (value.isEmpty) return value;
  return value.replaceFirst('go2778', 'picacomic');
}
