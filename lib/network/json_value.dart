/// Small, predictable conversions for values decoded from remote JSON.
///
/// Scalar helpers accept the common variants returned by the supported APIs.
/// Structure helpers deliberately return empty collections for non-structures;
/// callers that require a map or list must still validate that requirement.
library;

/// Converts a JSON value to an integer, or returns [fallback].
int jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final text = value.trim();
    return int.tryParse(text) ?? num.tryParse(text)?.toInt() ?? fallback;
  }
  return fallback;
}

/// Converts a non-null JSON value to text, or returns [fallback].
String jsonString(Object? value, {String fallback = ''}) =>
    value == null ? fallback : value.toString();

/// Converts common JSON boolean representations, or returns [fallback].
bool jsonBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) {
    if (value == 1) return true;
    if (value == 0) return false;
    return fallback;
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
    }
  }
  return fallback;
}

/// Returns [value] when it is a JSON list, otherwise an empty list.
List<dynamic> jsonList(Object? value) =>
    value is List ? value : const <dynamic>[];

/// Returns a string-keyed copy of [value], otherwise an empty map.
///
/// Non-string keys cannot occur in decoded JSON and are ignored when callers
/// pass a manually constructed map.
Map<String, dynamic> jsonMap(Object? value) {
  if (value is! Map) return const <String, dynamic>{};
  final result = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) result[key] = entry.value;
  }
  return result;
}

/// Converts scalar entries in a JSON list to strings.
///
/// Null and structured entries are dropped rather than producing misleading
/// display values such as `null` or `{...}`.
List<String> jsonStringList(Object? value) => <String>[
  for (final item in jsonList(value))
    if (item is String || item is num || item is bool) item.toString(),
];
