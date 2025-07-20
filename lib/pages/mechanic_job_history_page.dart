import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'invoice_detail_page.dart';

/// Page that displays the job history for the logged in mechanic.
class MechanicJobHistoryPage extends StatelessWidget {
  final String mechanicId;

  const MechanicJobHistoryPage({super.key, required this.mechanicId});

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.yellow;
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
        .where('mechanicId', isEqualTo: mechanicId)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Job History')),
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
            return const Center(child: Text('No jobs found'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final invoiceNum = data['invoiceNumber'] ?? doc.id;
              final car = data['carInfo'] ?? {};
              final carText =
                  '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
              final finalPrice = (data['finalPrice'] as num?)?.toDouble();
              final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
              final statusField = data['status'];
              final Timestamp? createdAtTs = data['createdAt'];
              final Timestamp? closedAt = data['closedAt'];
              final bool overdue = paymentStatus == 'pending' &&
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
                        role: 'mechanic',
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
                            Chip(
                              label: Text(
                                status[0].toUpperCase() + status.substring(1),
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: _statusColor(status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(data['customerId'])
                              .get(),
                          builder: (context, snap) {
                            if (snap.connectionState == ConnectionState.waiting) {
                              return const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              );
                            }
                            final username = snap.data?.data()?['username'] ?? 'Unknown';
                            return Text('Customer: $username');
                          },
                        ),
                        if (carText.isNotEmpty) Text('Vehicle: $carText'),
                        if (closedAt != null)
                          Text('Completed on ${_formatDate(closedAt)}'),
                        if (finalPrice != null)
                          Text('Final Price: \$${finalPrice.toStringAsFixed(2)}'),
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
