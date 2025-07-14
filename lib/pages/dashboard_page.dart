import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'mechanic_dashboard.dart';
import 'customer_dashboard.dart';

class DashboardPage extends StatelessWidget {
  final String userId;
  const DashboardPage({super.key, required this.userId});

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (doc.exists) {
      return doc.data()?['role'];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data;
        if (role == 'mechanic') {
          return MechanicDashboard(userId: userId);
        } else if (role == 'customer') {
          return CustomerDashboard(userId: userId);
        } else {
          return const Scaffold(
            body: Center(child: Text('❌ Unknown role or error')),
          );
        }
      },
    );
  }
}
