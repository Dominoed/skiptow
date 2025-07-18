import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'invoice_detail_page.dart';

/// Page that displays all invoices for the logged in customer.
class CustomerInvoicesPage extends StatelessWidget {
  final String userId;

  const CustomerInvoicesPage({super.key, required this.userId});

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      case 'closed':
        return Colors.blueGrey;
      default:
        return Colors.orange;
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('My Invoices')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = (snapshot.data?.docs ?? [])
              .where((d) => d.data()['flagged'] != true)
              .toList();
          if (docs.isEmpty) {
            return const Center(child: Text('No invoices found'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final invoiceNum = data['invoiceNumber'] ?? doc.id;
              final mechanic = data['mechanicUsername'] ?? 'Unknown';
              final car = data['carInfo'] ?? {};
              final carText =
                  '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
              final finalPrice = (data['finalPrice'] as num?)?.toDouble();
              final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
              final statusField = data['status'];
              final Timestamp? createdAtTs = data['createdAt'];
              final Timestamp? ts = data['timestamp'];
              final overdue = paymentStatus == 'pending' &&
                  createdAtTs != null &&
                  DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
              String status;
              if (statusField == 'closed') {
                status = 'closed';
              } else if (overdue) {
                status = 'overdue';
              } else if (paymentStatus == 'paid') {
                status = 'paid';
              } else {
                status = 'pending';
              }

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InvoiceDetailPage(
                        invoiceId: doc.id,
                        role: 'customer',
                      ),
                    ),
                  );
                },
                child: Card(
                  margin: const EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Invoice #: $invoiceNum',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(status),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Mechanic: $mechanic'),
                        if (carText.isNotEmpty) Text('Vehicle: $carText'),
                        Text('Submitted on ${_formatDate(ts)}'),
                        if (finalPrice != null)
                          Text('Final Price: \\$${finalPrice.toStringAsFixed(2)}'),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
