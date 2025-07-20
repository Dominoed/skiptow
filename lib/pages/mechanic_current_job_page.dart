import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Page allowing a mechanic to manage their current job.
class MechanicCurrentJobPage extends StatefulWidget {
  final String invoiceId;
  const MechanicCurrentJobPage({super.key, required this.invoiceId});

  @override
  State<MechanicCurrentJobPage> createState() => _MechanicCurrentJobPageState();
}

class _MechanicCurrentJobPageState extends State<MechanicCurrentJobPage> {
  final TextEditingController _etaController = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _etaController.dispose();
    super.dispose();
  }

  Future<void> _updateEta() async {
    final eta = int.tryParse(_etaController.text);
    if (eta != null) {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(widget.invoiceId)
          .update({'etaMinutes': eta});
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ETA updated')));
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() {
      _status = newStatus;
    });
    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .update({'status': newStatus, 'invoiceStatus': newStatus});
  }

  Future<void> _openNavigation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Current Job')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('invoices')
            .doc(widget.invoiceId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return const Center(child: Text('Job not found'));
          }
          final invoiceStatus = (data['invoiceStatus'] ?? data['status'] ?? '').toString();
          if (invoiceStatus != 'accepted' && invoiceStatus != 'in_progress') {
            Future.microtask(() {
              if (mounted) Navigator.pop(context);
            });
            return const SizedBox.shrink();
          }
          final description = data['description'] ?? '';
          final location = data['location'];
          final finalPrice = data['finalPrice'];
          final eta = data['etaMinutes'];
          final customerId = data['customerId'];
          if (eta != null && _etaController.text != eta.toString()) {
            _etaController.text = eta.toString();
          }
          _status = invoiceStatus;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(customerId)
                      .get(),
                  builder: (context, userSnap) {
                    final user = userSnap.data?.data();
                    final name = user?['username'] ?? user?['displayName'] ?? customerId;
                    final phone = user?['phone'] ?? user?['phoneNumber'];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer: $name'),
                        if (phone != null && phone.toString().isNotEmpty)
                          Text('Phone: $phone'),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                if (description.toString().isNotEmpty) Text('Service: $description'),
                if (finalPrice != null)
                  Text('Final Price: \$${(finalPrice as num).toStringAsFixed(2)}'),
                const SizedBox(height: 8),
                if (location != null && location['lat'] != null && location['lng'] != null)
                  SizedBox(
                    height: 200,
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                              (location['lat'] as num).toDouble(),
                              (location['lng'] as num).toDouble(),
                            ),
                            zoom: 14,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId('job'),
                              position: LatLng(
                                (location['lat'] as num).toDouble(),
                                (location['lng'] as num).toDouble(),
                              ),
                            ),
                          },
                        ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: ElevatedButton.icon(
                            onPressed: () => _openNavigation(
                              (location['lat'] as num).toDouble(),
                              (location['lng'] as num).toDouble(),
                            ),
                            icon: const Icon(Icons.navigation),
                            label: const Text('Navigate'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _etaController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'ETA in minutes'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _updateEta,
                  child: const Text('Update ETA'),
                ),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'accepted', child: Text('Accepted')),
                    DropdownMenuItem(value: 'arrived', child: Text('Arrived')),
                    DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      _updateStatus(val);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
