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
  int _totalCustomers = 0;
  int _totalMechanics = 0;
  int _activeMechanics = 0;
  int _activeInvoices = 0;
  int _completedInvoices = 0;
  int _cancelledInvoices = 0;
  int _platformCompletedJobs = 0;
  int _closedInvoices = 0;
  int _flaggedInvoices = 0;
  int _overdueInvoices = 0;
  int _blockedMechanics = 0;
  int _flaggedMechanics = 0;
  int _flaggedCustomers = 0;
  int _blockedUsers = 0;
  int _totalActiveUsers = 0;
  int _newCustomers = 0;
  int _newMechanics = 0;
  int _paidInvoices = 0;
  double _totalPaidAmount = 0.0;
  double _averagePaidAmount = 0.0;
  double _unpaidOutstanding = 0.0;
  double _overdueBalance = 0.0;
  double _monthlyCollected = 0.0;
  double _monthlyServiceTotal = 0.0;
  double _monthlyPayoutEstimate = 0.0;
  double _platformRevenueEstimate = 0.0;
  double _totalPlatformRevenue = 0.0;
  double _allTimePlatformFees = 0.0;
  int _monthlyInvoices = 0;
  double _monthlyPlatformFees = 0.0;

  // Cache of userId to username for quick lookups
  Map<String, String> _usernames = {};

  // Current search query for invoices
  String _invoiceSearch = '';

  // Current search query for users
  String _userSearch = '';

  // Current role filter for users
  String _userRoleFilter = 'all';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newMechanicsSub;

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
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    _newMechanicsSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'mechanic')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('createdAt', isLessThan: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _newMechanics = snapshot.size;
        });
      } else {
        _newMechanics = snapshot.size;
      }
    });
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
    _totalMechanics = usersSnapshot.docs
        .where((d) => d.data()['role'] == 'mechanic')
        .length;
    _totalCustomers = usersSnapshot.docs
        .where((d) => d.data()['role'] == 'customer')
        .length;
    _totalActiveUsers = usersSnapshot.docs
        .where((d) =>
            (d.data()['role'] == 'mechanic' && d.data()['isActive'] == true) ||
            d.data()['role'] == 'customer')
        .length;
    final now = DateTime.now();
    _newCustomers = usersSnapshot.docs.where((d) {
      final data = d.data();
      if (data['role'] != 'customer') return false;
      final Timestamp? ts = data['createdAt'];
      if (ts == null) return false;
      final dt = ts.toDate();
      return dt.year == now.year && dt.month == now.month;
    }).length;
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    final newMechSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'mechanic')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('createdAt', isLessThan: Timestamp.fromDate(endOfMonth))
        .get();
    _newMechanics = newMechSnap.size;
    for (final d in usersSnapshot.docs) {
      final data = d.data();
      final username = (data['username'] ?? data['displayName'] ?? '').toString();
      nameMap[d.id] = username;
    }
    _usernames = nameMap;
    _blockedMechanics = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'mechanic' && d.data()['blocked'] == true)
        .length;
    _blockedUsers = usersSnapshot.docs
        .where((d) => d.data()['blocked'] == true)
        .length;
    _flaggedMechanics = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'mechanic' && d.data()['flagged'] == true)
        .length;
    _flaggedCustomers = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'customer' && d.data()['flagged'] == true)
        .length;

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

    final monthlySnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('createdAt', isLessThan: Timestamp.fromDate(endOfMonth))
        .get();
    _monthlyInvoices = monthlySnap.size;

    final closedSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('status', isEqualTo: 'closed')
        .get();
    _closedInvoices = closedSnap.size;
    double monthlyServiceTotal = 0.0;
    double monthlyPlatformFees = 0.0;
    for (final doc in closedSnap.docs) {
      final data = doc.data();
      final Timestamp? closedTs = data['closedAt'];
      if (closedTs != null) {
        final dt = closedTs.toDate();
        if (dt.year == now.year && dt.month == now.month) {
          monthlyServiceTotal +=
              (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
          monthlyPlatformFees +=
              (data['platformFee'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    _monthlyServiceTotal = monthlyServiceTotal;
    _platformRevenueEstimate = monthlyServiceTotal * 0.15;
    _monthlyPlatformFees = monthlyPlatformFees;

    final paidSnap = await FirebaseFirestore.instance
        .collection('invoices')
        .where('paymentStatus', isEqualTo: 'paid')
        .get();
    _paidInvoices = paidSnap.size;
    double total = 0.0;
    double monthlyTotal = 0.0;
    double allTimeFees = 0.0;
    for (final doc in paidSnap.docs) {
      final data = doc.data();
      final price = (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
      total += price;
      if (data['status'] == 'closed') {
        allTimeFees += (data['platformFee'] as num?)?.toDouble() ?? 0.0;
      }
      final Timestamp? closedTs = data['closedAt'];
      if (closedTs != null) {
        final dt = closedTs.toDate();
        if (dt.year == now.year && dt.month == now.month) {
          monthlyTotal += price;
        }
      }
    }
    _totalPaidAmount = total;
    _totalPlatformRevenue = total * 0.15;
    _monthlyCollected = monthlyTotal;
    _monthlyPayoutEstimate = monthlyTotal * 0.85;
    _averagePaidAmount =
        _paidInvoices > 0 ? _totalPaidAmount / _paidInvoices : 0.0;
    _allTimePlatformFees = allTimeFees;

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
    double monthlyServiceTotal = 0.0;
    double monthlyPlatformFees = 0.0;
    int monthlyInvoices = 0;
    double pendingTotal = 0.0;
    double overdueTotal = 0.0;
    double monthlyPayout = 0.0;
    double allTimeFees = 0.0;
    final now = DateTime.now();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'];
      final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
      final Timestamp? closedTs = data['closedAt'];
      if (status == 'active') {
        active++;
      } else if (status == 'completed') {
        completed++;
      } else if (status == 'closed') {
        completed++;
        closed++;
        if (closedTs != null) {
          final dt = closedTs.toDate();
          if (dt.year == now.year && dt.month == now.month) {
            monthlyServiceTotal +=
                (data['finalPrice'] as num?)?.toDouble() ?? 0.0;
          }
        }
      } else if (status == 'cancelled') {
        cancelled++;
      }
      if (data['flagged'] == true) flagged++;
      if (closedTs != null) {
        final dt = closedTs.toDate();
        if (dt.year == now.year && dt.month == now.month) {
          monthlyPlatformFees +=
              (data['platformFee'] as num?)?.toDouble() ?? 0.0;
        }
      }
      final Timestamp? createdAtTs = data['createdAt'];
      if (createdAtTs != null) {
        final createdDt = createdAtTs.toDate();
        if (createdDt.year == now.year && createdDt.month == now.month) {
          monthlyInvoices++;
        }
      }
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
        if (status == 'closed') {
          allTimeFees += (data['platformFee'] as num?)?.toDouble() ?? 0.0;
        }
        final Timestamp? closedTs = data['closedAt'];
        if (closedTs != null) {
          final dt = closedTs.toDate();
          if (dt.year == now.year && dt.month == now.month) {
            monthlyTotal += price;
            monthlyPayout += price;
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
      _totalPlatformRevenue = total * 0.15;
      _monthlyCollected = monthlyTotal;
      _monthlyServiceTotal = monthlyServiceTotal;
      _platformRevenueEstimate = monthlyServiceTotal * 0.15;
      _monthlyPayoutEstimate = monthlyPayout * 0.85;
      _averagePaidAmount = avg;
      _unpaidOutstanding = pendingTotal;
      _overdueBalance = overdueTotal;
      _monthlyInvoices = monthlyInvoices;
      _monthlyPlatformFees = monthlyPlatformFees;
      _allTimePlatformFees = allTimeFees;
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
      _totalPlatformRevenue = total * 0.15;
      _monthlyCollected = monthlyTotal;
      _monthlyServiceTotal = monthlyServiceTotal;
      _platformRevenueEstimate = monthlyServiceTotal * 0.15;
      _monthlyPayoutEstimate = monthlyPayout * 0.85;
      _averagePaidAmount = avg;
      _unpaidOutstanding = pendingTotal;
      _overdueBalance = overdueTotal;
      _monthlyInvoices = monthlyInvoices;
      _monthlyPlatformFees = monthlyPlatformFees;
      _allTimePlatformFees = allTimeFees;
    });
  }

  void _updateActiveUsers(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    int count = 0;
    int mechCount = 0;
    int newCount = 0;
    int blockedCount = 0;
    int blockedCustomerCount = 0;
    int flaggedCount = 0;
    int flaggedCustomerCount = 0;
    int customerCount = 0;
    int mechanicCount = 0;
    final Map<String, String> nameMap = {};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final role = data['role'];
      final username = (data['username'] ?? data['displayName'] ?? '').toString();
      nameMap[doc.id] = username;
      if (role == 'mechanic') {
        mechanicCount++;
        if (data['isActive'] == true) {
          count++;
          mechCount++;
        }
        if (data['blocked'] == true) blockedCount++;
        if (data['flagged'] == true) flaggedCount++;
      } else if (role == 'customer') {
        customerCount++;
        count++;
        if (data['blocked'] == true) blockedCustomerCount++;
        if (data['flagged'] == true) flaggedCustomerCount++;
        final Timestamp? ts = data['createdAt'];
        if (ts != null) {
          final dt = ts.toDate();
          final now = DateTime.now();
          if (dt.year == now.year && dt.month == now.month) {
            newCount++;
          }
        }
      }
    }
    final totalBlocked = blockedCount + blockedCustomerCount;
    if (!mounted) {
      _totalActiveUsers = count;
      _activeMechanics = mechCount;
      _usernames = nameMap;
      _newCustomers = newCount;
      _blockedMechanics = blockedCount;
      _blockedUsers = totalBlocked;
      _flaggedMechanics = flaggedCount;
      _flaggedCustomers = flaggedCustomerCount;
      _totalCustomers = customerCount;
      _totalMechanics = mechanicCount;
      return;
    }
    setState(() {
      _totalActiveUsers = count;
      _activeMechanics = mechCount;
      _usernames = nameMap;
      _newCustomers = newCount;
      _blockedMechanics = blockedCount;
      _blockedUsers = totalBlocked;
      _flaggedMechanics = flaggedCount;
      _flaggedCustomers = flaggedCustomerCount;
      _totalCustomers = customerCount;
      _totalMechanics = mechanicCount;
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

  Future<void> _blockMechanic(String mechId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(mechId)
        .update({'blocked': true});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mechanic blocked')),
      );
    }
  }

  Future<void> _unblockMechanic(String mechId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(mechId)
        .update({'blocked': false});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mechanic unblocked')),
      );
    }
  }

  Future<void> _unflagMechanic(String mechId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(mechId)
        .update({'flagged': false});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flag removed')),
      );
    }
  }

  Future<void> _flagCustomer(String customerId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(customerId)
        .update({'flagged': true});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer flagged')),
      );
    }
  }

  Future<void> _unflagCustomer(String customerId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(customerId)
        .update({'flagged': false});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flag removed')),
      );
    }
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
        Text('Active Mechanics Right Now: $_activeMechanics'),
        Text('Blocked Mechanics: $_blockedMechanics'),
        Text('Blocked Accounts: $_blockedUsers'),
        Text('Flagged Mechanics: $_flaggedMechanics'),
        Text('Flagged Customers: $_flaggedCustomers'),
        Text('Total Active Users: $_totalActiveUsers'),
        Text('New Customers This Month: $_newCustomers'),
        Text('New Mechanics This Month: $_newMechanics'),
        Text('Active Invoices: $_activeInvoices'),
        Text('Completed Invoices: $_completedInvoices'),
        Text('Total Requests This Month: $_monthlyInvoices'),
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
          'Platform Fees Collected This Month: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_monthlyPlatformFees)}',
        ),
        Text(
          'Estimated Payout to Mechanics: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_monthlyPayoutEstimate)}',
        ),
        Text(
          'Total Service Value This Month: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_monthlyServiceTotal)}',
        ),
        Text(
          'Estimated Platform Revenue This Month: '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_platformRevenueEstimate)}',
        ),
        Text(
          'Total Platform Revenue (All-Time): '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_totalPlatformRevenue)}',
        ),
        Text(
          'Total Platform Fees Collected (All-Time): '
          '${NumberFormat.currency(locale: 'en_US', symbol: '\$').format(_allTimePlatformFees)}',
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

  String _formatMonthYear(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return DateFormat('MMMM yyyy').format(dt);
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
    final double? finalPrice = (data['finalPrice'] as num?)?.toDouble();
    double? platformFee = (data['platformFee'] as num?)?.toDouble();
    bool estimatedFee = false;
    if (platformFee == null && finalPrice != null) {
      platformFee = double.parse((finalPrice * 0.15).toStringAsFixed(2));
      estimatedFee = true;
    }
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
            if (platformFee != null)
            Text(
              'Platform Fee for This Invoice: \$${platformFee.toStringAsFixed(2)}' +
                  (estimatedFee ? ' (est.)' : ''),
            ),
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
        final searchLower = _userSearch.toLowerCase();
        final filteredDocs = docs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final name = (data['username'] ?? '').toString().toLowerCase();
          return name.contains(searchLower) || d.id.toLowerCase().contains(searchLower);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Active Mechanics'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              return ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['username'] ?? d.id} (${data['role'] ?? 'mechanic'})',
                      ),
                    ),
                    if (data['createdAt'] != null)
                      Text(
                        'Created: ${_formatMonthYear(data['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                subtitle: Text(d.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.block),
                      onPressed: () => _deactivateMechanic(d.id),
                      tooltip: 'Deactivate',
                    ),
                    TextButton(
                      onPressed: () => _blockMechanic(d.id),
                      child: const Text('Block Mechanic'),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildBlockedMechanics() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mechanic')
          .where('blocked', isEqualTo: true)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final searchLower = _userSearch.toLowerCase();
        final filteredDocs = docs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final name = (data['username'] ?? '').toString().toLowerCase();
          return name.contains(searchLower) || d.id.toLowerCase().contains(searchLower);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Blocked Mechanics'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              return ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['username'] ?? d.id} (${data['role'] ?? 'mechanic'})',
                      ),
                    ),
                    if (data['createdAt'] != null)
                      Text(
                        'Created: ${_formatMonthYear(data['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                subtitle: Text(d.id),
                trailing: TextButton(
                  onPressed: () => _unblockMechanic(d.id),
                  child: const Text('Unblock Mechanic'),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildFlaggedMechanics() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mechanic')
          .where('flagged', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final searchLower = _userSearch.toLowerCase();
        final filteredDocs = docs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final name = (data['username'] ?? '').toString().toLowerCase();
          return name.contains(searchLower) || d.id.toLowerCase().contains(searchLower);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Flagged Mechanics'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              return ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['username'] ?? d.id} (${data['role'] ?? 'mechanic'})',
                      ),
                    ),
                    if (data['createdAt'] != null)
                      Text(
                        'Created: ${_formatMonthYear(data['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                subtitle: Text(d.id),
                trailing: TextButton(
                  onPressed: () => _unflagMechanic(d.id),
                  child: const Text('Remove Flag'),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildCustomers() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final searchLower = _userSearch.toLowerCase();
        final filteredDocs = docs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final name = (data['username'] ?? '').toString().toLowerCase();
          return name.contains(searchLower) || d.id.toLowerCase().contains(searchLower);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Customers'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              final flagged = data['flagged'] == true;
              return ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['username'] ?? d.id} (${data['role'] ?? 'customer'})',
                      ),
                    ),
                    if (data['createdAt'] != null)
                      Text(
                        'Created: ${_formatMonthYear(data['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                subtitle: Text(d.id),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (flagged)
                      const Icon(
                        Icons.flag,
                        color: Colors.red,
                      ),
                    TextButton(
                      onPressed: flagged ? null : () => _flagCustomer(d.id),
                      child: const Text('Flag Customer'),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Widget _buildFlaggedCustomers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .where('flagged', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final searchLower = _userSearch.toLowerCase();
        final filteredDocs = docs.where((d) {
          if (searchLower.isEmpty) return true;
          final data = d.data();
          final name = (data['username'] ?? '').toString().toLowerCase();
          return name.contains(searchLower) || d.id.toLowerCase().contains(searchLower);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Flagged Customers'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              return ListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${data['username'] ?? d.id} (${data['role'] ?? 'customer'})',
                      ),
                    ),
                    if (data['createdAt'] != null)
                      Text(
                        'Created: ${_formatMonthYear(data['createdAt'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
                subtitle: Text(d.id),
                trailing: TextButton(
                  onPressed: () => _unflagCustomer(d.id),
                  child: const Text('Remove Flag'),
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
    _newMechanicsSub?.cancel();
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Users', style: TextStyle(fontSize: 16)),
                      Row(
                        children: [
                          Text('Total Customers: $_totalCustomers'),
                          const SizedBox(width: 16),
                          Text('Total Mechanics: $_totalMechanics'),
                        ],
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search Users',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _userSearch = value;
                        });
                      },
                    ),
                  ),
                  Row(
                    children: [
                      const Text('Filter Users: '),
                      DropdownButton<String>(
                        value: _userRoleFilter,
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('All Users')),
                          DropdownMenuItem(
                              value: 'customer', child: Text('Customers Only')),
                          DropdownMenuItem(
                              value: 'mechanic', child: Text('Mechanics Only')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _userRoleFilter = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  if (_userRoleFilter == 'all' || _userRoleFilter == 'mechanic')
                    ...[
                      _buildActiveMechanics(),
                      _buildBlockedMechanics(),
                      _buildFlaggedMechanics(),
                    ],
                  if (_userRoleFilter == 'all' || _userRoleFilter == 'customer')
                    ...[
                      _buildCustomers(),
                      _buildFlaggedCustomers(),
                    ],
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

