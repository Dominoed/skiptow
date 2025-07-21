import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/csv_downloader.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'admin_user_detail_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'admin_financial_report_page.dart';
import 'admin_invoice_detail_page.dart';
import 'admin_mechanic_performance_page.dart';
import 'admin_customer_history_page.dart';
import 'admin_broadcast_message_page.dart';
import 'admin_report_detail_page.dart';
import 'admin_message_center_page.dart';

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
  int _blockedCustomers = 0;
  int _flaggedMechanics = 0;
  int _flaggedCustomers = 0;
  int _flaggedUsers = 0;
  int _blockedUsers = 0;
  int _suspiciousMechanics = 0;
  int _suspiciousCustomers = 0;
  int _suspiciousUsers = 0;
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

  // Current search queries for invoices
  String _invoiceNumberSearch = '';
  String _customerUsernameSearch = '';
  String _mechanicUsernameSearch = '';
  String _invoiceIdOrCustomerSearch = '';

  final TextEditingController _invoiceNumberController = TextEditingController();
  final TextEditingController _customerUsernameController =
      TextEditingController();
  final TextEditingController _mechanicUsernameController =
      TextEditingController();
  final TextEditingController _invoiceIdOrCustomerController =
      TextEditingController();

  // Current search query for users
  String _userSearch = '';

  // Current role filter for users
  String _userRoleFilter = 'all';

  // Current account status filter for users
  String _accountStatusFilter = 'all';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invoiceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedJobsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _usersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newMechanicsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _flaggedCustomersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _flaggedMechanicsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _suspiciousCustomersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _suspiciousMechanicsSub;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _invoiceStream;
  String _invoiceStatusFilter = 'all';
  String _invoiceStateFilter = 'all';
  String _reportStatusFilter = 'open';

  String _appVersion = '1.0.0';

  // Date range filter for invoices
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

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

    _flaggedCustomersSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'customer')
        .where('flagged', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _flaggedCustomers = snapshot.size;
          _flaggedUsers = _flaggedCustomers + _flaggedMechanics;
        });
      } else {
        _flaggedCustomers = snapshot.size;
        _flaggedUsers = _flaggedCustomers + _flaggedMechanics;
      }
    });

    _flaggedMechanicsSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'mechanic')
        .where('flagged', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _flaggedMechanics = snapshot.size;
          _flaggedUsers = _flaggedCustomers + _flaggedMechanics;
        });
      } else {
        _flaggedMechanics = snapshot.size;
        _flaggedUsers = _flaggedCustomers + _flaggedMechanics;
      }
    });

    _suspiciousCustomersSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'customer')
        .where('suspicious', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _suspiciousCustomers = snapshot.size;
          _suspiciousUsers = _suspiciousCustomers + _suspiciousMechanics;
        });
      } else {
        _suspiciousCustomers = snapshot.size;
        _suspiciousUsers = _suspiciousCustomers + _suspiciousMechanics;
      }
    });

    _suspiciousMechanicsSub = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'mechanic')
        .where('suspicious', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _suspiciousMechanics = snapshot.size;
          _suspiciousUsers = _suspiciousCustomers + _suspiciousMechanics;
        });
      } else {
        _suspiciousMechanics = snapshot.size;
        _suspiciousUsers = _suspiciousCustomers + _suspiciousMechanics;
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
    _blockedCustomers = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'customer' && d.data()['blocked'] == true)
        .length;
    _blockedUsers = _blockedMechanics + _blockedCustomers;
    _flaggedMechanics = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'mechanic' && d.data()['flagged'] == true)
        .length;
    _flaggedCustomers = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'customer' && d.data()['flagged'] == true)
        .length;
    _flaggedUsers = _flaggedMechanics + _flaggedCustomers;
    _suspiciousMechanics = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'mechanic' && d.data()['suspicious'] == true)
        .length;
    _suspiciousCustomers = usersSnapshot.docs
        .where((d) =>
            d.data()['role'] == 'customer' && d.data()['suspicious'] == true)
        .length;
    _suspiciousUsers = _suspiciousMechanics + _suspiciousCustomers;

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
    _platformRevenueEstimate = monthlyServiceTotal * 0.10;
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
    _totalPlatformRevenue = total * 0.10;
    _monthlyCollected = monthlyTotal;
    _monthlyPayoutEstimate = monthlyTotal * 0.90;
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
      _totalPlatformRevenue = total * 0.10;
      _monthlyCollected = monthlyTotal;
      _monthlyServiceTotal = monthlyServiceTotal;
      _platformRevenueEstimate = monthlyServiceTotal * 0.10;
      _monthlyPayoutEstimate = monthlyPayout * 0.90;
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
      _totalPlatformRevenue = total * 0.10;
      _monthlyCollected = monthlyTotal;
      _monthlyServiceTotal = monthlyServiceTotal;
      _platformRevenueEstimate = monthlyServiceTotal * 0.10;
      _monthlyPayoutEstimate = monthlyPayout * 0.90;
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
    int suspiciousCount = 0;
    int suspiciousCustomerCount = 0;
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
        if (data['suspicious'] == true) suspiciousCount++;
      } else if (role == 'customer') {
        customerCount++;
        count++;
        if (data['blocked'] == true) blockedCustomerCount++;
        if (data['flagged'] == true) flaggedCustomerCount++;
        if (data['suspicious'] == true) suspiciousCustomerCount++;
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
    final totalFlagged = flaggedCount + flaggedCustomerCount;
    final totalSuspicious = suspiciousCount + suspiciousCustomerCount;
    if (!mounted) {
      _totalActiveUsers = count;
      _activeMechanics = mechCount;
      _usernames = nameMap;
      _newCustomers = newCount;
      _blockedMechanics = blockedCount;
      _blockedCustomers = blockedCustomerCount;
      _blockedUsers = totalBlocked;
      _flaggedMechanics = flaggedCount;
      _flaggedCustomers = flaggedCustomerCount;
      _flaggedUsers = totalFlagged;
      _suspiciousMechanics = suspiciousCount;
      _suspiciousCustomers = suspiciousCustomerCount;
      _suspiciousUsers = totalSuspicious;
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
      _blockedCustomers = blockedCustomerCount;
      _blockedUsers = totalBlocked;
      _flaggedMechanics = flaggedCount;
      _flaggedCustomers = flaggedCustomerCount;
      _flaggedUsers = totalFlagged;
      _suspiciousMechanics = suspiciousCount;
      _suspiciousCustomers = suspiciousCustomerCount;
      _suspiciousUsers = totalSuspicious;
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

  Future<void> _unblockCustomer(String customerId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(customerId)
        .update({'blocked': false});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer unblocked')),
      );
    }
  }

  Future<void> _markSuspicious(String userId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({'suspicious': true});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User marked suspicious')),
      );
    }
  }

  Future<void> _removeSuspicious(String userId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .update({'suspicious': false});
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suspicious tag removed')),
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
    await const FlutterSecureStorage().delete(key: 'session_token');
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Widget _buildMessageCenterIcon() {
    final stream = FirebaseFirestore.instance
        .collection('notifications_admin')
        .where('unread', isEqualTo: true)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.support_agent),
              tooltip: 'Message Center',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminMessageCenterPage(adminId: widget.userId),
                  ),
                );
              },
            ),
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: CircleAvatar(
                  radius: 8,
                  backgroundColor: Colors.red,
                  child: Text(
                    '$count',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryPanel() {
    final currency = NumberFormat.currency(locale: 'en_US', symbol: '\$');
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryCard('Total Customers', '$_totalCustomers', Colors.blue),
        _summaryCard('Total Mechanics', '$_totalMechanics', Colors.blue),
        _summaryCard('Blocked Accounts', '$_blockedUsers', Colors.red),
        _summaryCard('Flagged Accounts', '$_flaggedUsers', Colors.orange),
        _summaryCard('Suspicious Accounts', '$_suspiciousUsers', Colors.red),
        _summaryCard('Active Mechanics', '$_activeMechanics', Colors.green),
        _summaryCard('Overdue Invoices', '$_overdueInvoices', Colors.red),
        _summaryCard('Outstanding Balance',
            currency.format(_unpaidOutstanding), Colors.deepPurple),
        _summaryCard('Paid Invoices', '$_paidInvoices', Colors.green),
        _summaryCard('Platform Revenue',
            currency.format(_totalPlatformRevenue), Colors.teal),
      ],
    );
  }

  Widget _buildStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Total Users: $_totalUsers'),
        Text('Active Mechanics Right Now: $_activeMechanics'),
        Text('Blocked Mechanics: $_blockedMechanics'),
        Text('Blocked Customers: $_blockedCustomers'),
        Text('Blocked Accounts: $_blockedUsers'),
        Text('Flagged Accounts: $_flaggedUsers'),
        Text('Suspicious Accounts: $_suspiciousUsers'),
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

  String _formatPrettyDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return DateFormat('MMMM d, yyyy').format(dt);
  }

  Color _paymentStatusColor(String status) {
    switch (status) {
      case 'Paid':
      case 'paid':
      case 'paid_in_person':
        return Colors.green;
      case 'Overdue':
      case 'overdue':
        return Colors.red;
      case 'Pending':
      case 'pending':
        return Colors.yellow;
      case 'Unpaid':
      case 'unpaid':
        return Colors.orange;
      case 'Closed':
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  bool _matchesUserSearch(Map<String, dynamic> data, String id) {
    final searchLower = _userSearch.toLowerCase();
    if (searchLower.isEmpty) return true;
    final username = (data['username'] ?? '').toString().toLowerCase();
    final email = (data['email'] ?? '').toString().toLowerCase();
    return username.contains(searchLower) ||
        id.toLowerCase().contains(searchLower) ||
        email.contains(searchLower);
  }

  Widget _buildStatusBadges(Map<String, dynamic> data) {
    final blocked = data['blocked'] == true;
    final flagged = data['flagged'] == true;
    final suspicious = data['suspicious'] == true;
    final unavailable = data['unavailable'] == true;
    final List<Widget> badges = [];
    if (blocked) {
      badges.add(
        const Chip(
          label: Text(
            'Blocked',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (flagged) {
      badges.add(
        const Chip(
          label: Text(
            'Flagged',
            style: TextStyle(color: Colors.black, fontSize: 12),
          ),
          backgroundColor: Colors.yellow,
        ),
      );
    }
    if (suspicious) {
      badges.add(
        const Chip(
          label: Text(
            'Suspicious',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    if (unavailable) {
      badges.add(
        const Chip(
          label: Text(
            'Unavailable',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    if (badges.isEmpty) {
      badges.add(
        const Chip(
          label: Text(
            'Active',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: badges
          .map((w) => Padding(padding: const EdgeInsets.only(right: 4), child: w))
          .toList(),
    );
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

  void _resetInvoiceFilters() {
    setState(() {
      _invoiceStatusFilter = 'all';
      _invoiceStateFilter = 'all';
      _invoiceNumberSearch = '';
      _customerUsernameSearch = '';
      _mechanicUsernameSearch = '';
      _invoiceIdOrCustomerSearch = '';
      _invoiceNumberController.clear();
      _customerUsernameController.clear();
      _mechanicUsernameController.clear();
      _invoiceIdOrCustomerController.clear();
      _startDate = null;
      _endDate = null;
      _startDateController.clear();
      _endDateController.clear();
    });
  }

  Widget _invoiceTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final flagged = data['flagged'] == true;
    final paymentStatus = (data['paymentStatus'] ?? 'pending') as String;
    final status = (data['status'] ?? '') as String;
    final Timestamp? createdAtTs = data['createdAt'];
    final Timestamp? acceptedAtTs =
        data['mechanicAcceptedAt'] ?? data['acceptedAt'];
    final double? finalPrice = (data['finalPrice'] as num?)?.toDouble();
    final mechName = (data['mechanicUsername'] ?? _usernames[data['mechanicId']] ?? data['mechanicId']).toString();
    final custName = (data['customerUsername'] ?? _usernames[data['customerId']] ?? data['customerId']).toString();
    final bool overdue = paymentStatus == 'pending' &&
        createdAtTs != null &&
        DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
    final label = status == 'closed'
        ? 'Closed'
        : (overdue
            ? 'Overdue'
            : (paymentStatus == 'paid' || paymentStatus == 'paid_in_person'
                ? 'Paid'
                : (paymentStatus == 'unpaid' ? 'Unpaid' : 'Pending')));
    return Container(
      color: overdue ? Colors.red.shade50 : null,
      child: ListTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Invoice #: ${data['invoiceNumber'] ?? doc.id}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Chip(
              label: Text(
                label,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: _paymentStatusColor(label),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text('Customer: $custName')),
                Expanded(child: Text('Mechanic: $mechName')),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (createdAtTs != null)
                  Text(
                    'Created: ${_formatPrettyDate(createdAtTs)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (acceptedAtTs != null)
                  Text(
                    'Accepted: ${_formatPrettyDate(acceptedAtTs)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (data['closedAt'] != null)
                  Text(
                    'Closed: ${_formatPrettyDate(data['closedAt'] as Timestamp?)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (finalPrice != null)
                  Text('Total: \$' + finalPrice.toStringAsFixed(2)),
              ],
            ),
            Text('Status: $status'),
            Text('Payment: $paymentStatus'),
            if ((data['customerReview'] ?? '').toString().isNotEmpty)
              Text('Customer Review: ${data['customerReview']}')
            else
              const Text('No review.'),
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('invoices')
                  .doc(doc.id)
                  .collection('mechanicFeedback')
                  .get(),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                final fb = snap.data!.docs.first.data();
                final rating = fb['rating'];
                final text = fb['feedbackText'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mechanic Rating: ${rating ?? ''}/5'),
                    if (text != null && text.toString().isNotEmpty)
                      Text('Mechanic Feedback: $text'),
                  ],
                );
              },
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminInvoiceDetailPage(
                      invoiceId: doc.id,
                      userId: widget.userId,
                    ),
                  ),
                );
              },
              tooltip: 'View Details',
            ),
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
          final status = (data['invoiceStatus'] ?? data['status'] ?? '') as String;
          final Timestamp? createdAtTs = data['createdAt'];
          final bool isOverdue = payment == 'pending' &&
              createdAtTs != null &&
              DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
          bool matchesStatus;
          switch (_invoiceStatusFilter) {
            case 'paid':
              matchesStatus = payment == 'paid';
              break;
            case 'pending':
              matchesStatus = payment == 'pending' && !isOverdue;
              break;
            case 'overdue':
              matchesStatus = isOverdue;
              break;
            case 'closed':
              matchesStatus = status == 'closed';
              break;
            default:
              matchesStatus = true;
          }
          if (!matchesStatus) return false;
          bool matchesState;
          switch (_invoiceStateFilter) {
            case 'pending':
              matchesState = status == 'active';
              break;
            case 'accepted':
              matchesState = status == 'accepted';
              break;
            case 'completed':
              matchesState = status == 'completed';
              break;
            case 'closed':
              matchesState = status == 'closed';
              break;
            case 'cancelled':
              matchesState = status == 'cancelled';
              break;
            default:
              matchesState = true;
          }
          if (!matchesState) return false;
          if (_startDate != null && _endDate != null) {
            if (createdAtTs == null) return false;
            final dt = DateTime(createdAtTs.toDate().year,
                createdAtTs.toDate().month, createdAtTs.toDate().day);
            if (dt.isBefore(_startDate!) || dt.isAfter(_endDate!)) {
              return false;
            }
          }
          return true;
        }).toList();
        final invoiceLower = _invoiceNumberSearch.toLowerCase();
        final mechLower = _mechanicUsernameSearch.toLowerCase();
        final custLower = _customerUsernameSearch.toLowerCase();
        final searchDocs = filteredDocs.where((d) {
          final data = d.data();
          final invoiceNum = (data['invoiceNumber'] ?? '').toString().toLowerCase();
          final mechName = (data['mechanicUsername'] ??
                  _usernames[data['mechanicId']] ?? '')
              .toString()
              .toLowerCase();
          final custName = (_usernames[data['customerId']] ?? '')
              .toLowerCase();
          if (invoiceLower.isNotEmpty && !invoiceNum.contains(invoiceLower)) {
            return false;
          }
          if (mechLower.isNotEmpty && !mechName.contains(mechLower)) {
            return false;
          }
          if (custLower.isNotEmpty && !custName.contains(custLower)) {
            return false;
          }
          return true;
        }).toList();
        final idCustLower = _invoiceIdOrCustomerSearch.toLowerCase();
        final resultDocs = searchDocs.where((d) {
          if (idCustLower.isEmpty) return true;
          final data = d.data();
          final custName = (_usernames[data['customerId']] ?? '').toLowerCase();
          final idMatch = d.id.toLowerCase() == idCustLower;
          return idMatch || custName.contains(idCustLower);
        }).toList();
        if (resultDocs.isEmpty) {
          return const Text('No invoices');
        }
        final total = resultDocs.fold<double>(
          0.0,
          (sum, d) => sum + ((d.data()['finalPrice'] as num?)?.toDouble() ?? 0.0),
        );
        final count = resultDocs.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Results: $count invoices',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Total Amount: \$${total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: resultDocs.map((e) => _invoiceTile(e)).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _userTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final created = data['createdAt'] as Timestamp?;
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminUserDetailPage(userId: doc.id),
          ),
        );
      },
      title: Text(data['username'] ?? doc.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Role: ${data['role'] ?? 'customer'}'),
          Text('ID: ${doc.id}'),
          if (data['email'] != null) Text('Email: ${data['email']}'),
          if (created != null) Text('Created: ${_formatPrettyDate(created)}'),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data['role'] == 'mechanic')
            IconButton(
              icon: const Icon(Icons.bar_chart),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminMechanicPerformancePage(
                      mechanicId: doc.id,
                      userId: widget.userId,
                    ),
                  ),
                );
              },
              tooltip: 'View Performance',
            ),
          if (data['role'] == 'customer')
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminCustomerHistoryPage(
                      customerId: doc.id,
                      userId: widget.userId,
                    ),
                  ),
                );
              },
              child: const Text('View History'),
            ),
          TextButton(
            onPressed: () => data['suspicious'] == true
                ? _removeSuspicious(doc.id)
                : _markSuspicious(doc.id),
            child: Text(data['suspicious'] == true
                ? 'Remove Suspicious Tag'
                : 'Mark as Suspicious'),
          ),
          _buildStatusBadges(data),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('users');
    if (_userRoleFilter != 'all') {
      query = query.where('role', isEqualTo: _userRoleFilter);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            snapshot.data?.docs ?? [];

        docs = docs.where((d) => _matchesUserSearch(d.data(), d.id)).toList();

        if (_accountStatusFilter == 'blocked') {
          docs = docs.where((d) => d.data()['blocked'] == true).toList();
        } else if (_accountStatusFilter == 'flagged') {
          docs = docs
              .where((d) => d.data()['flagged'] == true && d.data()['blocked'] != true)
              .toList();
        } else if (_accountStatusFilter == 'suspicious') {
          docs = docs
              .where((d) => d.data()['suspicious'] == true && d.data()['blocked'] != true)
              .toList();
        } else if (_accountStatusFilter == 'normal') {
          docs = docs
              .where((d) => d.data()['flagged'] != true && d.data()['blocked'] != true)
              .toList();
        }

        int rank(Map<String, dynamic> data) {
          if (data['blocked'] == true) return 0;
          if (data['suspicious'] == true) return 1;
          if (data['flagged'] == true) return 2;
          return 3;
        }

        docs.sort((a, b) => rank(a.data()).compareTo(rank(b.data())));

        if (docs.isEmpty) return const Text('No users');

        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: docs.map(_userTile).toList(),
        );
      },
    );
  }

  String _csvEscape(String? input) {
    if (input == null) return '';
    var s = input.replaceAll('"', '""');
    if (s.contains(',') || s.contains('\n') || s.contains('"')) {
      s = '"$s"';
    }
    return s;
  }

  Future<void> _exportUsers() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final buffer = StringBuffer();
    buffer.writeln(
        'Username,Email,Role,User ID,Created Date,Blocked,Flagged,Suspicious');
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final username =
          (data['username'] ?? data['displayName'] ?? '').toString();
      final email = (data['email'] ?? '').toString();
      final role = (data['role'] ?? '').toString();
      final created = _formatDate(data['createdAt'] as Timestamp?);
      final blocked = data['blocked'] == true ? 'yes' : 'no';
      final flagged = data['flagged'] == true ? 'yes' : 'no';
      final suspicious = data['suspicious'] == true ? 'yes' : 'no';
      final row = [
        username,
        email,
        role,
        doc.id,
        created,
        blocked,
        flagged,
        suspicious,
      ].map(_csvEscape).join(',');
      buffer.writeln(row);
    }
    await downloadCsv(buffer.toString(), fileName: 'users.csv');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User CSV exported')),
      );
    }
  }

  Widget _reportTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final ts = data['timestamp'] as Timestamp?;
    final preview = (data['reportText'] ?? '').toString();
    final shortText = preview.length > 40 ? '${preview.substring(0, 40)}...' : preview;
    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminReportDetailPage(
              reportId: doc.id,
              userId: widget.userId,
            ),
          ),
        );
      },
      title: Text('Report ID: ${doc.id}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invoice: ${data['relatedInvoiceId'] ?? data['invoiceId'] ?? ''}'),
          if (data['reportedBy'] != null)
            Text('Reported By: ${data['reportedBy']}'),
          if (preview.isNotEmpty) Text(shortText),
          Text('Customer: ${data['customerId'] ?? ''}'),
          Text('Mechanic: ${data['mechanicId'] ?? ''}'),
          if (ts != null) Text('Time: ${_formatPrettyDate(ts)}'),
          Text('Status: ${data['status'] ?? 'open'}'),
          if (data['imageUrl'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Image.network(
                data['imageUrl'],
                height: 80,
                errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
              ),
            ),
        ],
      ),
      trailing: data['status'] == 'open'
          ? TextButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('reports')
                    .doc(doc.id)
                    .update({'status': 'closed'});
              },
              child: const Text('Mark Closed'),
            )
          : null,
    );
  }

  Widget _buildReports() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('reports')
        .orderBy('timestamp', descending: true);
    if (_reportStatusFilter != 'all') {
      query = query.where('status', isEqualTo: _reportStatusFilter);
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Text('No reports');
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: docs.map(_reportTile).toList(),
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
          .where('blocked', isEqualTo: false)
          .where('flagged', isEqualTo: false)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
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
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.bar_chart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminMechanicPerformancePage(
                              mechanicId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      tooltip: 'View Performance',
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    IconButton(
                      icon: const Icon(Icons.block),
                      onPressed: () => _deactivateMechanic(d.id),
                      tooltip: 'Deactivate',
                    ),
                    TextButton(
                      onPressed: () => _blockMechanic(d.id),
                      child: const Text('Block Mechanic'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
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
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.bar_chart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminMechanicPerformancePage(
                              mechanicId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      tooltip: 'View Performance',
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    TextButton(
                      onPressed: () => _unblockMechanic(d.id),
                      child: const Text('Unblock Mechanic'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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

  Widget _buildFlaggedMechanics() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'mechanic')
          .where('flagged', isEqualTo: true)
          .where('blocked', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
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
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.bar_chart),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminMechanicPerformancePage(
                              mechanicId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      tooltip: 'View Performance',
                    ),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    TextButton(
                      onPressed: () => _unflagMechanic(d.id),
                      child: const Text('Remove Flag'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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

  Widget _buildBlockedCustomers() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .where('blocked', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
        }).toList();
        if (filteredDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 16, bottom: 8),
              child: Text('Blocked Customers'),
            ),
            ...filteredDocs.map((d) {
              final data = d.data();
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminCustomerHistoryPage(
                              customerId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      child: const Text('View History'),
                    ),
                    TextButton(
                      onPressed: () => _unblockCustomer(d.id),
                      child: const Text('Unblock Customer'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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

  Widget _buildCustomers() {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .where('blocked', isEqualTo: false)
          .where('flagged', isEqualTo: false)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
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
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminCustomerHistoryPage(
                              customerId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      child: const Text('View History'),
                    ),
                    TextButton(
                      onPressed: flagged ? null : () => _flagCustomer(d.id),
                      child: const Text('Flag Customer'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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
          .where('blocked', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final filteredDocs = docs.where((d) {
          return _matchesUserSearch(d.data(), d.id);
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
              final suspicious = data['suspicious'] == true;
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
                    _buildStatusBadges(data),
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminUserDetailPage(userId: d.id),
                          ),
                        );
                      },
                      tooltip: 'View Details',
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminCustomerHistoryPage(
                              customerId: d.id,
                              userId: widget.userId,
                            ),
                          ),
                        );
                      },
                      child: const Text('View History'),
                    ),
                    TextButton(
                      onPressed: () => _unflagCustomer(d.id),
                      child: const Text('Remove Flag'),
                    ),
                    TextButton(
                      onPressed: () => suspicious
                          ? _removeSuspicious(d.id)
                          : _markSuspicious(d.id),
                      child: Text(suspicious
                          ? 'Remove Suspicious Tag'
                          : 'Mark as Suspicious'),
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

  @override
  void dispose() {
    _invoiceSub?.cancel();
    _completedJobsSub?.cancel();
    _usersSub?.cancel();
    _newMechanicsSub?.cancel();
    _flaggedCustomersSub?.cancel();
    _flaggedMechanicsSub?.cancel();
    _suspiciousCustomersSub?.cancel();
    _suspiciousMechanicsSub?.cancel();
    _invoiceNumberController.dispose();
    _customerUsernameController.dispose();
    _mechanicUsernameController.dispose();
    _invoiceIdOrCustomerController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
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
              _buildMessageCenterIcon(),
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
                  _buildSummaryPanel(),
                  const SizedBox(height: 16),
                  _buildStats(),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdminFinancialReportPage(userId: widget.userId),
                        ),
                      );
                    },
                    child: const Text('Financial Reports'),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdminBroadcastMessagePage(userId: widget.userId),
                        ),
                      );
                    },
                    child: const Text('Broadcast Message'),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('Invoices', style: TextStyle(fontSize: 16)),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: TextField(
                      controller: _invoiceIdOrCustomerController,
                      decoration: const InputDecoration(
                        labelText: 'Search by ID or Customer',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _invoiceIdOrCustomerSearch = value;
                        });
                      },
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Advanced Filters'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _invoiceNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Invoice Number',
                                prefixIcon: Icon(Icons.receipt),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _invoiceNumberSearch = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _customerUsernameController,
                              decoration: const InputDecoration(
                                labelText: 'Customer Username',
                                prefixIcon: Icon(Icons.person),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _customerUsernameSearch = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _mechanicUsernameController,
                              decoration: const InputDecoration(
                                labelText: 'Mechanic Username',
                                prefixIcon: Icon(Icons.person),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _mechanicUsernameSearch = value;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Status: '),
                                DropdownButton<String>(
                                  value: _invoiceStatusFilter,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All')),
                                    DropdownMenuItem(value: 'paid', child: Text('Paid')),
                                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                                    DropdownMenuItem(value: 'overdue', child: Text('Overdue')),
                                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _invoiceStatusFilter = value;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Show Invoices By Status: '),
                                DropdownButton<String>(
                                  value: _invoiceStateFilter,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All')),
                                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                                    DropdownMenuItem(value: 'accepted', child: Text('Accepted')),
                                    DropdownMenuItem(value: 'completed', child: Text('Completed')),
                                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                                  ],
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() {
                                        _invoiceStateFilter = value;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _startDateController,
                                    readOnly: true,
                                    decoration:
                                        const InputDecoration(labelText: 'Start Date'),
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _startDate ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate:
                                            DateTime.now().add(const Duration(days: 365)),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          _startDate = DateTime(
                                              picked.year, picked.month, picked.day);
                                          _startDateController.text =
                                              DateFormat('yyyy-MM-dd').format(_startDate!);
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _endDateController,
                                    readOnly: true,
                                    decoration:
                                        const InputDecoration(labelText: 'End Date'),
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: _endDate ?? DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate:
                                            DateTime.now().add(const Duration(days: 365)),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          _endDate =
                                              DateTime(picked.year, picked.month, picked.day);
                                          _endDateController.text =
                                              DateFormat('yyyy-MM-dd').format(_endDate!);
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton(
                                onPressed: _resetInvoiceFilters,
                                child: const Text('Reset Filters'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  _buildInvoices(),
                  const SizedBox(height: 16),
                  const Text('Reports', style: TextStyle(fontSize: 16)),
                  Row(
                    children: [
                      const Text('Status: '),
                      DropdownButton<String>(
                        value: _reportStatusFilter,
                        items: const [
                          DropdownMenuItem(value: 'open', child: Text('Open')),
                          DropdownMenuItem(value: 'closed', child: Text('Closed')),
                          DropdownMenuItem(value: 'all', child: Text('All')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _reportStatusFilter = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  _buildReports(),
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
                      const Text('Filter by Role: '),
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
                  Row(
                    children: [
                      const Text('Account Status: '),
                      DropdownButton<String>(
                        value: _accountStatusFilter,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                          DropdownMenuItem(value: 'flagged', child: Text('Flagged')),
                          DropdownMenuItem(value: 'suspicious', child: Text('Suspicious')),
                          DropdownMenuItem(value: 'normal', child: Text('Normal')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _accountStatusFilter = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: _exportUsers,
                      child: const Text('Export Users as CSV'),
                    ),
                  ),
                  _buildUsersList(),
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

