import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:skiptow/pages/create_invoice_page.dart';

import "../utils.dart";
/// Displays the logged-in mechanic's account information and performance.
class MechanicProfilePage extends StatefulWidget {
  /// The mechanic ID whose profile will be displayed.
  final String mechanicId;

  /// Whether this profile was opened from a referral link.
  final bool referral;

  const MechanicProfilePage({
    super.key,
    required this.mechanicId,
    this.referral = false,
  });

  @override
  State<MechanicProfilePage> createState() => _MechanicProfilePageState();
}

class _MechanicProfilePageState extends State<MechanicProfilePage> {
  late final Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfileData();
  }

  Future<Map<String, dynamic>> _loadProfileData() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.mechanicId)
        .get();
    final userData = userDoc.data() ?? {};

    final invoicesSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.mechanicId)
        .get();

    int completedJobs = 0;
    double totalEarnings = 0.0;
    for (final doc in invoicesSnap.docs) {
      final data = doc.data();
      if (data['flagged'] == true) continue;
      final status = data['status'];
      if (status == 'completed' || status == 'closed') {
        completedJobs++;
      }
      if (data['paymentStatus'] == 'paid') {
        totalEarnings += (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return {
      'username': userData['username'] ?? 'Unknown',
      'email': userData['email'] ?? 'Unknown',
      'createdAt': userData['createdAt'],
      'completedJobs': completedJobs,
      'totalEarnings': totalEarnings,
      'blocked': userData['blocked'] == true,
      'pro': userData['isPro'] == true,
      'isActive': userData['isActive'] == true,
      'unavailable': userData['unavailable'] == true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mechanic Profile')),
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
          final bool blocked = data['blocked'] == true;
          final bool pro = data['pro'] == true;
          final bool isCurrentUser =
              widget.mechanicId == FirebaseAuth.instance.currentUser?.uid;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Username: ${data['username']}'),
                Text('Email: ${data['email']}'),
                Text('Member Since: ${formatDate(data['createdAt'] as Timestamp?)}'),
                if (isCurrentUser)
                  Text('Basic or Pro: ${pro ? 'Pro' : 'Basic'}'),
                const SizedBox(height: 20),
                Text('Total Jobs Completed: ${data['completedJobs']}'),
                Text('Total Earnings: \$${data['totalEarnings'].toStringAsFixed(2)}'),
                Text('Account Status: ${blocked ? 'Blocked' : 'Active'}'),
                if (widget.referral) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Referral Request \u2014 mechanic may still decline.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                  pro
                      ? ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreateInvoicePage(
                                  customerId:
                                      FirebaseAuth.instance.currentUser?.uid ??
                                          '',
                                  mechanicId: widget.mechanicId,
                                  mechanicUsername: data['username'] ?? 'Unnamed',
                                  distance: 0,
                                ),
                              ),
                            );
                          },
                          child: const Text('Request This Mechanic'),
                        )
                      : const Text(
                          'This mechanic does not accept referral requests.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
