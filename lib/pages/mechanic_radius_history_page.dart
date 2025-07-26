import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import "../utils.dart";
/// Displays the history of radius changes for a mechanic.
class MechanicRadiusHistoryPage extends StatelessWidget {
  final String mechanicId;

  const MechanicRadiusHistoryPage({super.key, required this.mechanicId});

  String formatDate(Timestamp? ts) {
  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('mechanics')
        .doc(mechanicId)
        .collection('radius_history')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Radius History')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
      ),
    );
  }
}
