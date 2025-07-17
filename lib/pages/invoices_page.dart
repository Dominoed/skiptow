import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'invoice_detail_page.dart';

/// Displays a list of invoices for the logged in user.
///
/// The page automatically determines if the user is a customer or
/// mechanic by checking the `users` collection. It then queries the
/// `invoices` collection for documents associated with the user.
class InvoicesPage extends StatefulWidget {
  final String userId;

  const InvoicesPage({super.key, required this.userId});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  String? _selectedFilter;

  Widget _resetFilterButton() {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedFilter = null;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
      ),
      child: const Text('Reset Filters'),
    );
  }

  // Fetch the role of the current user so we know which field to query.
  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  Widget _filterButton(String value, String label) {
    final bool selected = _selectedFilter == value;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedFilter = selected ? null : value;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : null,
      ),
      child: Text(label),
    );
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

        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('invoices');
        if (role == 'customer') {
          query = query.where('customerId', isEqualTo: widget.userId);
        } else {
          query = query.where('mechanicId', whereIn: [widget.userId, 'any']);
        }
        if (_selectedFilter == 'active' ||
            _selectedFilter == 'completed' ||
            _selectedFilter == 'cancelled') {
          query = query.where('status', isEqualTo: _selectedFilter);
        }
        query = query.orderBy('timestamp', descending: true);

        return Scaffold(
          appBar: AppBar(title: const Text('Invoices')),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _resetFilterButton(),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                          currentUserId: widget.userId,
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

/// Widget to display a single invoice in the list.
class _InvoiceTile extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;
  final String role;
  final String currentUserId;

  const _InvoiceTile({
    required this.invoiceId,
    required this.data,
    required this.role,
    required this.currentUserId,
  });

  // Simple date formatting used throughout the UI.
  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

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
      // Customer contact details visible only to mechanics
      if (role == 'mechanic' &&
          (data['customerPhone'] ?? '').toString().isNotEmpty)
        Text('Phone: ${data['customerPhone']}'),
      if (role == 'mechanic' &&
          (data['customerEmail'] ?? '').toString().isNotEmpty)
        Text('Email: ${data['customerEmail']}'),
      if (distance != null) Text('Distance: ${distance.toStringAsFixed(1)} mi'),
      Text('Submitted on ${_formatDate(ts)}'),
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

    if (role == 'customer' &&
        status == 'active' &&
        data['customerId'] == currentUserId) {
      columnChildren.add(
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
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
                    .doc(invoiceId)
                    .update({'status': 'cancelled'});

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Request cancelled.')),
                  );
                }
              }
            },
            child: const Text('Cancel Request'),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceDetailPage(
              invoiceId: invoiceId,
              role: role,
            ),
          ),
        );
      },
      child: Card(
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
            children: columnChildren,
          ),
        ),
      ),
    );
  }
}
