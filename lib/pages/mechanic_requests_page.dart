import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import '../utils.dart';
import 'invoice_detail_page.dart';

class MechanicRequestsPage extends StatefulWidget {
  final String mechanicId;
  const MechanicRequestsPage({super.key, required this.mechanicId});

  @override
  State<MechanicRequestsPage> createState() => _MechanicRequestsPageState();
}

class _MechanicRequestsPageState extends State<MechanicRequestsPage> {
  late Future<Map<String, dynamic>?> _mechFuture;

  @override
  void initState() {
    super.initState();
    _mechFuture = _loadMechanic();
  }

  Future<Map<String, dynamic>?> _loadMechanic() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.mechanicId)
        .get();
    return doc.data();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _mechFuture,
      builder: (context, mechSnap) {
        if (!mechSnap.hasData) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final mechLocation = mechSnap.data?['location'];

        final directStream = FirebaseFirestore.instance
            .collection('invoices')
            .where('mechanicId', isEqualTo: widget.mechanicId)
            .where('status', isEqualTo: 'active')
            .snapshots();

        final broadcastStream = FirebaseFirestore.instance
            .collection('invoices')
            .where('status', isEqualTo: 'active')
            .where('mechanicId', isEqualTo: null)
            .where('mechanicCandidates', arrayContains: widget.mechanicId)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: directStream,
          builder: (context, directSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: broadcastStream,
              builder: (context, broadSnap) {
                if (directSnap.connectionState == ConnectionState.waiting ||
                    broadSnap.connectionState == ConnectionState.waiting) {
                  return Scaffold(
                    appBar: AppBar(title: Text('Service Requests')),
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                if (directSnap.data != null) {
                  docs.addAll(directSnap.data!.docs);
                }
                if (broadSnap.data != null) {
                  docs.addAll(broadSnap.data!.docs);
                }
                final visibleDocs = docs.where((d) {
                  final data = d.data();
                  if (data['flagged'] == true) return false;
                  if (data['invoiceStatus'] == 'cancelled') return false;
                  final responded = (data['mechanicResponded'] as List?)
                          ?.contains(widget.mechanicId) ??
                      false;
                  return !responded;
                }).toList();

                return Scaffold(
                  appBar: AppBar(title: const Text('Service Requests')),
                  body: visibleDocs.isEmpty
                      ? const Center(child: Text('No service requests'))
                      : ListView.builder(
                          itemCount: visibleDocs.length,
                          itemBuilder: (context, index) {
                            final doc = visibleDocs[index];
                            return _RequestCard(
                              invoiceId: doc.id,
                              data: doc.data(),
                              mechanicId: widget.mechanicId,
                              mechanicLocation: mechLocation,
                            );
                          },
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;
  final String mechanicId;
  final Map<String, dynamic>? mechanicLocation;

  const _RequestCard({
    required this.invoiceId,
    required this.data,
    required this.mechanicId,
    this.mechanicLocation,
  });

  double? _calcDistance(Map<String, dynamic>? invoiceLoc) {
    if (invoiceLoc == null ||
        mechanicLocation == null ||
        invoiceLoc['lat'] == null ||
        invoiceLoc['lng'] == null ||
        mechanicLocation!['lat'] == null ||
        mechanicLocation!['lng'] == null) {
      return null;
    }
    final meters = Geolocator.distanceBetween(
      invoiceLoc['lat'],
      invoiceLoc['lng'],
      mechanicLocation!['lat'],
      mechanicLocation!['lng'],
    );
    return meters / 1609.34;
  }

  Future<bool> _canAcceptMore() async {
    final mechDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(mechanicId)
        .get();
    final isPro = getBool(mechDoc.data(), 'isProUser');
    if (isPro) return true;

    final activeSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: mechanicId)
        .where('invoiceStatus', whereIn: ['accepted', 'in_progress'])
        .limit(1)
        .get();
    return activeSnap.docs.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final broadcast = data['mechanicId'] == null;
    final responded = (data['mechanicResponded'] as List?)?.contains(mechanicId) ?? false;
    final car = data['carInfo'] ?? {};
    final carText =
        '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
    final location = data['location'];
    final description = data['description'] ?? '';
    double? distance = (data['distance'] as num?)?.toDouble();
    distance ??= _calcDistance(location);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(data['customerId'])
          .get(),
      builder: (context, snap) {
        final customerName = snap.data?.data()?['username'] ?? data['customerId'];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: $customerName'),
                if (carText.isNotEmpty) Text('Vehicle: $carText'),
                if (description.toString().isNotEmpty) Text(description),
                if (location != null &&
                    location['lat'] != null &&
                    location['lng'] != null)
                  Text('Location: ${location['lat']}, ${location['lng']}')
                else
                  const Text('Location unavailable.'),
                if (distance != null)
                  Text('Distance: ${distance.toStringAsFixed(1)} mi'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: broadcast
                      ? [
                          ElevatedButton(
                            onPressed:
                                responded ? null : () => _acceptBroadcast(context),
                            child: const Text('Accept Job'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed:
                                responded ? null : () => _declineBroadcast(context),
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _viewDetails(context),
                            child: const Text('Details'),
                          ),
                        ]
                      : [
                          ElevatedButton(
                            onPressed: () => _acceptDirect(context),
                            child: const Text('Accept'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: () => _declineDirect(context),
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _viewDetails(context),
                            child: const Text('Details'),
                          ),
                        ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _viewDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(
          invoiceId: invoiceId,
          role: 'mechanic',
        ),
      ),
    );
  }

  Future<void> _acceptBroadcast(BuildContext context) async {
    if (!await _canAcceptMore()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active request.')),
        );
      }
      return;
    }
    final invoiceRef =
        FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(invoiceRef);
        if (snap.data()?['mechanicId'] != null) {
          return;
        }
        if ((snap.data()?['mechanicResponded'] as List?)?.contains(mechanicId) ?? false) {
          return;
        }
        final mechDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(mechanicId)
            .get();
        final username = mechDoc.data()?['username'] ?? 'Mechanic';
        tx.update(invoiceRef, {
          'mechanicId': mechanicId,
          'mechanicUsername': username,
          'mechanicAccepted': true,
          'mechanicAcceptedAt': FieldValue.serverTimestamp(),
          'acceptedAt': FieldValue.serverTimestamp(),
          'status': 'accepted',
        });
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request accepted.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Unable to accept. Another mechanic may have claimed it.')),
        );
      }
    }
  }

  Future<void> _declineBroadcast(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Decline Request'),
          content: const Text('Are you sure you want to decline this request?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final invoiceRef =
        FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(invoiceRef);
      if ((snap.data()?['mechanicResponded'] as List?)?.contains(mechanicId) ??
          false) {
        return;
      }
      tx.update(invoiceRef, {
        'mechanicResponded': FieldValue.arrayUnion([mechanicId])
      });
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request declined.')),
      );
    }
  }

  Future<void> _acceptDirect(BuildContext context) async {
    if (!await _canAcceptMore()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You already have an active request.')),
        );
      }
      return;
    }
    await FirebaseFirestore.instance.collection('invoices').doc(invoiceId).update({
      'mechanicAccepted': true,
      'mechanicAcceptedAt': FieldValue.serverTimestamp(),
      'acceptedAt': FieldValue.serverTimestamp(),
      'status': 'accepted',
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request accepted.')),
      );
    }
  }

  Future<void> _declineDirect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Decline Request'),
          content: const Text('Are you sure you want to decline this request?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    final update = <String, dynamic>{
      'status': 'cancelled',
      'cancelledBy': 'mechanic',
    };
    if (data['mechanicResponded'] is List) {
      update['mechanicResponded'] = FieldValue.arrayUnion([mechanicId]);
    }
    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(invoiceId)
        .update(update);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request declined.')),
      );
    }
  }
}
