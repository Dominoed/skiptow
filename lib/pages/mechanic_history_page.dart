import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils.dart';

/// Combined history page for mechanics showing location and radius history.
class MechanicHistoryPage extends StatelessWidget {
  final String mechanicId;
  const MechanicHistoryPage({super.key, required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Location History'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Location'),
              Tab(text: 'Radius'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LocationHistoryTab(mechanicId: mechanicId),
            _RadiusHistoryTab(mechanicId: mechanicId),
          ],
        ),
      ),
    );
  }
}

class _LocationHistoryTab extends StatelessWidget {
  final String mechanicId;
  const _LocationHistoryTab({required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('mechanics')
        .doc(mechanicId)
        .collection('location_history')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date/Time')),
                DataColumn(label: Text('Latitude')),
                DataColumn(label: Text('Longitude')),
              ],
              rows: rows,
            ),
          ),
        );
      },
    );
  }
}

class _RadiusHistoryTab extends StatelessWidget {
  final String mechanicId;
  const _RadiusHistoryTab({required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('mechanics')
        .doc(mechanicId)
        .collection('radius_history')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No radius changes found'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final radius = (data['newRadiusMiles'] as num?)?.toDouble() ?? 0.0;
            final ts = data['timestamp'] as Timestamp?;
            return ListTile(
              leading: const Icon(Icons.radio_button_checked),
              title: Text('Radius: ${radius.toStringAsFixed(0)} miles'),
              subtitle: Text(formatDate(ts)),
            );
          },
        );
      },
    );
  }
}
