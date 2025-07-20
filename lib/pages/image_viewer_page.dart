import 'package:flutter/material.dart';

/// Simple fullscreen image viewer with pinch-to-zoom support.
class ImageViewerPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.imageUrls.length,
          itemBuilder: (context, index) {
            final url = widget.imageUrls[index];
            return Center(
              child: InteractiveViewer(
                child: Image.network(url),
              ),
            );
          },
        ),
      ),
    );
  }
}
