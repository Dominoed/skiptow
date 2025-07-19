import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Page for system admins to broadcast a message to mechanics,
/// customers, or both.
class AdminBroadcastMessagePage extends StatefulWidget {
  final String userId;
  const AdminBroadcastMessagePage({super.key, required this.userId});

  @override
  State<AdminBroadcastMessagePage> createState() => _AdminBroadcastMessagePageState();
}

class _AdminBroadcastMessagePageState extends State<AdminBroadcastMessagePage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  String _audience = 'both';
  bool _sendPush = true;
  bool _urgent = false;
  bool _sending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['role'] as String?;
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty || _sending) return;

    setState(() {
      _sending = true;
    });

    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('users');
    if (_audience == 'mechanics') {
      query = query.where('role', isEqualTo: 'mechanic');
    } else if (_audience == 'customers') {
      query = query.where('role', isEqualTo: 'customer');
    }

    final snapshot = await query.get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      final ref = FirebaseFirestore.instance
          .collection('notifications')
          .doc(doc.id)
          .collection('messages')
          .doc();
      batch.set(ref, {
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        if (!_sendPush) 'sendFcm': false,
      });
    }
    await batch.commit();

    if (_urgent) {
      await FirebaseFirestore.instance
          .doc('alerts/global/currentAlert')
          .set({
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message sent to ${snapshot.docs.length} users')),
      );
      Navigator.pop(context);
    }

    setState(() {
      _sending = false;
    });
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
              Navigator.pop(context);
            }
          });
          return const SizedBox.shrink();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Broadcast Message'),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    prefixIcon: Icon(Icons.message),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _audience,
                  decoration: const InputDecoration(labelText: 'Send To'),
                  items: const [
                    DropdownMenuItem(value: 'mechanics', child: Text('All Mechanics')),
                    DropdownMenuItem(value: 'customers', child: Text('All Customers')),
                    DropdownMenuItem(value: 'both', child: Text('All Users')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _audience = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Send push notification'),
                  value: _sendPush,
                  onChanged: (v) {
                    setState(() => _sendPush = v);
                  },
                ),
                SwitchListTile(
                  title: const Text('Mark as urgent global alert'),
                  value: _urgent,
                  onChanged: (v) {
                    setState(() => _urgent = v);
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? 'Sending...' : 'Send Message'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    await FirebaseFirestore.instance
                        .doc('alerts/global/currentAlert')
                        .delete();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Global alert cleared')),
                      );
                    }
                  },
                  child: const Text('Clear Current Alert'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

