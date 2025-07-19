import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadCsv(String csv, {String fileName = 'invoices.csv'}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(csv);
}

