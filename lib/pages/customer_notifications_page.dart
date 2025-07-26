import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils.dart';

/// Page that displays notifications for a customer.
class CustomerNotificationsPage extends StatelessWidget {
  final String userId;

  const CustomerNotificationsPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('notifications')
        .doc(userId)
        .collection('messages')
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
              final body = data['body'] ?? '';
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
                    if (body.isNotEmpty) Text(body),
                    Text(formatDate(ts)),
                  ],
                ),
                onTap: () {
                  if (!read) {
                    FirebaseFirestore.instance
                        .collection('notifications')
                        .doc(userId)
                        .collection('messages')
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
