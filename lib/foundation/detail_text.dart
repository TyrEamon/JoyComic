String normalizeDetailText(String text) {
  var normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  normalized = normalized.replaceAll(
    RegExp(r'<br\b[^>]*>', caseSensitive: false),
    '\n',
  );
  normalized = normalized.replaceAll(
    RegExp(r'</(?:p|div)\s*>', caseSensitive: false),
    '\n',
  );
  normalized = normalized.replaceAll(RegExp(r'<[^>]+>'), '');
  normalized = normalized.replaceAllMapped(
    RegExp(
      r'&(?:#(x[0-9a-f]+|[0-9]+)|(amp|lt|gt|quot|apos|nbsp));',
      caseSensitive: false,
    ),
    _decodeDetailEntity,
  );
  normalized = normalized.replaceAll('\u00a0', ' ');

  normalized = normalized
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return normalized.trim();
}

String _decodeDetailEntity(Match match) {
  final numeric = match.group(1);
  if (numeric != null) {
    final isHex = numeric.toLowerCase().startsWith('x');
    final value = int.tryParse(
      isHex ? numeric.substring(1) : numeric,
      radix: isHex ? 16 : 10,
    );
    if (value == null ||
        value <= 0 ||
        value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff)) {
      return '\uFFFD';
    }
    return String.fromCharCode(value);
  }

  return switch (match.group(2)!.toLowerCase()) {
    'amp' => '&',
    'lt' => '<',
    'gt' => '>',
    'quot' => '"',
    'apos' => "'",
    'nbsp' => ' ',
    _ => match.group(0)!,
  };
}
