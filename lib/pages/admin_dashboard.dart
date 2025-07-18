import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
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
  int _closedInvoices = 0;
  int _flaggedInvoices = 0;
  int _overdueInvoices = 0;
  int _totalActiveUsers = 0;
  int _paidInvoices = 0;
  double _totalPaidAmount = 0.0;
  double _averagePaidAmount = 0.0;
  double _unpaidOutstanding = 0.0;
  double _overdueBalance = 0.0;
  double _monthlyCollected = 0.0;

  // Cache of userId to username for quick lookups
  Map<String, String> _usernames = {};

  // Current search query for invoices
  String _invoiceSearch = '';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _invoiceStream;
  String _paymentStatusFilter = 'all';

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
        .where('status', whereIn: ['completed', 'closed'])
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
    final Map<String, String> nameMap = {};
    _activeMechanics = usersSnapshot.docs
        .where((d) => d.data()['role'] == 'mechanic' && d.data()['isActive'] == true)
        .length;
    _totalActiveUsers = usersSnapshot.docs
        .where((d) =>
            (d.data()['role'] == 'mechanic' && d.data()['isActive'] == true) ||
            d.data()['role'] == 'customer')
        .length;
    for (final d in usersSnapshot.docs) {
      final data = d.data();
      final username = (data['username'] ?? data['displayName'] ?? '').toString();
      nameMap[d.id] = username;
    }
    _usernames = nameMap;

    final activeSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'active')
        .get();
    _activeInvoices = activeSnap.size;

    final completedSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', whereIn: ['completed', 'closed'])
        .get();
    _completedInvoices = completedSnap.size;
    _platformCompletedJobs = completedSnap.size;

    final cancelledSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'cancelled')
        .get();
    _cancelledInvoices = cancelledSnap.size;

    final closedSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'closed')
        .get();
    _closedInvoices = closedSnap.size;

    final paidSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('paymentStatus', isEqualTo: 'paid')
        .get();
    _paidInvoices = paidSnap.size;
    double total = 0.0;
    double monthlyTotal = 0.0;
    final now = DateTime.now();
    for (final doc in paidSnap.docs) {
      final data = doc.data();
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      total += price;
      final Timestamp? closedTs = data['closedAt'];
      if (closedTs != null) {
        final dt = closedTs.toDate();
        if (dt.year == now.year && dt.month == now.month) {
          monthlyTotal += price;
        }
      }
    }
    _totalPaidAmount = total;
    _monthlyCollected = monthlyTotal;
    _averagePaidAmount =
        _paidInvoices > 0 ? _totalPaidAmount / _paidInvoices : 0.0;

    final pendingSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('paymentStatus', isEqualTo: 'pending')
        .get();
    double outstanding = 0.0;
    for (final doc in pendingSnap.docs) {
      outstanding += (doc.data()['finalPrice'] as num?)?.toDouble() ?? 0.0;
    }
    _unpaidOutstanding = outstanding;

    final flaggedSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('flagged', isEqualTo: true)
        .get();
    _flaggedInvoices = flaggedSnap.size;

    final overdueSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('paymentStatus', isEqualTo: 'pending')
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(
            DateTime.now().subtract(const Duration(days: 7)),
          ),
        )
        .get();
    _overdueInvoices = overdueSnap.size;
    double overdueTotal = 0.0;
    for (final doc in overdueSnap.docs) {
      overdueTotal += (doc.data()['finalPrice'] as num?)?.toDouble() ?? 0.0;
    }
    _overdueBalance = overdueTotal;
    if (mounted) setState(() {});
  }

  void _updateInvoiceCounts(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    int active = 0;
    int completed = 0;
    int cancelled = 0;
    int closed = 0;
    int flagged = 0;
    int overdue = 0;
    int paid = 0;
    double total = 0.0;
    double monthlyTotal = 0.0;
    double pendingTotal = 0.0;
    double overdueTotal = 0.0;
    final now = DateTime.now();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'];
      final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
      if (status == 'active') {
        active++;
      } else if (status == 'completed') {
        completed++;
      } else if (status == 'closed') {
        completed++;
        closed++;
      } else if (status == 'cancelled') {
        cancelled++;
      }
      if (data['flagged'] == true) flagged++;
      final Timestamp? createdAtTs = data['createdAt'];
      if (paymentStatus == 'pending' &&
          createdAtTs != null &&
          DateTime.now().difference(createdAtTs.toDate()).inDays > 7) {
        overdue++;
        overdueTotal += (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      }
      if (paymentStatus == 'paid') {
        paid++;
        final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
        total += price;
        final Timestamp? closedTs = data['closedAt'];
        if (closedTs != null) {
          final dt = closedTs.toDate();
          if (dt.year == now.year && dt.month == now.month) {
            monthlyTotal += price;
          }
        }
      } else if (paymentStatus == 'pending') {
        pendingTotal += (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final avg = paid > 0 ? total / paid : 0.0;
    if (!mounted) {
      _activeInvoices = active;
      _completedInvoices = completed;
      _cancelledInvoices = cancelled;
      _closedInvoices = closed;
      _flaggedInvoices = flagged;
      _overdueInvoices = overdue;
      _paidInvoices = paid;
      _totalPaidAmount = total;
      _monthlyCollected = monthlyTotal;
      _averagePaidAmount = avg;
      _unpaidOutstanding = pendingTotal;
      _overdueBalance = overdueTotal;
      return;
    }
    setState(() {
      _activeInvoices = active;
      _completedInvoices = completed;
      _cancelledInvoices = cancelled;
      _closedInvoices = closed;
      _flaggedInvoices = flagged;
      _overdueInvoices = overdue;
      _paidInvoices = paid;
      _totalPaidAmount = total;
      _monthlyCollected = monthlyTotal;
      _averagePaidAmount = avg;
      _unpaidOutstanding = pendingTotal;
      _overdueBalance = overdueTotal;
    });
  }

  void _updateActiveUsers(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    int count = 0;
    final Map<String, String> nameMap = {};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final role = data['role'];
      final username = (data['username'] ?? data['displayName'] ?? '').toString();
      nameMap[doc.id] = username;
      if (role == 'mechanic') {
        if (data['isActive'] == true) count++;
      } else if (role == 'customer') {
        count++;
      }
    }
    if (!mounted) {
      _totalActiveUsers = count;
      _usernames = nameMap;
      return;
    }
    setState(() {
      _totalActiveUsers = count;
      _usernames = nameMap;
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
        Text('Total Paid Requests: $_paidInvoices'),
        Text(
          'Total Payments Collected: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_totalPaidAmount)}',
        ),
        Text(
          'Payments Collected This Month: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_monthlyCollected)}',
        ),
        Text(
          'Average Payment Per Job: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_averagePaidAmount)}',
        ),
        Text(
          'Unpaid Balance Outstanding: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_unpaidOutstanding)}',
        ),
        Text('Cancelled Invoices: $_cancelledInvoices'),
        Text('Overdue Invoices: $_overdueInvoices'),
        Text(
          'Total Overdue Balance: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_overdueBalance)}',
        ),
        Text('Flagged Invoices: $_flaggedInvoices'),
        Text('Platform Completed Jobs: $_platformCompletedJobs'),
        Text('Total Requests Closed: $_closedInvoices'),
      ],
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  Color _paymentStatusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _flagInvoice(String id) async {
    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(id)
        .update({'flagged': true});
  }

  Future<void> _confirmDeleteInvoice(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: const Text(
            'Are you sure? This will permanently delete the invoice.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(id)
          .delete();
    }
  }

  Widget _invoiceTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final flagged = data['flagged'] == true;
    final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
    final Timestamp? createdAtTs = data['createdAt'];
    final bool overdue = paymentStatus == 'pending' &&
        createdAtTs != null &&
        DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
    return Container(
      color: overdue ? Colors.red.shade50 : null,
      child: ListTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mechanic: ${data['mechanicId']}'),
            Text(
              'Invoice #: ${data['invoiceNumber'] ?? doc.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Customer: ${data['customerId']}'),
            Text('Status: ${data['status']}'),
            Row(
              children: [
                const Text('Payment Status: '),
                Text(
                  paymentStatus,
                  style: TextStyle(
                    color: _paymentStatusColor(paymentStatus),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (overdue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Chip(
                  label: const Text(
                    'OVERDUE',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                ),
              ),
            Text('Submitted: ${_formatDate(data['timestamp'])}'),
            if (data['closedAt'] != null)
              Text('Closed: ${_formatDate(data['closedAt'])}'),
            Text('Flagged: ${flagged ? 'Yes' : 'No'}'),
            if ((data['customerReview'] ?? '').toString().isNotEmpty)
              Text('Customer Review: ${data['customerReview']}')
            else
              const Text('No review.'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.flag),
              onPressed: flagged ? null : () => _flagInvoice(doc.id),
              tooltip: 'Flag Invoice',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _confirmDeleteInvoice(doc.id),
              tooltip: 'Delete Invoice',
            ),
          ],
        ),
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
        final filteredDocs = docs.where((d) {
          final data = d.data();
          final payment = (data['paymentStatus'] ?? 'pending') as String;
          final Timestamp? createdAtTs = data['createdAt'];
          final bool isOverdue = payment == 'pending' &&
              createdAtTs != null &&
              DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
          if (_paymentStatusFilter == 'all') return true;
          if (_paymentStatusFilter == 'overdue') return isOverdue;
          return payment == _paymentStatusFilter;
        }).toList();
        final searchLower = _invoiceSearch.toLowerCase();
        final searchDocs = filteredDocs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final invoiceNum = (data['invoiceNumber'] ?? '').toString().toLowerCase();
          final mechName = (data['mechanicUsername'] ??
                  _usernames[data['mechanicId']] ??
                  '')
              .toString()
              .toLowerCase();
          final custName = (_usernames[data['customerId']] ?? '')
              .toLowerCase();
          return invoiceNum.contains(searchLower) ||
              mechName.contains(searchLower) ||
              custName.contains(searchLower);
        }).toList();
        if (searchDocs.isEmpty) {
          return const Text('No invoices');
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> active = [];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> completed = [];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> cancelled = [];

        for (final d in searchDocs) {
          final status = d.data()['status'];
          if (status == 'active') {
            active.add(d);
          } else if (status == 'completed' || status == 'closed') {
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
            ...items.map((e) => _invoiceTile(e)),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search Invoices',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _invoiceSearch = value;
                        });
                      },
                    ),
                  ),
                  Row(
                    children: [
                      const Text('Filter by Payment Status: '),
                      DropdownButton<String>(
                        value: _paymentStatusFilter,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(value: 'pending', child: Text('Pending')),
                          DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _paymentStatusFilter = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
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

