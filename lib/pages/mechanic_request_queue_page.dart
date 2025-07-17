import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'invoice_detail_page.dart';
import 'mechanic_dashboard.dart';

/// Helper to hold mechanic role and timestamp field info.
class _RoleAndField {
  final String? role;
  final String field;

  _RoleAndField({required this.role, required this.field});
}

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
  late Future<_RoleAndField> _initialData;

  @override
  void initState() {
    super.initState();
    _initialData = _getInitialData();
  }

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

  Future<_RoleAndField> _getInitialData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.mechanicId)
        .get();
    final role = userDoc.data()?['role'] as String?;

    final invoiceSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .limit(1)
        .get();

    String field = 'timestamp';
    if (invoiceSnap.docs.isNotEmpty) {
      final data = invoiceSnap.docs.first.data();
      if (data.containsKey('submittedAt')) {
        field = 'submittedAt';
      } else if (data.containsKey('createdAt')) {
        field = 'createdAt';
      }
    }

    return _RoleAndField(role: role, field: field);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RoleAndField>(
      future: _initialData,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data!.role;
        final tsField = snapshot.data!.field;

        if (role != 'mechanic') {
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
        if (_selectedFilter == 'active') {
          query = query.orderBy(tsField, descending: true);
        }

        final stream = query.snapshots();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Request Queue'),
            automaticallyImplyLeading: false,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                setState(() {
                  _selectedFilter = 'active';
                });
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MechanicDashboard(
                      userId: widget.mechanicId,
                    ),
                  ),
                );
              },
            ),
          ),
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

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    final date = DateFormat('MM/dd/yyyy').format(dt);
    final time = DateFormat('h:mm a').format(dt);
    return '$date at $time';
  }

  @override
  Widget build(BuildContext context) {
    final car = data['carInfo'] ?? {};
    final carText =
        '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
    final status = (data['status'] ?? 'active').toString();
    final distance = data['distance'];
    final location = data['location'];

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
        final Timestamp? ts = data['timestamp'];

        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Customer: $customerName'),
                if (carText.isNotEmpty) Text('Car: $carText'),
                if (ts != null)
                  Text('Submitted: ${_formatTimestamp(ts)}'),
                if (location != null &&
                    location['lat'] != null &&
                    location['lng'] != null)
                  Text("Location: ${location['lat']}, ${location['lng']}")
                else
                  const Text('Location unavailable.'),
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

