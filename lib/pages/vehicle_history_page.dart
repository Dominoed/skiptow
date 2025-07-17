import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Displays a list of vehicles previously used by the customer
/// in service requests.
class VehicleHistoryPage extends StatelessWidget {
  final String userId;

  const VehicleHistoryPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final Stream<DocumentSnapshot<Map<String, dynamic>>> stream =
        FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('My Vehicles')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final List<dynamic> raw =
              (snapshot.data?.data()?['vehicles'] as List<dynamic>?) ?? [];
          final vehicles = raw
              .whereType<Map<String, dynamic>>()
              .map((car) {
                final year = (car['year'] ?? '').toString();
                final make = (car['make'] ?? '').toString();
                final model = (car['model'] ?? '').toString();
                return [year, make, model]
                    .where((e) => e.isNotEmpty)
                    .join(' ');
              })
              .where((v) => v.isNotEmpty)
              .toList();

          if (vehicles.isEmpty) {
            return const Center(child: Text('No vehicles found'));
          }
          return ListView.builder(
            itemCount: vehicles.length,
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(vehicles[index]),
              );
            },
          );
        },
      ),
    );
  }
}
