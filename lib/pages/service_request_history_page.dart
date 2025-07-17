import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ServiceRequestHistoryPage extends StatelessWidget {
  final String userId;

  const ServiceRequestHistoryPage({super.key, required this.userId});

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.yellow[700]!;
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
      appBar: AppBar(title: const Text('Service Request History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No service requests found'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final car = data['carInfo'] ?? {};
              final carText =
                  '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
              final mechanic = data['mechanicUsername'] ?? 'Unknown';
              final description = data['description'] ?? '';
              final status = (data['status'] ?? 'active') as String;
              final Timestamp? ts = data['timestamp'];

              return Card(
                margin: const EdgeInsets.all(8),
                shape: status == 'cancelled'
                    ? RoundedRectangleBorder(
                        side: const BorderSide(color: Colors.red, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mechanic: $mechanic'),
                      if (carText.isNotEmpty) Text('Car: $carText'),
                      if (description.toString().isNotEmpty) Text(description),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                      Text('Submitted on ${_formatDate(ts)}'),
                    ],
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
