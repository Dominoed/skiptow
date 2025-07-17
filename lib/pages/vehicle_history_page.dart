import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Displays a list of vehicles previously used by the customer
/// in service requests.
class VehicleHistoryPage extends StatelessWidget {
  final String userId;

  const VehicleHistoryPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot<Map<String, dynamic>>> stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('My Vehicles')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final Set<String> uniqueVehicles = {};
          for (var d in docs) {
            final data = d.data();
            final car = data['carInfo'] ?? {};
            final year = (car['year'] ?? '').toString();
            final make = (car['make'] ?? '').toString();
            final model = (car['model'] ?? '').toString();
            final vehicle = [year, make, model].where((e) => e.isNotEmpty).join(' ');
            if (vehicle.isNotEmpty) {
              uniqueVehicles.add(vehicle);
            }
          }

          if (uniqueVehicles.isEmpty) {
            return const Center(child: Text('No vehicles found'));
          }

          final vehicles = uniqueVehicles.toList();
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
