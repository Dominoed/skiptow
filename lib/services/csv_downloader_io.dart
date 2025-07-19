import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadCsv(String csv) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/invoices.csv');
  await file.writeAsString(csv);
}

