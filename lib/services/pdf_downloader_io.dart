import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadPdf(List<int> bytes, {String fileName = 'invoice.pdf'}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
}
