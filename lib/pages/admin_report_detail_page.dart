import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_invoice_detail_page.dart';
import 'admin_user_detail_page.dart';
import "../utils.dart";
import 'dashboard_page.dart';

/// Detailed view of a specific report for admins.
class AdminReportDetailPage extends StatefulWidget {
  final String reportId;
  final String userId;

  const AdminReportDetailPage({
    super.key,
    required this.reportId,
    required this.userId,
  });

  @override
  State<AdminReportDetailPage> createState() => _AdminReportDetailPageState();
}

class _AdminReportDetailPageState extends State<AdminReportDetailPage> {
  late Future<Map<String, dynamic>?> _reportFuture;
  final TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reportFuture = _loadReport();
  }

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  Future<Map<String, dynamic>?> _loadReport() async {
    final doc = await FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId)
        .get();
    final data = doc.data();
    if (data == null) return null;

    final invId = data['relatedInvoiceId'] ?? data['invoiceId'];
    if (invId != null) {
      final invDoc = await FirebaseFirestore.instance
          .collection('invoices')
          .doc(invId)
          .get();
      if (invDoc.exists) {
        data['invoiceNumber'] = invDoc.data()?['invoiceNumber'];
      }
    }
    if (data['customerId'] != null) {
      final cust = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['customerId'])
          .get();
      data['customerUsername'] = cust.data()?['username'] ?? data['customerId'];
    }
    if (data['mechanicId'] != null) {
      final mech = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['mechanicId'])
          .get();
      data['mechanicUsername'] = mech.data()?['username'] ?? data['mechanicId'];
    }
    _notesController.text = data['adminNotes'] ?? '';
    return data;
  }

  }

  Future<void> _saveNotes() async {
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId)
        .update({'adminNotes': _notesController.text.trim()});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notes saved')),
      );
    }
  }

  Future<void> _closeReport() async {
    await FirebaseFirestore.instance
        .collection('reports')
        .doc(widget.reportId)
        .update({'status': 'closed'});
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report marked closed')),
      );
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Widget _buildDetails(Map<String, dynamic> data) {
    final ts = data['timestamp'] as Timestamp?;
    final status = (data['status'] ?? 'open').toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report ID: ${widget.reportId}'),
          if (data['relatedInvoiceId'] != null || data['invoiceId'] != null)
            Text('Invoice ID: ${data['relatedInvoiceId'] ?? data['invoiceId']}'),
          if (data['reportedBy'] != null)
            Text('Reported By: ${data['reportedBy']}'),
          if ((data['reportText'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(data['reportText']),
            ),
          if (ts != null) Text('Date: ${formatDate(ts)}'),
          Text('Status: $status'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              if (data['relatedInvoiceId'] != null || data['invoiceId'] != null)
                ElevatedButton(
                  onPressed: () {
                    final invId =
                        data['relatedInvoiceId'] ?? data['invoiceId'];
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminInvoiceDetailPage(
                          invoiceId: invId,
                          userId: widget.userId,
                        ),
                      ),
                    );
                  },
                  child: const Text('View Invoice'),
                ),
              if (data['customerId'] != null)
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminUserDetailPage(userId: data['customerId']),
                      ),
                    );
                  },
                  child: const Text('Customer Profile'),
                ),
              if (data['mechanicId'] != null)
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            AdminUserDetailPage(userId: data['mechanicId']),
                      ),
                    );
                  },
                  child: const Text('Mechanic Profile'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Internal Notes'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: _saveNotes,
                child: const Text('Save Notes'),
              ),
              const SizedBox(width: 16),
              if (status != 'closed')
                ElevatedButton(
                  onPressed: _closeReport,
                  child: const Text('Mark Closed'),
                ),
            ],
          ),
        ],
      ),
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
          appBar: AppBar(title: const Text('Report Details')),
          body: FutureBuilder<Map<String, dynamic>?>(
            future: _reportFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const Center(child: Text('Report not found'));
              }
              return _buildDetails(snapshot.data!);
            },
          ),
        );
      },
    );
  }
}
