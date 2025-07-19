import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/csv_downloader.dart';
import 'dashboard_page.dart';

/// Detailed view of a single invoice for admins.
class AdminInvoiceDetailPage extends StatefulWidget {
  final String invoiceId;
  final String userId;

  const AdminInvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.userId,
  });

  @override
  State<AdminInvoiceDetailPage> createState() => _AdminInvoiceDetailPageState();
}

class _AdminInvoiceDetailPageState extends State<AdminInvoiceDetailPage> {
  late Future<Map<String, dynamic>?> _invoiceFuture;
  late Future<List<Map<String, String>>> _mechanicsFuture;
  String? _selectedMechanicId;

  @override
  void initState() {
    super.initState();
    _invoiceFuture = _loadInvoice();
    _mechanicsFuture = _loadMechanics();
  }

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  Future<Map<String, dynamic>?> _loadInvoice() async {
    final doc = await FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .get();
    final data = doc.data();
    if (data == null) return null;

    final custDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(data['customerId'])
        .get();
    data['customerUsername'] = custDoc.data()?['username'] ?? 'Unknown';

    if (data['mechanicId'] != null && data['mechanicId'] != 'any') {
      final mechDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['mechanicId'])
          .get();
      data['mechanicUsername'] = mechDoc.data()?['username'] ?? 'Unknown';
    }

    return data;
  }

  Future<List<Map<String, String>>> _loadMechanics() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'mechanic')
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs
        .map((d) => {
              'id': d.id,
              'username': d.data()['username'] ?? d.id,
            })
        .toList();
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'overdue':
        return Colors.red;
      case 'pending':
        return Colors.yellow;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _csvEscape(String? input) {
    if (input == null) return '';
    var s = input.replaceAll('"', '""');
    if (s.contains(',') || s.contains('\n') || s.contains('"')) {
      s = '"$s"';
    }
    return s;
  }

  Future<void> _exportInvoice(Map<String, dynamic> data) async {
    final buffer = StringBuffer();
    buffer.writeln(
        'Invoice Number,Customer Username,Mechanic Username,Final Price,Platform Fee,Payment Status,Created Date,Closed Date');
    final invoiceNum = (data['invoiceNumber'] ?? widget.invoiceId).toString();
    final customer = (data['customerUsername'] ?? '').toString();
    final mechanic = (data['mechanicUsername'] ?? '').toString();
    final finalPrice = (data['finalPrice'] as num?)?.toString() ?? '';
    final fee = (data['platformFee'] as num?)?.toString() ?? '';
    final paymentStatus = (data['paymentStatus'] ?? '').toString();
    final created = _formatDate(data['createdAt'] as Timestamp?);
    final closed = _formatDate(data['closedAt'] as Timestamp?);
    final row = [
      invoiceNum,
      customer,
      mechanic,
      finalPrice,
      fee,
      paymentStatus,
      created,
      closed,
    ].map(_csvEscape).join(',');
    buffer.writeln(row);
    await downloadCsv(buffer.toString(), fileName: 'invoice_$invoiceNum.csv');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice CSV exported')),
      );
    }
  }

  void _showJson(Map<String, dynamic> data) {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Raw Invoice Data'),
        content: SingleChildScrollView(child: Text(jsonStr)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          )
        ],
      ),
    );
  }

  Future<void> _reassignRequest(
      Map<String, dynamic> invoiceData, String mechanicId) async {
    final invoiceRef = FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId);

    final mechDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(mechanicId)
        .get();
    final newUsername = mechDoc.data()?['username'] ?? 'Mechanic';

    await invoiceRef.update({
      'mechanicId': mechanicId,
      'mechanicUsername': newUsername,
      'mechanicAccepted': false,
      'status': 'active',
      'reassignmentHistory': FieldValue.arrayUnion([
        {
          'mechanicId': mechanicId,
          'timestamp': FieldValue.serverTimestamp(),
        }
      ])
    });

    final oldMech = invoiceData['mechanicId'];
    final customerId = invoiceData['customerId'];

    await FirebaseFirestore.instance.collection('admin_logs').add({
      'action': 'reassignRequest',
      'invoiceId': widget.invoiceId,
      'oldMechanicId': oldMech,
      'newMechanicId': mechanicId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(mechanicId)
        .collection('messages')
        .add({
      'title': 'New Service Request Assigned',
      'body': 'A service request has been assigned to you.',
      'timestamp': FieldValue.serverTimestamp(),
    });

    if (customerId != null) {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(customerId)
          .collection('messages')
          .add({
        'title': 'Mechanic Reassigned',
        'body': 'Your request has been reassigned to $newUsername.',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request reassigned.')),
      );
      setState(() {
        _invoiceFuture = _loadInvoice();
        _selectedMechanicId = null;
      });
    }
  }

  Widget _buildDetails(Map<String, dynamic> data) {
    final car = data['carInfo'] ?? {};
    final carText =
        '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
    final loc = data['location'];
    final status = (data['paymentStatus'] ?? 'pending') as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Invoice #: ${data['invoiceNumber'] ?? widget.invoiceId}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('Created: ${_formatDate(data['createdAt'] as Timestamp?)}'),
        if (data['closedAt'] != null)
          Text('Closed: ${_formatDate(data['closedAt'] as Timestamp?)}'),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Payment Status: '),
            Chip(
              label: Text(
                status,
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: _statusColor(status),
            ),
          ],
        ),
        if (data['platformFee'] != null)
          Text(
              'Platform Fee: \$${(data['platformFee'] as num).toStringAsFixed(2)}'),
        if (data['finalPrice'] != null)
          Text(
              'Total Amount: \$${(data['finalPrice'] as num).toStringAsFixed(2)}'),
        Text('Customer: ${data['customerUsername'] ?? 'Unknown'}'),
        Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
        FutureBuilder<List<Map<String, String>>>(
          future: _mechanicsFuture,
          builder: (context, mechSnap) {
            if (!mechSnap.hasData) return const SizedBox.shrink();
            final mechanics = mechSnap.data!;
            final isComplete =
                data['status'] == 'completed' || data['status'] == 'closed';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedMechanicId ?? data['mechanicId'],
                  decoration:
                      const InputDecoration(labelText: 'Select Mechanic'),
                  items: mechanics
                      .map(
                        (m) => DropdownMenuItem(
                          value: m['id'],
                          child: Text(m['username'] ?? m['id']),
                        ),
                      )
                      .toList(),
                  onChanged: isComplete
                      ? null
                      : (val) {
                          setState(() {
                            _selectedMechanicId = val;
                          });
                        },
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: isComplete || _selectedMechanicId == null
                      ? null
                      : () => _reassignRequest(
                          data, _selectedMechanicId!),
                  child: const Text('Reassign Request'),
                ),
              ],
            );
          },
        ),
        if (carText.isNotEmpty) Text('Car: $carText'),
        if ((data['description'] ?? '').toString().isNotEmpty)
          Text('Service: ${data['description']}'),
        if (loc != null)
          Text('Location: ${loc['lat']}, ${loc['lng']}'),
        if ((data['notes'] ?? '').toString().isNotEmpty)
          Text('Customer Notes:\n${data['notes']}'),
        if ((data['postJobNotes'] ?? '').toString().isNotEmpty)
          Text('Mechanic Notes:\n${data['postJobNotes']}'),
        if ((data['customerReview'] ?? '').toString().isNotEmpty)
          Text('Customer Review:\n${data['customerReview']}'),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ElevatedButton(
              onPressed: () => _showJson(data),
              child: const Text('View Raw JSON'),
            ),
            ElevatedButton(
              onPressed: () => _exportInvoice(data),
              child: const Text('Export This Invoice'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, roleSnap) {
        if (!roleSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (roleSnap.data != 'admin') {
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
          appBar: AppBar(title: const Text('Invoice Details')),
          body: FutureBuilder<Map<String, dynamic>?>(
            future: _invoiceFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Center(child: Text('Invoice not found'));
              }
              return _buildDetails(snapshot.data!);
            },
          ),
        );
      },
    );
  }
}
