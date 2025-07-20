import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_page.dart';

/// Displays basic account settings and information for the logged in user.
class AccountSettingsPage extends StatefulWidget {
  final String userId;

  const AccountSettingsPage({super.key, required this.userId});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late final Future<Map<String, dynamic>> _userFuture;

  @override
  void initState() {
    super.initState();
    _userFuture = _loadUserData();
  }

  Future<Map<String, dynamic>> _loadUserData() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    final data = doc.data() ?? {};
    return {
      'username': data['username'],
      'email': data['email'],
      'role': data['role'],
      'radiusMiles': data['radiusMiles'],
      'isActive': data['isActive'],
      'unavailable': data['unavailable'],
    };
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            return const Center(child: Text('Unable to load account data'));
          }

          final data = snapshot.data!;
          final role = data['role'] ?? 'N/A';
          final isMechanic = role == 'mechanic';

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Username: ${data['username'] ?? 'N/A'}'),
                Text('Email: ${data['email'] ?? 'N/A'}'),
                Text('Role: $role'),
                if (isMechanic) ...[
                  const SizedBox(height: 20),
                  Text('Radius: ${data['radiusMiles']?.toString() ?? 'N/A'} miles'),
                  Text('Status: ${(data['isActive'] ?? false) ? 'Active' : 'Inactive'}'),
                  Text('Temporarily Unavailable: ${(data['unavailable'] ?? false) ? 'Yes' : 'No'}'),
                ],
                const Spacer(),
                ElevatedButton(
                  onPressed: _logout,
                  child: const Text('Log Out'),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: null,
                  child: const Text('Delete My Account'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
