import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:charts_flutter/flutter.dart' as charts;

class _MonthSpending {
  final DateTime month;
  final double total;
  _MonthSpending(this.month, this.total);
}

import 'dashboard_page.dart';

class AdminCustomerHistoryPage extends StatefulWidget {
  final String customerId;
  final String userId;
  const AdminCustomerHistoryPage({
    super.key,
    required this.customerId,
    required this.userId,
  });

  @override
  State<AdminCustomerHistoryPage> createState() => _AdminCustomerHistoryPageState();
}

class _AdminCustomerHistoryPageState extends State<AdminCustomerHistoryPage> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  Future<Map<String, dynamic>> _loadStats() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.customerId)
        .get();
    final userData = userDoc.data() ?? {};

    final invoicesSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.customerId)
        .orderBy('createdAt', descending: true)
        .get();

    int totalRequests = 0;
    int paidInvoices = 0;
    int overdueInvoices = 0;
    int pendingInvoices = 0;
    double totalSpent = 0.0;
    double highestPayment = 0.0;

    final now = DateTime.now();
    final Map<int, double> monthTotals = {};
    for (int i = 0; i < 12; i++) {
      final m = DateTime(now.year, now.month - i, 1);
      monthTotals[m.year * 100 + m.month] = 0.0;
    }

    for (final doc in invoicesSnap.docs) {
      final data = doc.data();
      if (data['flagged'] == true) continue;
      totalRequests++;
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
      final Timestamp? createdAtTs = data['createdAt'];
      if (paymentStatus == 'paid') {
        paidInvoices++;
        totalSpent += price;
        if (price > highestPayment) highestPayment = price;
        final Timestamp? closedAt = data['closedAt'];
        final date = (closedAt ?? createdAtTs)?.toDate();
        if (date != null) {
          final key = date.year * 100 + date.month;
          if (monthTotals.containsKey(key)) {
            monthTotals[key] = monthTotals[key]! + price;
          }
        }
      } else {
        if (createdAtTs != null &&
            DateTime.now().difference(createdAtTs.toDate()).inDays > 7) {
          overdueInvoices++;
        } else {
          pendingInvoices++;
        }
      }
    }

    final List<_MonthSpending> months = [];
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = m.year * 100 + m.month;
      months.add(_MonthSpending(m, monthTotals[key] ?? 0));
    }

    return {
      'username': userData['username'] ?? 'Unknown',
      'createdAt': userData['createdAt'],
      'blocked': userData['blocked'] == true,
      'flagged': userData['flagged'] == true,
      'totalRequests': totalRequests,
      'totalSpent': totalSpent,
      'paidInvoices': paidInvoices,
      'overdueInvoices': overdueInvoices,
      'pendingInvoices': pendingInvoices,
      'highestPayment': highestPayment,
      'invoices': invoicesSnap.docs,
      'months': months,
    };
  }

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
    if (ts == null) return 'N/A';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  String _currency(double value) {
    return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(value);
  }

  Widget _buildChart(List<_MonthSpending> months) {
    final series = [
      charts.Series<_MonthSpending, String>(
        id: 'Spending',
        colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
        domainFn: (d, _) => DateFormat('MMM').format(d.month),
        measureFn: (d, _) => d.total,
        data: months,
      )
    ];
    return SizedBox(
      height: 200,
      child: charts.BarChart(series, animate: true),
    );
  }

  Widget _buildSpendingTable(List<_MonthSpending> months) {
    return Table(
      columnWidths: const {1: IntrinsicColumnWidth()},
      border: TableBorder.all(color: Colors.grey),
      children: [
        const TableRow(children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Text('Month', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child:
                Text('Amount', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ]),
        ...months.map(
          (m) => TableRow(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(DateFormat('MMM yyyy').format(m.month)),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_currency(m.total)),
            ),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, roleSnap) {
        if (!roleSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (roleSnap.data != 'admin') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Access denied.')),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => DashboardPage(userId: widget.userId)),
                (route) => false,
              );
            }
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Customer History')),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final invoices = data['invoices'] as List<QueryDocumentSnapshot<Map<String, dynamic>>>;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Customer Username: ${data['username']}'),
                  Text('User ID: ${widget.customerId}'),
                  Text('Registration Date: ${_formatDate(data['createdAt'] as Timestamp?)}'),
                  Text('Blocked: ${data['blocked'] ? 'Yes' : 'No'}'),
                  Text('Flagged: ${data['flagged'] ? 'Yes' : 'No'}'),
                  Text('Suspicious: ${data['suspicious'] ? 'Yes' : 'No'}'),
                  const SizedBox(height: 16),
                  Text('Total Service Requests: ${data['totalRequests']}'),
                  Text('Total Amount Spent: \$${(data['totalSpent'] as double).toStringAsFixed(2)}'),
                  Text('Number of Paid Invoices: ${data['paidInvoices']}'),
                  Text('Number of Overdue Invoices: ${data['overdueInvoices']}'),
                  Text('Number of Pending Invoices: ${data['pendingInvoices']}'),
                  Text('Highest Payment Made: \$${(data['highestPayment'] as double).toStringAsFixed(2)}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Amount Spent Per Month (Last 12 Months)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildChart(data['months'] as List<_MonthSpending>),
                  const SizedBox(height: 8),
                  _buildSpendingTable(data['months'] as List<_MonthSpending>),
                  const SizedBox(height: 16),
                  const Text('Invoices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...invoices.map((doc) {
                    final invoice = doc.data();
                    final invoiceNum = invoice['invoiceNumber'] ?? doc.id;
                    final mechanicId = invoice['mechanicId'];
                    final paymentStatus = (invoice['paymentStatus'] ?? 'pending') as String;
                    final statusField = invoice['status'];
                    final Timestamp? createdAtTs = invoice['createdAt'];
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
                    final price = (invoice['finalPrice'] as num?)?.toDouble();

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
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
                            FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              future: mechanicId != null
                                  ? FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(mechanicId)
                                      .get()
                                  : Future.value(null),
                              builder: (context, snap) {
                                final name = snap.data?.data()?['username'] ?? 'Unknown';
                                return Text('Mechanic: $name');
                              },
                            ),
                            Text('Created: ${_formatDate(createdAtTs)}'),
                            if (price != null) Text('Final Price: \$${price.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
