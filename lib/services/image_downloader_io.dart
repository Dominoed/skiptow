import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<void> downloadImage(List<int> bytes, {String fileName = 'image.png'}) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
}
