import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Displays a table of location history for a mechanic.
class MechanicLocationHistoryPage extends StatelessWidget {
  final String mechanicId;

  const MechanicLocationHistoryPage({super.key, required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('mechanics')
        .doc(mechanicId)
        .collection('location_history')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Location History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No location history found'));
          }

          final rows = docs.map((doc) {
            final data = doc.data();
            final ts = data['timestamp'];
            final dt = ts is Timestamp ? ts.toDate().toLocal() : DateTime.now();
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            return DataRow(cells: [
              DataCell(Text(DateFormat('MMM d, yyyy h:mm a').format(dt))),
              DataCell(Text(lat?.toStringAsFixed(6) ?? '')),
              DataCell(Text(lng?.toStringAsFixed(6) ?? '')),
            ]);
          }).toList();

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date/Time')),
                DataColumn(label: Text('Latitude')),
                DataColumn(label: Text('Longitude')),
              ],
              rows: rows,
            ),
          );
        },
      ),
    );
  }
}
