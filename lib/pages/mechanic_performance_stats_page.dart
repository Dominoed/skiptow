import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MechanicPerformanceStatsPage extends StatelessWidget {
  final String mechanicId;
  const MechanicPerformanceStatsPage({super.key, required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    final sessionStream = FirebaseFirestore.instance
        .collection('mechanic_sessions')
        .doc(mechanicId)
        .collection('sessions')
        .orderBy('startTime', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Performance Stats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: sessionStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          final now = DateTime.now();
          final startOfWeek = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          final startOfMonth = DateTime(now.year, now.month, 1);
          double weekHours = 0;
          double monthHours = 0;
          for (final d in docs) {
            final data = d.data();
            final start = (data['startTime'] as Timestamp?)?.toDate();
            final end = (data['endTime'] as Timestamp?)?.toDate() ?? now;
            if (start == null) continue;
            if (end.isBefore(start)) continue;
            if (end.isAfter(startOfWeek)) {
              final from = start.isBefore(startOfWeek) ? startOfWeek : start;
              weekHours += end.difference(from).inMinutes / 60.0;
            }
            if (end.isAfter(startOfMonth)) {
              final from = start.isBefore(startOfMonth) ? startOfMonth : start;
              monthHours += end.difference(from).inMinutes / 60.0;
            }
          }

          final q = FirebaseFirestore.instance
              .collection('invoices')
              .where('mechanicId', isEqualTo: mechanicId)
              .where('paymentStatus', isEqualTo: 'paid')
              .where('closedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth));

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, invSnap) {
              double monthEarnings = 0;
              if (invSnap.hasData) {
                for (final d in invSnap.data!.docs) {
                  if (d.data()['flagged'] == true) continue;
                  monthEarnings += (d.data()['finalPrice'] as num?)?.toDouble() ?? 0.0;
                }
              }
              final hourly = monthHours > 0 ? monthEarnings / monthHours : 0.0;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ListTile(
                    title: const Text('Active Hours This Week'),
                    trailing: Text(weekHours.toStringAsFixed(2)),
                  ),
                  ListTile(
                    title: const Text('Active Hours This Month'),
                    trailing: Text(monthHours.toStringAsFixed(2)),
                  ),
                  ListTile(
                    title: const Text('Est. \$/hr'),
                    trailing: Text(hourly.toStringAsFixed(2)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

