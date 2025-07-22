/// Helper to compute hash codes for multiple values.
/// This mirrors the deprecated `hashValues` function from `dart:ui`.
int hashValues(
  Object? arg0,
  Object? arg1, [
  Object? arg2,
  Object? arg3,
  Object? arg4,
  Object? arg5,
  Object? arg6,
  Object? arg7,
  Object? arg8,
]) {
  return Object.hashAll([
    arg0,
    arg1,
    arg2,
    arg3,
    arg4,
    arg5,
    arg6,
    arg7,
    arg8,
  ]);
}

/// Helper to compute hash codes for an arbitrary number of values.
///
/// This mirrors the `hashList` utility from Flutter which wraps
/// `Object.hashAll` but exposes a name consistent with [hashValues].
int hashAll(Iterable<Object?> values) {
  return Object.hashAll(values);
}
