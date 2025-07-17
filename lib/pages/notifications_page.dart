import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple notifications page for mechanics.
///
/// Shows updates for invoices where the mechanic is assigned.
/// Notifications are stored only in Firestore; read/cleared state
/// is tracked locally using [ValueNotifier]s.
class NotificationsPage extends StatelessWidget {
  final String userId;
  NotificationsPage({super.key, required this.userId});

  final ValueNotifier<Set<String>> _cleared = ValueNotifier(<String>{});
  final ValueNotifier<Set<String>> _read = ValueNotifier(<String>{});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots();

    return ValueListenableBuilder<Set<String>>(
      valueListenable: _cleared,
      builder: (context, clearedIds, _) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final visibleDocs =
                docs.where((d) => !clearedIds.contains(d.id)).toList();

            return Scaffold(
              appBar: AppBar(
                title: const Text('Notifications'),
                actions: [
                  if (visibleDocs.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      tooltip: 'Clear',
                      onPressed: () {
                        _cleared.value = {
                          ...clearedIds,
                          ...visibleDocs.map((d) => d.id)
                        };
                      },
                    ),
                ],
              ),
              body: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : visibleDocs.isEmpty
                      ? const Center(child: Text('No notifications'))
                      : ValueListenableBuilder<Set<String>>(
                          valueListenable: _read,
                          builder: (context, readIds, __) {
                            return ListView.builder(
                              itemCount: visibleDocs.length,
                              itemBuilder: (context, index) {
                                final doc = visibleDocs[index];
                                final data = doc.data();
                                final status = data['status'] ?? '';
                                final message = status == 'active'
                                    ? "New request received from ${data['customerId']}"
                                    : status == 'completed'
                                        ? 'Request marked as completed.'
                                        : status == 'closed'
                                            ? 'Request closed.'
                                            : "Status updated: $status";
                                final unread = !readIds.contains(doc.id);
                                return ListTile(
                                  leading: Icon(
                                    status == 'completed'
                                        ? Icons.check_circle
                                        : status == 'closed'
                                            ? Icons.archive
                                            : Icons.notifications,
                                    color: status == 'completed'
                                        ? Colors.green
                                        : status == 'closed'
                                            ? Colors.blueGrey
                                            : Colors.blue,
                                  ),
                                  title: Text(message),
                                  tileColor:
                                      unread ? Colors.grey[300] : Colors.white,
                                  onTap: () {
                                    _read.value = {...readIds, doc.id};
                                  },
                                );
                              },
                            );
                          },
                        ),
            );
          },
        );
      },
    );
  }
}
