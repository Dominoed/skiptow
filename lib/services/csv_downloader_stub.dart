import 'dart:async';

Future<void> downloadCsv(String csv) {
  return Future.error(
      UnsupportedError('CSV download not supported on this platform'));
}

