import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'dashboard_page.dart';

/// Simple admin dashboard for monitoring the platform.
class AdminDashboardPage extends StatefulWidget {
  final String userId;
  const AdminDashboardPage({super.key, required this.userId});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {

  int _totalUsers = 0;
  int _activeMechanics = 0;
  int _activeInvoices = 0;
  int _completedInvoices = 0;
  int _cancelledInvoices = 0;
  int _platformCompletedJobs = 0;
  int _totalActiveUsers = 0;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _invoiceStream;

  String _appVersion = '1.0.0';

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  @override
  void initState() {
    super.initState();
    _invoiceStream = FirebaseFirestore.instance
        .collection('invoices')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _invoiceSub = _invoiceStream.listen(_updateInvoiceCounts);
    _completedJobsSub = FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _platformCompletedJobs = snapshot.size;
        });
      } else {
        _platformCompletedJobs = snapshot.size;
      }
    });
    _usersSub = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen(_updateActiveUsers);
    _loadStats();
    _loadAppVersion();
  }

  Future<void> _loadStats() async {
    final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
    _totalUsers = usersSnapshot.size;
    _activeMechanics = usersSnapshot.docs
        .where((d) => d.data()['role'] == 'mechanic' && d.data()['isActive'] == true)
        .length;
    _totalActiveUsers = usersSnapshot.docs
        .where((d) =>
            (d.data()['role'] == 'mechanic' && d.data()['isActive'] == true) ||
            d.data()['role'] == 'customer')
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
    _platformCompletedJobs = completedSnap.size;

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

  void _updateActiveUsers(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    int count = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final role = data['role'];
      if (role == 'mechanic') {
        if (data['isActive'] == true) count++;
      } else if (role == 'customer') {
        count++;
      }
    }
    if (!mounted) {
      _totalActiveUsers = count;
      return;
    }
    setState(() {
      _totalActiveUsers = count;
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

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {
      // Keep default version on failure
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Widget _buildStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Users: $_totalUsers'),
        Text('Active Mechanics: $_activeMechanics'),
        Text('Total Active Users: $_totalActiveUsers'),
        Text('Active Invoices: $_activeInvoices'),
        Text('Completed Invoices: $_completedInvoices'),
        Text('Cancelled Invoices: $_cancelledInvoices'),
        Text('Platform Completed Jobs: $_platformCompletedJobs'),
      ],
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  Widget _invoiceTile(Map<String, dynamic> data) {
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

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> active = [];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> completed = [];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> cancelled = [];

        for (final d in docs) {
          final status = d.data()['status'];
          if (status == 'active') {
            active.add(d);
          } else if (status == 'completed') {
            completed.add(d);
          } else if (status == 'cancelled') {
            cancelled.add(d);
          }
        }

        List<Widget> section(String title,
            List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
          if (items.isEmpty) return <Widget>[];
          return [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ...items.map((e) => _invoiceTile(e.data())),
            const Divider(),
          ];
        }

        final children = <Widget>[
          ...section('Active Invoices', active),
          ...section('Completed Invoices', completed),
          ...section('Cancelled Invoices', cancelled),
        ];
        if (children.isNotEmpty && children.last is Divider) {
          children.removeLast();
        }

        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
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
    _completedJobsSub?.cancel();
    _usersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data != 'admin') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Access denied.')),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) => DashboardPage(userId: widget.userId)),
                (route) => false,
              );
            }
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Dashboard'),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _logout,
                tooltip: 'Logout',
              ),
            ],
          ),
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
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'SkipTow Platform Version: $_appVersion',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

