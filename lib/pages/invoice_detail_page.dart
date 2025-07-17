import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

/// Page to show full invoice details.
class InvoiceDetailPage extends StatefulWidget {
  final String invoiceId;
  final String role;

  const InvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.role,
  });

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late final Future<Map<String, dynamic>?> _invoiceFuture;
  Future<Map<String, dynamic>?> _loadInvoice() async {
    final doc = await FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .get();
    final data = doc.data();
    if (data == null) return null;

    final customerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(data['customerId'])
        .get();
    final customerData = customerDoc.data();
    data['customerName'] =
        customerData?['displayName'] ?? customerData?['username'];
    data['customerUsername'] = customerData?['username'] ?? 'Unknown';
    // Optional contact info
    data['customerPhone'] =
        customerData?['phone'] ?? customerData?['phoneNumber'];
    data['customerEmail'] = customerData?['email'];

    // Fetch mechanic info
    if (data['mechanicId'] != 'any') {
      final mechDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['mechanicId'])
          .get();
      final mechData = mechDoc.data();
      data['mechanicIsActive'] = mechData?['isActive'] ?? false;

      final mechLocation = mechData?['location'];
      final invoiceLocation = data['location'];
      if (widget.role == 'customer' &&
          mechLocation != null &&
          invoiceLocation != null &&
          mechLocation['lat'] != null &&
          mechLocation['lng'] != null &&
          invoiceLocation['lat'] != null &&
          invoiceLocation['lng'] != null) {
        final double meters = Geolocator.distanceBetween(
          invoiceLocation['lat'],
          invoiceLocation['lng'],
          mechLocation['lat'],
          mechLocation['lng'],
        );
        data['distanceToMechanic'] = meters / 1609.34;
      }

      // Contact details only for non-customer views
      if (widget.role != 'customer') {
        data['mechanicPhone'] =
            mechData?['phone'] ?? mechData?['phoneNumber'];
        data['mechanicEmail'] = mechData?['email'];
      }
    }
    return data;
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  @override
  void initState() {
    super.initState();
    _invoiceFuture = _loadInvoice();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _invoiceFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Invoice Details')),
            body: const Center(child: Text('Invoice not found')),
          );
        }

        final data = snapshot.data!;
        final car = data['carInfo'] ?? {};
        final carText =
            '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
        final location = data['location'];
        final status = data['status'] ?? 'active';
        final finalPrice = data['finalPrice'];

        final children = <Widget>[];
        if (widget.role == 'mechanic') {
          final name = data['customerName'] ?? data['customerUsername'];
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Customer: ${name ?? 'Unknown'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        children.add(
          Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
        );

        if (widget.role == 'customer') {
          if (data['distanceToMechanic'] != null) {
            children.add(
              Text(
                'Distance to Mechanic: '
                '${(data['distanceToMechanic'] as double).toStringAsFixed(1)} miles',
              ),
            );
          } else {
            children.add(const Text('Distance unavailable.'));
          }
        }

        final bool? mechActive = data['mechanicIsActive'] as bool?;
        if (mechActive != null) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                mechActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: mechActive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        children.addAll([
          if (widget.role != 'mechanic')
            Text('Customer: ${data['customerName'] ?? data['customerUsername'] ?? 'Unknown'}'),
          if (carText.isNotEmpty) Text('Car: $carText'),
          if ((data['description'] ?? '').toString().isNotEmpty)
            Text('Problem: ${data['description']}'),
          if ((data['notes'] ?? '').toString().isNotEmpty)
            Text('Customer Notes:\n${data['notes']}')
          else
            const Text('No additional notes.'),
          if (widget.role == 'customer')
            Text(
              finalPrice != null
                  ? 'Final Total: \$${finalPrice.toStringAsFixed(2)}'
                  : 'Final Total: Pending',
            ),
          // Show customer contact info only to mechanics
          if (widget.role == 'mechanic' &&
              (data['customerPhone'] ?? '').toString().isNotEmpty)
            Text('Phone: ${data['customerPhone']}'),
          if (widget.role == 'mechanic' &&
              (data['customerEmail'] ?? '').toString().isNotEmpty)
            Text('Email: ${data['customerEmail']}'),
          // Show mechanic contact info to non-customers (e.g. mechanic or admin)
          if (widget.role != 'customer' &&
              (data['mechanicPhone'] ?? '').toString().isNotEmpty)
            Text('Mechanic Phone: ${data['mechanicPhone']}'),
          if (widget.role != 'customer' &&
              (data['mechanicEmail'] ?? '').toString().isNotEmpty)
            Text('Mechanic Email: ${data['mechanicEmail']}'),
          if (location != null)
            Text('Location: ${location['lat']}, ${location['lng']}'),
          if (data['distance'] != null)
            Text('Distance: ${data['distance'].toStringAsFixed(1)} mi'),
          Text('Submitted: ${_formatDate(data['timestamp'])}'),
          Text('Status: $status'),
          if (finalPrice != null && widget.role != 'customer')
            Text('Final Price: \$${finalPrice.toString()}'),
        ];

        if (widget.role == 'mechanic' && status == 'active') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  final controller = TextEditingController();
                  final price = await showDialog<double>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Mark as Completed'),
                        content: TextField(
                          controller: controller,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Enter final total price (in USD):',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              final val = double.tryParse(controller.text);
                              Navigator.of(context).pop(val);
                            },
                            child: const Text('Submit'),
                          ),
                        ],
                      );
                    },
                  );

                  if (price != null) {
                    await FirebaseFirestore.instance
                        .collection('invoices')
                        .doc(widget.invoiceId)
                        .update({'status': 'completed', 'finalPrice': price});

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invoice marked as completed.'),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text('Mark as Completed'),
              ),
            ),
          );

          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Cancel Request'),
                        content: const Text(
                            'Are you sure you want to cancel this service request?'),
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

                  if (confirmed == true) {
                    await FirebaseFirestore.instance
                        .collection('invoices')
                        .doc(widget.invoiceId)
                        .update({
                      'status': 'cancelled',
                      'cancelledBy': 'mechanic',
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Request cancelled.')),
                      );
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text('Cancel Request'),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Invoice Details')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

