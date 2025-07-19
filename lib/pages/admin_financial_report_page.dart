import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import '../services/csv_downloader.dart';

import 'dashboard_page.dart';

class AdminFinancialReportPage extends StatefulWidget {
  final String userId;
  const AdminFinancialReportPage({super.key, required this.userId});

  @override
  State<AdminFinancialReportPage> createState() => _AdminFinancialReportPageState();
}

class _AdminFinancialReportPageState extends State<AdminFinancialReportPage> {
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
    final snapshot = await FirebaseFirestore.instance.collection('invoices').get();
    final now = DateTime.now();

    int paidInvoices = 0;
    double totalPaid = 0.0;
    double monthlyPaid = 0.0;
    double pendingTotal = 0.0;
    double overdueTotal = 0.0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      if (data['flagged'] == true) continue;
      final status = (data['paymentStatus'] ?? 'pending') as String;
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      final Timestamp? createdAtTs = data['createdAt'];
      final Timestamp? closedAtTs = data['closedAt'];
      final date = (closedAtTs ?? createdAtTs)?.toDate();
      final bool thisMonth = date != null &&
          date.year == now.year &&
          date.month == now.month;

      if (status == 'paid') {
        paidInvoices++;
        totalPaid += price;
        if (thisMonth) {
          monthlyPaid += price;
        }
      } else if (status == 'pending') {
        pendingTotal += price;
        if (createdAtTs != null &&
            DateTime.now().difference(createdAtTs.toDate()).inDays > 7) {
          overdueTotal += price;
        }
      }
    }

    final platformRevenueAllTime = totalPaid * 0.15;
    final platformRevenueMonth = monthlyPaid * 0.15;
    final payoutsAllTime = totalPaid * 0.85;
    final payoutsMonth = monthlyPaid * 0.85;
    final averagePayment = paidInvoices > 0 ? totalPaid / paidInvoices : 0.0;

    return {
      'paidInvoices': paidInvoices,
      'platformRevenueAllTime': platformRevenueAllTime,
      'platformRevenueMonth': platformRevenueMonth,
      'payoutsAllTime': payoutsAllTime,
      'payoutsMonth': payoutsMonth,
      'collectedMonth': monthlyPaid,
      'overdueBalance': overdueTotal,
      'pendingPayments': pendingTotal,
      'averagePayment': averagePayment,
      'paidJobs': paidInvoices,
    };
  }
  Future<void> _refresh() async {
    final stats = await _loadStats();
    setState(() {
      _statsFuture = Future.value(stats);
    });
  }

  String _currency(double value) {
    return NumberFormat.currency(locale: 'en_US', symbol: '\$').format(value);
  }

  Widget _statItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

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

  Future<void> _exportInvoices() async {
    final snapshot = await FirebaseFirestore.instance.collection('invoices').get();
    final buffer = StringBuffer();
    buffer.writeln(
        'Invoice Number,Customer Username,Mechanic Username,Final Price,Platform Fee,Payment Status,Created Date,Closed Date');
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final invoiceNum = (data['invoiceNumber'] ?? doc.id).toString();
      final customer = (data['customerUsername'] ?? '').toString();
      final mechanic = (data['mechanicUsername'] ?? '').toString();
      final finalPrice = (data['finalPrice'] as num?)?.toString() ?? '';
      final fee = (data['platformFee'] as num?)?.toString() ?? '';
      final paymentStatus = (data['paymentStatus'] ?? '').toString();
      final created = _formatTimestamp(data['createdAt'] as Timestamp?);
      final closed = _formatTimestamp(data['closedAt'] as Timestamp?);
      final row = [
        invoiceNum,
        customer,
        mechanic,
        finalPrice,
        fee,
        paymentStatus,
        created,
        closed,
      ].map(_csvEscape).join(',');
      buffer.writeln(row);
    }
    await downloadCsv(buffer.toString(), fileName: 'invoices.csv');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice CSV exported')),
      );
    }
  }

  // Data class for monthly revenue totals
  class _MonthRevenue {
    final DateTime month;
    final double total;
    _MonthRevenue(this.month, this.total);
  }

  /// Builds a bar chart showing platform revenue over the last 12 months.
  Widget _buildRevenueChart() {
    final start = DateTime(DateTime.now().year, DateTime.now().month - 11, 1);
    return SizedBox(
      height: 200,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('invoices')
            .where('paymentStatus', isEqualTo: 'paid')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final Map<int, double> totals = {};
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final Timestamp? closedAtTs = data['closedAt'];
            final Timestamp? createdAtTs = data['createdAt'];
            final date = (closedAtTs ?? createdAtTs)?.toDate();
            if (date == null || date.isBefore(start)) continue;
            final key = date.year * 100 + date.month;
            double fee;
            final feeNum = data['platformFee'];
            if (feeNum is num) {
              fee = feeNum.toDouble();
            } else {
              final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
              fee = price * 0.15;
            }
            totals[key] = (totals[key] ?? 0) + fee;
          }

          final List<_MonthRevenue> dataPoints = [];
          for (int i = 0; i < 12; i++) {
            final month = DateTime(start.year, start.month + i, 1);
            final key = month.year * 100 + month.month;
            dataPoints.add(_MonthRevenue(month, totals[key] ?? 0));
          }

          final series = [
            charts.Series<_MonthRevenue, String>(
              id: 'PlatformRevenue',
              colorFn: (_, __) => charts.MaterialPalette.blue.shadeDefault,
              domainFn: (d, _) => DateFormat('MMM').format(d.month),
              measureFn: (d, _) => d.total,
              data: dataPoints,
            )
          ];
          return charts.BarChart(series, animate: true);
        },
      ),
    );
  }
  Widget _buildReport(Map<String, dynamic> stats) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: _exportInvoices,
            child: const Text('Export Invoices as CSV'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'All-Time Totals',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        _statItem('Total Paid Invoices', '${stats['paidInvoices']}'),
        _statItem(
            'Total Platform Revenue',
            _currency(stats['platformRevenueAllTime'] as double)),
        _statItem(
            'Total Payouts to Mechanics',
            _currency(stats['payoutsAllTime'] as double)),
        _statItem('Total Number of Paid Jobs', '${stats['paidJobs']}'),
        const SizedBox(height: 16),
        const Text(
          'This Month',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        _statItem(
            'Total Platform Revenue (This Month)',
            _currency(stats['platformRevenueMonth'] as double)),
        _statItem(
            'Total Payouts to Mechanics (This Month)',
            _currency(stats['payoutsMonth'] as double)),
        _statItem('Total Collected This Month',
            _currency(stats['collectedMonth'] as double)),
        _statItem('Average Payment Per Invoice',
            _currency(stats['averagePayment'] as double)),
        _statItem('Total Overdue Balance',
            _currency(stats['overdueBalance'] as double)),
        _statItem('Total Pending Payments',
            _currency(stats['pendingPayments'] as double)),
        const SizedBox(height: 16),
        const Text(
          'Platform Revenue (Last 12 Months)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        _buildRevenueChart(),
      ],
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

        if (snapshot.data != 'admin') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Access denied.')),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => DashboardPage(userId: widget.userId)),
                (route) => false,
              );
            }
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Financial Reports'),
          ),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, statsSnapshot) {
              if (!statsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: _buildReport(statsSnapshot.data!),
              );
            },
          ),
        );
      },
    );
  }
}
