import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'invoice_detail_page.dart';

/// Page to view active service requests assigned to a mechanic.
class MechanicRequestQueuePage extends StatefulWidget {
  final String mechanicId;

  const MechanicRequestQueuePage({super.key, required this.mechanicId});

  @override
  State<MechanicRequestQueuePage> createState() =>
      _MechanicRequestQueuePageState();
}

class _MechanicRequestQueuePageState extends State<MechanicRequestQueuePage> {
  String _selectedFilter = 'active';

  Widget _filterButton(String value, String label) {
    final bool selected = _selectedFilter == value;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedFilter = value;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : null,
      ),
      child: Text(label),
    );
  }

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.mechanicId)
        .get();
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

        if (snapshot.data != 'mechanic') {
          return const Scaffold(
            body: Center(child: Text('Access denied')),
          );
        }

        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('invoices')
            .where('mechanicId', isEqualTo: widget.mechanicId);
        if (_selectedFilter.isNotEmpty) {
          query = query.where('status', isEqualTo: _selectedFilter);
        }
        query = query.orderBy('timestamp', descending: true);

        final stream = query.snapshots();

        return Scaffold(
          appBar: AppBar(title: const Text('Request Queue')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _filterButton('active', 'Show Active'),
                    const SizedBox(width: 8),
                    _filterButton('completed', 'Show Completed'),
                    const SizedBox(width: 8),
                    _filterButton('cancelled', 'Show Cancelled'),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('No requests found'));
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        return _RequestTile(
                          invoiceId: docs[index].id,
                          data: data,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RequestTile extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;

  const _RequestTile({required this.invoiceId, required this.data});

  @override
  Widget build(BuildContext context) {
    final car = data['carInfo'] ?? {};
    final carText =
        '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
    final status = (data['status'] ?? 'active').toString();
    final distance = data['distance'];

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(data['customerId'])
          .get(),
      builder: (context, snapshot) {
        final userData = snapshot.data?.data();
        final customerName =
            userData?['username'] ?? data['customerId'];
        final phone = data['customerPhone'] ??
            userData?['phone'] ?? userData?['phoneNumber'];
        final email = data['customerEmail'] ?? userData?['email'];

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: $customerName'),
                if (carText.isNotEmpty) Text('Car: $carText'),
                if (phone != null && phone.toString().isNotEmpty)
                  Text('Phone: $phone'),
                if (email != null && email.toString().isNotEmpty)
                  Text('Email: $email'),
                if (distance != null)
                  Text('Distance: ${(distance as num).toDouble().toStringAsFixed(1)} mi'),
                Text('Status: $status'),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoiceDetailPage(
                            invoiceId: invoiceId,
                            role: 'mechanic',
                          ),
                        ),
                      );
                    },
                    child: const Text('View Details'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InvoiceDetailPage(
                            invoiceId: invoiceId,
                            role: 'mechanic',
                          ),
                        ),
                      );
                    },
                    child: const Text('View Invoice'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

