import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils.dart';

/// Page that displays notifications for a mechanic.
class MechanicNotificationsPage extends StatelessWidget {
  final String userId;

  const MechanicNotificationsPage({super.key, required this.userId});

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return DateFormat('MM/dd h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('notifications_mechanics')
        .doc(userId)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No notifications'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final title = data['title'] ?? '';
              final message = data['message'] ?? '';
              final Timestamp? ts = data['timestamp'];
              final bool read = getBool(data, 'read');
              return ListTile(
                title: Text(
                  title,
                  style: TextStyle(
                    fontWeight: read ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.isNotEmpty)
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(_formatDate(ts)),
                  ],
                ),
                trailing: read
                    ? null
                    : const Icon(
                        Icons.circle,
                        size: 10,
                        color: Colors.blue,
                      ),
                onTap: () {
                  if (!read) {
                    FirebaseFirestore.instance
                        .collection('notifications_mechanics')
                        .doc(userId)
                        .collection('notifications')
                        .doc(doc.id)
                        .update({'read': true});
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
