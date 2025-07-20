import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'general_chat_page.dart';

/// Page for admins to manage general message threads with any user.
class AdminMessageCenterPage extends StatelessWidget {
  final String adminId;
  const AdminMessageCenterPage({super.key, required this.adminId});

  Future<void> _startNewChat(BuildContext context) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Username'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text('Chat'),
            ),
          ],
        );
      },
    );

    if (username == null || username.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('User not found')));
      }
      return;
    }
    final userId = snap.docs.first.id;
    _openThreadWithUser(context, userId, username);
  }

  Future<void> _openThreadWithUser(
      BuildContext context, String userId, String username) async {
    String? threadId;
    final snapshot = await FirebaseFirestore.instance
        .collection('messages_general')
        .where('participants', arrayContains: adminId)
        .get();
    for (final doc in snapshot.docs) {
      final parts = List<String>.from(doc.data()['participants'] ?? []);
      if (parts.contains(userId)) {
        threadId = doc.id;
        break;
      }
    }
    if (threadId == null) {
      final ref = FirebaseFirestore.instance.collection('messages_general').doc();
      await ref.set({
        'participants': [adminId, userId],
        'lastMessage': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      threadId = ref.id;
    }
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GeneralChatPage(
            threadId: threadId!,
            currentUserId: adminId,
            otherUserId: userId,
            otherUsername: username,
            currentUsername: 'Admin',
            currentUserRole: 'admin',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('messages_general')
        .where('participants', arrayContains: adminId)
        .orderBy('updatedAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Center'),
        actions: [
          IconButton(
            onPressed: () => _startNewChat(context),
            icon: const Icon(Icons.add_comment),
            tooltip: 'New Chat',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No message threads'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final parts = List<String>.from(data['participants'] ?? []);
              parts.remove(adminId);
              final otherId = parts.isNotEmpty ? parts.first : '';
              final Timestamp? ts = data['updatedAt'];
              final last = data['lastMessage'] ?? '';
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherId)
                    .get(),
                builder: (context, snap) {
                  final name = snap.data?.data()?['username'] ?? otherId;
                  return ListTile(
                    title: Text(name),
                    subtitle: Text(last),
                    trailing: Text(
                      ts != null
                          ? DateFormat('MM/dd h:mm a')
                              .format(ts.toDate().toLocal())
                          : '',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => _openThreadWithUser(context, otherId, name),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
