import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:charts_flutter/flutter.dart' as charts;

import 'dashboard_page.dart';

class AdminMechanicPerformancePage extends StatefulWidget {
  final String mechanicId;
  final String userId;
  const AdminMechanicPerformancePage({
    super.key,
    required this.mechanicId,
    required this.userId,
  });

  @override
  State<AdminMechanicPerformancePage> createState() => _AdminMechanicPerformancePageState();
}

class _MonthEarnings {
  final DateTime month;
  final double total;
  _MonthEarnings(this.month, this.total);
}

class _AdminMechanicPerformancePageState extends State<AdminMechanicPerformancePage> {
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
        .doc(widget.mechanicId)
        .get();
    final userData = userDoc.data() ?? {};

    // Query all invoices for general stats
    final invoices = await FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.mechanicId)
        .get();

    // Query only paid invoices for the monthly earnings chart
    final paidInvoicesQuery = await FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.mechanicId)
        .where('paymentStatus', isEqualTo: 'paid')
        .get();

    int completed = 0;
    int overdue = 0;
    int paidCount = 0;
    double totalPaid = 0.0;
    double highest = 0.0;
    double fees = 0.0;
    int timeCount = 0;
    int totalMinutes = 0;

    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 11, 1);
    final Map<int, double> monthTotals = {};
    for (int i = 0; i < 12; i++) {
      final m = DateTime(now.year, now.month - i, 1);
      monthTotals[m.year * 100 + m.month] = 0.0;
    }

    for (final doc in invoices.docs) {
      final data = doc.data();
      final status = (data['status'] ?? '') as String;
      final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      final Timestamp? createdAtTs = data['createdAt'];

      if (status == 'completed' || status == 'closed') {
        completed++;
      }

      if (paymentStatus == 'paid') {
        paidCount++;
        totalPaid += price;
        if (price > highest) highest = price;
        fees += (data['platformFee'] as num?)?.toDouble() ?? price * 0.10;
      } else if (paymentStatus == 'pending' &&
          createdAtTs != null &&
          DateTime.now().difference(createdAtTs.toDate()).inDays > 7) {
        overdue++;
      }

      if (paymentStatus == 'paid' || status == 'completed') {
        final Timestamp? start = data['acceptedAt'] ?? data['mechanicAcceptedAt'] ?? data['mechanicAcceptedTimestamp'];
        final Timestamp? end = data['completedAt'] ?? data['jobCompletedTimestamp'] ?? data['closedAt'];
        if (start != null && end != null) {
          totalMinutes += end.toDate().difference(start.toDate()).inMinutes;
          timeCount++;
        }
      }
    }

    for (final doc in paidInvoicesQuery.docs) {
      final data = doc.data();
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      final Timestamp? createdAtTs = data['createdAt'];
      final Timestamp? closedTs = data['closedAt'];
      final date = (closedTs ?? createdAtTs)?.toDate();
      if (date != null && !date.isBefore(start)) {
        final key = date.year * 100 + date.month;
        if (monthTotals.containsKey(key)) {
          monthTotals[key] = monthTotals[key]! + price;
        }
      }
    }

    final avg = paidCount > 0 ? totalPaid / paidCount : 0.0;
    final avgCompletion = timeCount > 0 ? (totalMinutes / timeCount) / 60.0 : 0.0;
    final List<_MonthEarnings> months = [];
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = m.year * 100 + m.month;
      months.add(_MonthEarnings(m, monthTotals[key] ?? 0));
    }

    return {
      'username': userData['username'] ?? 'Unknown',
      'createdAt': userData['createdAt'],
      'blocked': userData['blocked'] == true,
      'flagged': userData['flagged'] == true,
      'totalJobs': completed,
      'totalEarnings': totalPaid,
      'platformFees': fees,
      'averagePayment': avg,
      'averageCompletion': avgCompletion,
      'highestPayment': highest,
      'overdueInvoices': overdue,
      'months': months,
    };
  }

  String _currency(double value) {
    return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(value);
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'N/A';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  Widget _statItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<_MonthEarnings> months) {
    final series = [
      charts.Series<_MonthEarnings, String>(
        id: 'Earnings',
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

  Widget _buildEarningsTable(List<_MonthEarnings> months) {
    return Table(
      columnWidths: const {1: IntrinsicColumnWidth()},
      border: TableBorder.all(color: Colors.grey),
      children: [
        const TableRow(children: [
          Padding(
            padding: EdgeInsets.all(8),
            child:
                Text('Month', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child:
                Text('Earnings', style: TextStyle(fontWeight: FontWeight.bold)),
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
          appBar: AppBar(title: const Text('Mechanic Performance')),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data!;
              final months = data['months'] as List<_MonthEarnings>;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Mechanic Username: ${data['username']}'),
                  Text('User ID: ${widget.mechanicId}'),
                  Text('Registration Date: ${_formatDate(data['createdAt'] as Timestamp?)}'),
                  Text('Blocked: ${data['blocked'] ? 'Yes' : 'No'}'),
                  Text('Flagged: ${data['flagged'] ? 'Yes' : 'No'}'),
                  Text('Suspicious: ${data['suspicious'] ? 'Yes' : 'No'}'),
                  const SizedBox(height: 16),
                  _statItem('Total Jobs Completed', '${data['totalJobs']}'),
                  _statItem('Total Earnings Paid Out', _currency(data['totalEarnings'] as double)),
                  _statItem('Platform Fees Generated', _currency(data['platformFees'] as double)),
                  _statItem('Average Payment Per Job', _currency(data['averagePayment'] as double)),
                  _statItem('Average Completion Time (hrs)', (data['averageCompletion'] as double).toStringAsFixed(2)),
                  _statItem('Highest Single Payment', _currency(data['highestPayment'] as double)),
                  _statItem('Number of Overdue Invoices', '${data['overdueInvoices']}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Earnings Per Month (Last 12 Months)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildChart(months),
                  const SizedBox(height: 8),
                  _buildEarningsTable(months),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
