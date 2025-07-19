import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Displays detailed account information for any user.
class AdminUserDetailPage extends StatefulWidget {
  final String userId;

  const AdminUserDetailPage({super.key, required this.userId});

  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage> {
  late Future<Map<String, dynamic>> _detailsFuture;
  bool _isBlocked = false;
  bool _isFlagged = false;
  bool _isSuspicious = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  Future<Map<String, dynamic>> _loadDetails() async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final userData = userDoc.data() ?? {};
    final role = userData['role'] ?? 'customer';
    setState(() {
      _isBlocked = userData['blocked'] == true;
      _isFlagged = userData['flagged'] == true;
      _isSuspicious = userData['suspicious'] == true;
    });

    int completedJobs = 0;
    double totalEarnings = 0.0;
    int totalRequests = 0;
    double totalPaid = 0.0;

    if (role == 'mechanic') {
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('mechanicId', isEqualTo: widget.userId)
          .get();
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
    } else {
      final invoicesSnap = await FirebaseFirestore.instance
          .collection('invoices')
          .where('customerId', isEqualTo: widget.userId)
          .get();
      for (final doc in invoicesSnap.docs) {
        final data = doc.data();
        if (data['flagged'] == true) continue;
        totalRequests++;
        if (data['paymentStatus'] == 'paid') {
          totalPaid += (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    return {
      'username': userData['username'] ?? 'Unknown',
      'email': userData['email'] ?? 'Unknown',
      'createdAt': userData['createdAt'],
      'role': role,
      'blocked': userData['blocked'] == true,
      'flagged': userData['flagged'] == true,
      'suspicious': userData['suspicious'] == true,
      'completedJobs': completedJobs,
      'totalEarnings': totalEarnings,
      'totalRequests': totalRequests,
      'totalPaid': totalPaid,
    };
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return 'N/A';
    final dt = ts.toDate().toLocal();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  Future<void> _toggleBlock() async {
    final newStatus = !_isBlocked;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'blocked': newStatus});
    setState(() {
      _isBlocked = newStatus;
      _detailsFuture = _loadDetails();
    });
  }

  Future<void> _toggleFlag() async {
    final newStatus = !_isFlagged;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'flagged': newStatus});
    setState(() {
      _isFlagged = newStatus;
      _detailsFuture = _loadDetails();
    });
  }

  Future<void> _toggleSuspicious() async {
    final newStatus = !_isSuspicious;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'suspicious': newStatus});
    setState(() {
      _isSuspicious = newStatus;
      _detailsFuture = _loadDetails();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Details')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('User not found'));
          }

          final data = snapshot.data!;
          final role = data['role'] ?? 'customer';

          final List<Widget> children = [];

          if (_isBlocked) {
            children.add(
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.red,
                child: const Text(
                  '🚫 BLOCKED ACCOUNT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
            children.add(const SizedBox(height: 8));
          }

          if (_isFlagged) {
            children.add(
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.yellow,
                child: const Text(
                  '⚠️ FLAGGED ACCOUNT',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
            children.add(const SizedBox(height: 8));
          }

          if (_isSuspicious) {
            children.add(
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.red,
                child: const Text(
                  'SUSPICIOUS ACCOUNT',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
            children.add(const SizedBox(height: 8));
          }

          children.addAll([
            Text('Username: ${data['username']}'),
            Text('User ID: ${widget.userId}'),
            Text('Email: ${data['email']}'),
            Text('Role: $role'),
            Text('Account Created: ${_formatDate(data['createdAt'] as Timestamp?)}'),
            Text('Blocked: ${data['blocked'] == true ? 'Yes' : 'No'}'),
            Text('Flagged: ${data['flagged'] == true ? 'Yes' : 'No'}'),
            Text('Suspicious: ${data['suspicious'] == true ? 'Yes' : 'No'}'),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _toggleBlock,
              child: Text(_isBlocked ? 'Unblock Account' : 'Block Account'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _toggleFlag,
              child: Text(_isFlagged ? 'Remove Flag' : 'Flag Account'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _toggleSuspicious,
              child:
                  Text(_isSuspicious ? 'Unmark Suspicious' : 'Mark as Suspicious Account'),
            ),
            const SizedBox(height: 20),
          ];

          if (role == 'mechanic') {
            children.addAll([
              Text('Total Jobs Completed: ${data['completedJobs']}'),
              Text('Total Earnings: \$${(data['totalEarnings'] as double).toStringAsFixed(2)}'),
            ]);
          } else {
            children.addAll([
              Text('Total Service Requests: ${data['totalRequests']}'),
              Text('Total Amount Paid: \$${(data['totalPaid'] as double).toStringAsFixed(2)}'),
            ]);
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        },
      ),
    );
  }
}
