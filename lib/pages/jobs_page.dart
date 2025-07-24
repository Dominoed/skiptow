import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'invoice_detail_page.dart';
import '../utils.dart';

/// Displays a list of jobs for the logged in user.
///
/// The page automatically determines if the user is a customer or
/// mechanic by checking the `users` collection. It then queries the
/// `invoices` collection for documents associated with the user.
class JobsPage extends StatefulWidget {
  final String userId;

  const JobsPage({super.key, required this.userId});

  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  // Fetch the role of the current user so we know which field to query.
  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
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

        final role = snapshot.data;
        if (role != 'customer' && role != 'mechanic') {
          return const Scaffold(
            body: Center(child: Text('❌ Unknown role')),
          );
        }

        Query<Map<String, dynamic>> query =
            FirebaseFirestore.instance.collection('invoices');
        if (role == 'customer') {
          query = query.where('customerId', isEqualTo: widget.userId);
        } else {
          // Mechanics only view invoices assigned to them
          query = query.where('mechanicId', isEqualTo: widget.userId);
        }
        query = query.orderBy('timestamp', descending: true);

        return Scaffold(
          appBar: AppBar(title: const Text('Jobs')),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
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
                        final data = docs[index].data();
                        return _JobTile(
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

/// Widget to display a single job in the list.
class _JobTile extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;
  final String role;
  final String currentUserId;

  const _JobTile({
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
      case 'closed':
        return Colors.blueGrey;
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
      if (role == 'customer' && status == 'completed')
        Text(
          data['finalPrice'] != null
              ? 'Total Paid: \$${(data['finalPrice'] as num).toStringAsFixed(2)}'
              : 'Payment amount unavailable.',
        ),
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
              final priceController = TextEditingController();
              final notesController = TextEditingController();
              final result = await showDialog<Map<String, dynamic>?>(
                context: context,
                builder: (context) {
                  String? errorText;
                  return StatefulBuilder(
                    builder: (context, setState) {
                      return AlertDialog(
                        title: const Text('Mark as Completed'),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Enter final total price (in USD):',
                                ),
                              ),
                              TextField(
                                controller: notesController,
                                minLines: 3,
                                maxLines: 5,
                                decoration: const InputDecoration(
                                  labelText: 'Post-Job Notes (required)',
                                ),
                              ),
                              if (errorText != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    errorText!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              final price = double.tryParse(priceController.text);
                              final notes = notesController.text.trim();
                              if (price == null || notes.isEmpty) {
                                setState(() {
                                  errorText = 'Please enter a valid price and notes.';
                                });
                              } else {
                                Navigator.of(context).pop({'price': price, 'notes': notes});
                              }
                            },
                            child: const Text('Submit'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );

              if (result != null) {
                final double price = result['price'] as double;
                final String notes = result['notes'] as String;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Confirm Final Price'),
                      content: Text(
                        'Confirm final price of \$${price.toStringAsFixed(2)}? This cannot be changed later.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Confirm'),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed == true) {
                  final double fee = double.parse((price * 0.10).toStringAsFixed(2));
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(invoiceId)
                      .update({
                    'status': 'completed',
                    'invoiceStatus': 'completed',
                    'finalPrice': price,
                    'postJobNotes': notes,
                    'platformFee': fee,
                  });
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .update({'completedJobs': FieldValue.increment(1)});

                  await showCustomerRatingDialog(context, invoiceId);
                }
              }
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
                    .update({'status': 'cancelled', 'invoiceStatus': 'cancelled'});

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
