import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Displays a list of invoices for the logged in user.
///
/// The page automatically determines if the user is a customer or
/// mechanic by checking the `users` collection. It then queries the
/// `invoices` collection for documents associated with the user.
class InvoicesPage extends StatelessWidget {
  final String userId;

  const InvoicesPage({super.key, required this.userId});

  // Fetch the role of the current user so we know which field to query.
  Future<String?> _getRole() async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return doc.data()?['role'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data;
        if (role != 'customer' && role != 'mechanic') {
          return const Scaffold(
            body: Center(child: Text('❌ Unknown role')),
          );
        }

        final query = FirebaseFirestore.instance
            .collection('invoices')
            .where(role == 'customer' ? 'customerId' : 'mechanicId',
                isEqualTo: userId)
            .orderBy('timestamp', descending: true);

        return Scaffold(
          appBar: AppBar(title: const Text('Invoices')),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('No invoices found'));
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  return _InvoiceTile(
                    invoiceId: docs[index].id,
                    data: data,
                    role: role!,
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Widget to display a single invoice in the list.
class _InvoiceTile extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;
  final String role;

  const _InvoiceTile({
    required this.invoiceId,
    required this.data,
    required this.role,
  });

  // Simple date formatting used throughout the UI.
  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first; // yyyy-MM-dd HH:mm:ss
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      default:
        return Colors.yellow[700]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final car = data['carInfo'] ?? {};
    final carText =
        '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
    final status = (data['status'] ?? 'active') as String;
    final description = data['description'] ?? '';
    final distance = data['distance'];
    final Timestamp? ts = data['timestamp'];

    Widget otherName;
    if (role == 'customer') {
      final name = data['mechanicUsername'] ?? 'Unknown';
      otherName = Text('Mechanic: $name');
    } else {
      // Fetch the customer username from Firestore.
      otherName = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(data['customerId'])
            .get(),
        builder: (context, snapshot) {
          final name = snapshot.data?.data()?['username'] ?? 'Unknown';
          return Text('Customer: $name');
        },
      );
    }

    final List<Widget> columnChildren = [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          otherName,
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
      if (carText.isNotEmpty) Text(carText),
      if (description.toString().isNotEmpty) Text(description),
      if (distance != null) Text('Distance: ${distance.toStringAsFixed(1)} mi'),
      Text('Submitted: ${_formatDate(ts)}'),
    ];

    if (role == 'mechanic' && status == 'active') {
      columnChildren.add(
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('invoices')
                  .doc(invoiceId)
                  .update({'status': 'completed'});
            },
            child: const Text('Mark Completed'),
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: columnChildren,
        ),
      ),
    );
  }
}
