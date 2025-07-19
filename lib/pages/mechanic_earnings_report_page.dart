import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:charts_flutter/flutter.dart' as charts;

import '../services/csv_downloader.dart';

class _MonthEarning {
  final DateTime month;
  final double earnings;
  _MonthEarning(this.month, this.earnings);
}

class MechanicEarningsReportPage extends StatelessWidget {
  final String mechanicId;
  const MechanicEarningsReportPage({super.key, required this.mechanicId});

  String _currency(double value) {
    return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(value);
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('yyyy-MM-dd').format(dt);
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
    buffer.writeln('Invoice Number,Customer Username,Amount Paid,Date Paid');
    for (final doc in docs) {
      final data = doc.data();
      final invoiceNum = (data['invoiceNumber'] ?? doc.id).toString();
      final customer = (data['customerUsername'] ?? '').toString();
      final amount = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      final date = _formatDate(data['closedAt'] as Timestamp?);
      final row = [
        invoiceNum,
        customer,
        amount.toStringAsFixed(2),
        date,
      ].map(_csvEscape).join(',');
      buffer.writeln(row);
    }
    await downloadCsv(buffer.toString(), fileName: 'earnings.csv');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Earnings CSV exported')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: mechanicId)
        .where('paymentStatus', isEqualTo: 'paid')
        .orderBy('closedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings Report')),
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
            return const Center(child: Text('No paid invoices found'));
          }

          double total = 0.0;
          double monthly = 0.0;
          double highest = 0.0;
          final now = DateTime.now();
          final months = List.generate(
            12,
            (i) => DateTime(now.year, now.month - i, 1),
          );
          final monthTotals = {
            for (final m in months) DateFormat('yyyy-MM').format(m): 0.0
          };
          for (final doc in docs) {
            final data = doc.data();
            final amount = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
            total += amount;
            if (amount > highest) highest = amount;
            final ts = data['closedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;
            if (ts != null) {
              final dt = ts.toDate();
              if (dt.year == now.year && dt.month == now.month) {
                monthly += amount;
              }
              final key = DateFormat('yyyy-MM').format(DateTime(dt.year, dt.month));
              if (monthTotals.containsKey(key)) {
                monthTotals[key] = monthTotals[key]! + amount;
              }
            }
          }
          final paidJobs = docs.length;
          final average = paidJobs > 0 ? total / paidJobs : 0.0;

          final chartData = months
              .map((m) => _MonthEarning(
                    m,
                    monthTotals[DateFormat('yyyy-MM').format(m)] ?? 0.0,
                  ))
              .toList()
              .reversed
              .toList();
          final series = [
            charts.Series<_MonthEarning, DateTime>(
              id: 'Monthly Earnings',
              colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
              domainFn: (d, _) => d.month,
              measureFn: (d, _) => d.earnings,
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
                      'Earnings Per Month (Last 12 Months)',
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
                    Text('Total Earnings: ${_currency(total)}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Earnings This Month: ${_currency(monthly)}'),
                    const SizedBox(height: 4),
                    Text('Paid Jobs: $paidJobs'),
                    const SizedBox(height: 4),
                    Text('Average Payment per Job: ${_currency(average)}'),
                    const SizedBox(height: 4),
                    Text('Highest Single Payment: ${_currency(highest)}'),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ElevatedButton(
                    onPressed: () => _exportCsv(context, docs),
                    child: const Text('Download CSV'),
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final invoiceNum = data['invoiceNumber'] ?? docs[index].id;
                    final amount =
                        (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
                    final date = _formatDate(data['closedAt'] as Timestamp?);
                    final customer = (data['customerUsername'] ?? '').toString();
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Invoice #: $invoiceNum',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text('Amount Paid: ${_currency(amount)}'),
                            if (date.isNotEmpty) Text('Date Paid: $date'),
                            if (customer.isNotEmpty) Text('Customer: $customer'),
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
