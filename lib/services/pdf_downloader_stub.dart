import 'dart:async';

Future<void> downloadPdf(List<int> bytes, {String fileName = 'invoice.pdf'}) {
  return Future.error(
      UnsupportedError('PDF download not supported on this platform'));
}
