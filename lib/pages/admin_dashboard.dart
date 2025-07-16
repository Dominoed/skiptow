import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

/// Simple admin dashboard for monitoring the platform.
/// Access is granted only if the [userId] matches [_adminUserId].
class AdminDashboardPage extends StatefulWidget {
  final String userId;
  const AdminDashboardPage({super.key, required this.userId});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  /// TODO: Replace with your real admin UID.
  static const String _adminUserId = 'ADMIN_USER_ID';

  int _totalUsers = 0;
  int _activeMechanics = 0;
  int _activeInvoices = 0;
  int _completedInvoices = 0;
  int _cancelledInvoices = 0;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSub;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _invoiceStream;

  @override
  void initState() {
    super.initState();
    _invoiceStream = FirebaseFirestore.instance
        .collection('invoices')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _invoiceSub = _invoiceStream.listen(_updateInvoiceCounts);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    _totalUsers = usersSnapshot.size;
    _activeMechanics = usersSnapshot.docs
        .where((d) => d.data()['role'] == 'mechanic' && d.data()['isActive'] == true)
        .length;

    final activeSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'active')
        .get();
    _activeInvoices = activeSnap.size;

    final completedSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'completed')
        .get();
    _completedInvoices = completedSnap.size;

    final cancelledSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'cancelled')
        .get();
    _cancelledInvoices = cancelledSnap.size;
    if (mounted) setState(() {});
  }

  void _updateInvoiceCounts(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    int active = 0;
    int completed = 0;
    int cancelled = 0;
    for (final doc in snapshot.docs) {
      final status = doc.data()['status'];
      if (status == 'active') {
        active++;
      } else if (status == 'completed') {
        completed++;
      } else if (status == 'cancelled') {
        cancelled++;
      }
    }
    if (!mounted) {
      _activeInvoices = active;
      _completedInvoices = completed;
      _cancelledInvoices = cancelled;
      return;
    }
    setState(() {
      _activeInvoices = active;
      _completedInvoices = completed;
      _cancelledInvoices = cancelled;
    });
  }

  Future<void> _refresh() async {
    await _loadStats();
  }

  Future<void> _deactivateMechanic(String mechId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(mechId)
        .update({'isActive': false});
    await _loadStats();
  }

  Widget _buildStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Users: $_totalUsers'),
        Text('Active Mechanics: $_activeMechanics'),
        Text('Active Invoices: $_activeInvoices'),
        Text('Completed Invoices: $_completedInvoices'),
        Text('Cancelled Invoices: $_cancelledInvoices'),
      ],
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  Widget _buildInvoices() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _invoiceStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Text('No invoices');
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            return ListTile(
              title: Text('Mechanic: ${data['mechanicId']}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer: ${data['customerId']}'),
                  Text('Status: ${data['status']}'),
                  Text('Submitted: ${_formatDate(data['timestamp'])}'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveMechanics() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mechanic')
          .where('isActive', isEqualTo: true)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Active Mechanics'),
            ),
            ...docs.map((d) {
              return ListTile(
                title: Text(d.data()['username'] ?? d.id),
                subtitle: Text(d.id),
                trailing: IconButton(
                  icon: const Icon(Icons.block),
                  onPressed: () => _deactivateMechanic(d.id),
                  tooltip: 'Deactivate',
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _invoiceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId != _adminUserId) {
      return const Scaffold(
        body: Center(child: Text('Access denied')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStats(),
              const SizedBox(height: 16),
              const Divider(),
              const Text('Invoices', style: TextStyle(fontSize: 16)),
              _buildInvoices(),
              _buildActiveMechanics(),
            ],
          ),
        ),
      ),
    );
  }
}

