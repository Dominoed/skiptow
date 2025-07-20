
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'invoice_detail_page.dart';

/// Displays a customer's service requests with filter options.
class CustomerRequestHistoryPage extends StatefulWidget {
  final String userId;
  const CustomerRequestHistoryPage({super.key, required this.userId});

  @override
  State<CustomerRequestHistoryPage> createState() => _CustomerRequestHistoryPageState();
}

class _CustomerRequestHistoryPageState extends State<CustomerRequestHistoryPage> {
  String _filter = 'all';

  Widget _filterButton(String value, String label) {
    final selected = _filter == value;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _filter = value;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : null,
      ),
      child: Text(label),
    );
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

  Color _paymentColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId);

    if (_filter == 'active') {
      query = query.where('status', isEqualTo: 'active');
    } else if (_filter == 'completed') {
      query = query.where('status', whereIn: ['completed', 'closed']);
    }

    query = query.orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Service History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _filterButton('active', 'Active'),
                const SizedBox(width: 8),
                _filterButton('completed', 'Completed'),
                const SizedBox(width: 8),
                _filterButton('all', 'All'),
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

                final docs = (snapshot.data?.docs ?? [])
                    .where((d) => d.data()['flagged'] != true)
                    .toList();
                if (docs.isEmpty) {
                  return const Center(child: Text('No service requests found'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final invoiceNum = data['invoiceNumber'] ?? doc.id;
                    final status =
                        (data['invoiceStatus'] ?? data['status'] ?? 'active')
                            .toString();
                    final mechanic = data['mechanicUsername'];
                    final Timestamp? createdAt = data['createdAt'] ?? data['timestamp'];
                    final estimated = (data['estimatedPrice'] ?? data['quotedPrice']) as num?;
                    final finalPrice = data['finalPrice'] as num?;
                    final bool customerConfirmed = data['customerConfirmed'] == true;

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Invoice #: $invoiceNum',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
                            if (mechanic != null) Text('Mechanic: $mechanic'),
                            Text('Created: ${_formatDate(createdAt)}'),
                            if (estimated != null)
                              Text('Estimated: \${estimated.toDouble().toStringAsFixed(2)}'),
                            if (finalPrice != null)
                              Text('Final Price: \${finalPrice.toDouble().toStringAsFixed(2)}'),
                              if (status == 'completed' && !customerConfirmed && finalPrice != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Job Completed – Please Confirm Final Price: \${finalPrice.toDouble().toStringAsFixed(2)}'),
                                    Row(
                                      children: [
                                        ElevatedButton(
                                          onPressed: () async {
                                            await FirebaseFirestore.instance
                                                .collection('invoices')
                                                .doc(doc.id)
                                                .update({
                                              'invoiceStatus': 'closed',
                                              'status': 'closed',
                                              'customerConfirmed': true
                                            });
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Price accepted. Invoice closed.')),
                                              );
                                            }
                                          },
                                          child: const Text('Accept Price & Close'),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton(
                                          onPressed: () {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dispute feature coming soon.')));
                                          },
                                          child: const Text('Dispute Price'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                            Row(
                              children: [
                                const Text('Mechanic Accepted: '),
                                Icon(
                                  data['mechanicAccepted'] == true ? Icons.check : Icons.close,
                                  color: data['mechanicAccepted'] == true ? Colors.green : Colors.red,
                                  size: 16,
                                ),
                              ],
                            ),
                            if (data['etaMinutes'] != null)
                              Text('ETA: ${data['etaMinutes']} minutes'),
                            if (data['paymentStatus'] != null)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _paymentColor(data['paymentStatus']),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Payment: ${data['paymentStatus']}',
                                  style: const TextStyle(color: Colors.white),
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
                                        invoiceId: doc.id,
                                        role: 'customer',
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('View Details'),
                              ),
                            ),
                            if ((data['mechanicId'] == null ||
                                    data['mechanicAccepted'] != true) &&
                                data['invoiceStatus'] != 'cancelled' &&
                                data['invoiceStatus'] != 'closed')
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) {
                                        return AlertDialog(
                                          title:
                                              const Text('Cancel Request'),
                                          content: const Text(
                                              'Are you sure you want to cancel this service request?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(false),
                                              child: const Text('No'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(true),
                                              child: const Text('Yes'),
                                            ),
                                          ],
                                        );
                                      },
                                    );

                                    if (confirmed == true) {
                                      await FirebaseFirestore.instance
                                          .collection('invoices')
                                          .doc(doc.id)
                                          .update({
                                        'invoiceStatus': 'cancelled'
                                      });

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                              content: Text('Request cancelled.')),
                                        );
                                      }
                                    }
                                  },
                                  child: const Text('Cancel Request'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}