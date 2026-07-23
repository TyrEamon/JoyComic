/// HLS master-playlist quality discovery.
library;

import 'dart:convert';
import 'dart:typed_data';

const maxHlsManifestBytes = 512 * 1024;

bool isHlsManifestCandidate(Uri uri) =>
    uri.path.toLowerCase().endsWith('.m3u8');

Future<String> readHlsManifest(
  Stream<List<int>> bytes, {
  int maxBytes = maxHlsManifestBytes,
}) async {
  final buffer = BytesBuilder(copy: false);
  var size = 0;
  await for (final chunk in bytes) {
    size += chunk.length;
    if (size > maxBytes) {
      throw const FormatException('HLS manifest is too large');
    }
    buffer.add(chunk);
  }
  return utf8.decode(buffer.takeBytes());
}

class HlsVariant {
  const HlsVariant({
    required this.uri,
    required this.bandwidth,
    required this.width,
    required this.height,
  });

  final Uri uri;
  final int bandwidth;
  final int width;
  final int height;

  String get label {
    if (height > 0) return '${height}p';
    if (bandwidth > 0) {
      return '${(bandwidth / 1000000).toStringAsFixed(1)} Mbps';
    }
    return '其他';
  }
}

List<HlsVariant> parseHlsVariants(String manifest, Uri manifestUri) {
  if (!manifest.trimLeft().startsWith('#EXTM3U')) {
    return const <HlsVariant>[];
  }
  final lines = manifest
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .toList(growable: false);
  final variants = <HlsVariant>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final attributes = _parseAttributes(
      line.substring('#EXT-X-STREAM-INF:'.length),
    );
    String? source;
    for (var next = index + 1; next < lines.length; next++) {
      final candidate = lines[next];
      if (candidate.isEmpty) continue;
      if (candidate.startsWith('#')) break;
      source = candidate;
      index = next;
      break;
    }
    if (source == null) continue;
    final resolution = attributes['RESOLUTION']?.split('x');
    variants.add(
      HlsVariant(
        uri: manifestUri.resolve(source),
        bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
        width: resolution?.length == 2 ? int.tryParse(resolution![0]) ?? 0 : 0,
        height: resolution?.length == 2 ? int.tryParse(resolution![1]) ?? 0 : 0,
      ),
    );
  }
  variants.sort((a, b) {
    final height = b.height.compareTo(a.height);
    return height != 0 ? height : b.bandwidth.compareTo(a.bandwidth);
  });
  return List<HlsVariant>.unmodifiable(variants);
}

Map<String, String> _parseAttributes(String raw) {
  final result = <String, String>{};
  for (final match in RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(raw)) {
    final key = match.group(1);
    var value = match.group(2);
    if (key == null || value == null) continue;
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}
