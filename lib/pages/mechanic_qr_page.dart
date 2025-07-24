import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/image_downloader_stub.dart'
    if (dart.library.io) '../services/image_downloader_io.dart'
    if (dart.library.html) '../services/image_downloader_web.dart';

/// Page for mechanics to generate and download their referral QR code.
class MechanicQrPage extends StatefulWidget {
  final String mechanicId;
  const MechanicQrPage({super.key, required this.mechanicId});

  @override
  State<MechanicQrPage> createState() => _MechanicQrPageState();
}

class _MechanicQrPageState extends State<MechanicQrPage> {
  String? _link;
  bool _copied = false;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    final docRef =
        FirebaseFirestore.instance.collection('users').doc(widget.mechanicId);
    final snap = await docRef.get();
    String link = snap.data()?['referralLink'] as String? ??
        'https://skiptow.site/mechanic/${widget.mechanicId}';
    if (snap.data()?['referralLink'] == null) {
      await docRef.update({'referralLink': link});
    }
    if (mounted) {
      setState(() {
        _link = link;
      });
    }
  }

  Future<void> _downloadQrCode() async {
    if (_link == null) return;
    final painter = QrPainter(
      data: _link!,
      version: QrVersions.auto,
      gapless: true,
    );
    final data = await painter.toImageData(300);
    if (data == null) return;
    await downloadImage(data.buffer.asUint8List(),
        fileName: 'referral_${widget.mechanicId}.png');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QR code image downloaded')),
      );
    }
  }

  Future<void> _copyLink() async {
    if (_link == null) return;
    await Clipboard.setData(ClipboardData(text: _link!));
    if (mounted) {
      setState(() => _copied = true);
    }
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral QR Code')),
      body: _link == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RepaintBoundary(
                    key: _qrKey,
                    child: QrImageView(
                      data: _link!,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _downloadQrCode,
                    child: const Text('Download QR Code Image'),
                  ),
                  const SizedBox(height: 20),
                  SelectableText(_link!),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _copyLink,
                    child: Text(_copied ? 'Copied!' : 'Copy'),
                  ),
                ],
              ),
            ),
    );
  }
}
