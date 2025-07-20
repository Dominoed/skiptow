import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'general_chat_page.dart';

/// Help page allowing customers and mechanics to chat with support.
class HelpSupportPage extends StatelessWidget {
  final String userId;
  final String userRole; // customer or mechanic
  const HelpSupportPage({super.key, required this.userId, required this.userRole});

  Future<String?> _getAdminId() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<String?> _getUsername(String id) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
    return doc.data()?['username'] as String?;
  }

  Future<void> _contactSupport() async {
    final uri = Uri.parse('mailto:support@skiptow.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _startChat(BuildContext context) async {
    final adminId = await _getAdminId();
    if (adminId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Support unavailable')));
      }
      return;
    }

    String? threadId;
    final existing = await FirebaseFirestore.instance
        .collection('messages_general')
        .where('participants', arrayContains: userId)
        .get();
    for (final doc in existing.docs) {
      final parts = List<String>.from(doc.data()['participants'] ?? []);
      if (parts.contains(adminId)) {
        threadId = doc.id;
        break;
      }
    }
    if (threadId == null) {
      final ref = FirebaseFirestore.instance.collection('messages_general').doc();
      await ref.set({
        'participants': [userId, adminId],
        'lastMessage': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      threadId = ref.id;
    }

    final username = await _getUsername(userId) ?? 'User';

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GeneralChatPage(
            threadId: threadId!,
            currentUserId: userId,
            otherUserId: adminId,
            otherUsername: 'Admin',
            currentUsername: username,
            currentUserRole: userRole,
          ),
        ),
      );
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('How to use the app'),
            const Text(
              'Customers can browse nearby mechanics on the map and send service '
              'requests directly from their profile. Mechanics can toggle their '
              'availability and manage jobs from the dashboard.',
            ),
            _sectionTitle('How to submit requests'),
            const Text(
              'From a mechanic profile, tap "Request Service" and fill out the '
              'vehicle details and problem description. You will be notified once '
              'a mechanic accepts the job.',
            ),
            _sectionTitle('How to receive jobs'),
            const Text(
              'Mechanics get notified of new requests in real time. View open '
              'invoices to accept or complete a job.',
            ),
            _sectionTitle('FAQ'),
            const Text(
              'Browse our frequently asked questions or start a chat below if '
              'you need more help.',
            ),
            _sectionTitle('Contact support'),
            const Text(
              'If you have any issues with the app or your account, you can reach '
              'our support team at any time.',
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _contactSupport,
                child: const Text('Email support@skiptow.com'),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () => _startChat(context),
                child: const Text('Chat with Support'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('This does not request a mechanic!'),
          ],
        ),
      ),
    );
  }
}
