import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import "../utils.dart";

/// Displays the logged-in customer's basic profile information.
class CustomerProfilePage extends StatefulWidget {
  final String userId;

  const CustomerProfilePage({super.key, required this.userId});

  @override
  State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
  late final Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfileData();
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final userData = userDoc.data() ?? {};

    final invoicesSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .get();

    int totalRequests = 0;
    double totalPaid = 0.0;
    for (final doc in invoicesSnap.docs) {
      final data = doc.data();
      if (data['flagged'] == true) continue;
      totalRequests++;
      if (data['paymentStatus'] == 'paid') {
        totalPaid += (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return {
      'username': userData['username'] ?? 'Unknown',
      'email': userData['email'] ?? 'Unknown',
      'createdAt': userData['createdAt'],
      'totalRequests': totalRequests,
      'totalPaid': totalPaid,
    };
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('Profile not found'));
          }

          final data = snapshot.data!;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Username: ${data['username']}'),
                Text('Email: ${data['email']}'),
                Text('Member Since: ${formatDate(data['createdAt'] as Timestamp?)}'),
                const SizedBox(height: 20),
                Text('Total Service Requests: ${data['totalRequests']}'),
                Text('Total Paid: \$${data['totalPaid'].toStringAsFixed(2)}'),
              ],
            ),
          );
        },
      ),
    );
  }
}
