import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:charts_flutter/flutter.dart' as charts;

import "../utils.dart";
import '../services/csv_downloader.dart';

class _MonthSpending {
  final DateTime month;
  final double amount;
  _MonthSpending(this.month, this.amount);
}

class CustomerServiceHistoryPage extends StatelessWidget {
  final String userId;
  const CustomerServiceHistoryPage({super.key, required this.userId});


  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  String _csvEscape(String? input) {
    if (input == null) return '';
    var s = input.replaceAll('"', '""');
    if (s.contains(',') || s.contains('\n') || s.contains('"')) {
      s = '"$s"';
    }
    return s;
  }

  Future<void> _exportCsv(BuildContext context,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final buffer = StringBuffer();
    buffer.writeln(
        'Invoice Number,Mechanic Username,Status,Final Price,Created Date,Completed Date');
    for (final doc in docs) {
      final data = doc.data();
      final invoiceNum = (data['invoiceNumber'] ?? doc.id).toString();
      final mechanic = (data['mechanicUsername'] ?? '').toString();
      final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
      final statusField = data['status'];
      final Timestamp? createdAtTs = data['createdAt'];
      final Timestamp? closedAtTs = data['closedAt'];
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
      final price = (data['finalPrice'] as num?)?.toDouble();
      final row = [
        invoiceNum,
        mechanic,
        status,
        price != null ? price.toStringAsFixed(2) : '',
        _formatTimestamp(createdAtTs),
        _formatTimestamp(closedAtTs),
      ].map(_csvEscape).join(',');
      buffer.writeln(row);
    }
    await downloadCsv(buffer.toString(), fileName: 'service_history.csv');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Service history CSV exported')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Service History')),
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
            return const Center(child: Text('No service history found'));
          }

          int totalRequests = docs.length;
          int paidCount = 0;
          int pendingCount = 0;
          int overdueCount = 0;
          double totalSpent = 0.0;

          final now = DateTime.now();
          final months = List.generate(
              12, (i) => DateTime(now.year, now.month - i, 1));
          final monthTotals = {
            for (final m in months) DateFormat('yyyy-MM').format(m): 0.0
          };

          for (final doc in docs) {
            final data = doc.data();
            final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
            final Timestamp? createdAtTs = data['createdAt'];
            final bool overdue = paymentStatus == 'pending' &&
                createdAtTs != null &&
                DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
            final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
            if (paymentStatus == 'paid') {
              paidCount++;
              totalSpent += price;

              final ts = data['closedAt'] as Timestamp? ?? createdAtTs;
              if (ts != null) {
                final dt = ts.toDate();
                final key =
                    DateFormat('yyyy-MM').format(DateTime(dt.year, dt.month));
                if (monthTotals.containsKey(key)) {
                  monthTotals[key] = monthTotals[key]! + price;
                }
              }
            } else if (overdue) {
              overdueCount++;
            } else {
              pendingCount++;
            }
          }

          final chartData = months
              .map((m) => _MonthSpending(
                  m, monthTotals[DateFormat('yyyy-MM').format(m)] ?? 0.0))
              .toList()
              .reversed
              .toList();
          final series = [
            charts.Series<_MonthSpending, DateTime>(
              id: 'Monthly Spending',
              colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
              domainFn: (d, _) => d.month,
              measureFn: (d, _) => d.amount,
              data: chartData,
            )
          ];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Amount Spent Per Month (Last 12 Months)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 200,
                      child: charts.TimeSeriesChart(
                        series,
                        animate: true,
                        dateTimeFactory: const charts.LocalDateTimeFactory(),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Requests Submitted: $totalRequests',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Total Amount Spent: \$${totalSpent.toStringAsFixed(2)}'),
                    const SizedBox(height: 4),
                    Text('Paid Invoices: $paidCount'),
                    Text('Pending Invoices: $pendingCount'),
                    Text('Overdue Invoices: $overdueCount'),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => _exportCsv(context, docs),
                        child: const Text('Download CSV'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final invoiceNum = data['invoiceNumber'] ?? doc.id;
                    final mechanic = data['mechanicUsername'] ?? 'Unknown';
                    final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
                    final statusField = data['status'];
                    final Timestamp? createdAtTs = data['createdAt'];
                    final Timestamp? closedAtTs = data['closedAt'];
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
                    final price = (data['finalPrice'] as num?)?.toDouble();

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
                                    color: statusColor(status),
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
                            Text('Created: ${formatDate(createdAtTs)}'),
                            if (closedAtTs != null)
                              Text('Completed: ${formatDate(closedAtTs)}'),
                            if (price != null)
                              Text('Final Price: \$${price.toStringAsFixed(2)}'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
