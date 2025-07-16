import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    data['customerUsername'] = customerDoc.data()?['username'] ?? 'Unknown';
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

        final children = <Widget>[
          Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
          Text('Customer: ${data['customerUsername'] ?? 'Unknown'}'),
          if (carText.isNotEmpty) Text('Car: $carText'),
          if ((data['description'] ?? '').toString().isNotEmpty)
            Text('Problem: ${data['description']}'),
          if (location != null)
            Text('Location: ${location['lat']}, ${location['lng']}'),
          if (data['distance'] != null)
            Text('Distance: ${data['distance'].toStringAsFixed(1)} mi'),
          Text('Submitted: ${_formatDate(data['timestamp'])}'),
          Text('Status: $status'),
        ];

        if (widget.role == 'mechanic' && status == 'active') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId)
                      .update({'status': 'completed'});
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Mark as Completed'),
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

