import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
  Widget _buildReport(Map<String, dynamic> stats) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
