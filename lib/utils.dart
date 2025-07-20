bool getBool(Map<String, dynamic>? data, String key, {bool defaultValue = false}) {
  final value = data?[key];
  if (value is bool) return value;
  if (value == null) return defaultValue;
  if (value is num) return value != 0;
  final str = value.toString().toLowerCase();
  if (str == 'true') return true;
  if (str == 'false') return false;
  return defaultValue;
}
