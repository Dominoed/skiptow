import 'dart:async';

Future<void> downloadImage(List<int> bytes, {String fileName = 'image.png'}) {
  return Future.error(
      UnsupportedError('Image download not supported on this platform'));
}
