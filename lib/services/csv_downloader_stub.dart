import 'dart:async';

Future<void> downloadCsv(String csv, {String fileName = 'invoices.csv'}) {
  return Future.error(
      UnsupportedError('CSV download not supported on this platform'));
}

