typedef JsonMap = Map<String, dynamic>;

JsonMap? jsonMapOrNull(Object? value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> jsonList(Object? value) {
  return value is List ? List<Object?>.from(value) : const <Object?>[];
}

String? nullableString(Object? value) {
  if (value == null) return null;
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) return value.toString();
  return null;
}

String stringValue(Object? value, {String fallback = ''}) {
  return nullableString(value) ?? fallback;
}

String objectId(Object? value) {
  final direct = nullableString(value);
  if (direct != null) return direct;

  final map = jsonMapOrNull(value);
  if (map == null) return '';

  for (final key in const ['_id', 'id', r'$oid']) {
    final id = nullableString(map[key]);
    if (id != null) return id;
  }
  return '';
}

DateTime? dateTimeOrNull(Object? value) {
  if (value is DateTime) return value;
  final text = nullableString(value);
  return text == null ? null : DateTime.tryParse(text);
}

int intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  switch (value?.toString().trim().toLowerCase()) {
    case 'true':
    case '1':
      return true;
    case 'false':
    case '0':
      return false;
    default:
      return fallback;
  }
}
