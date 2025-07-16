import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'mechanic_dashboard.dart';
import 'customer_dashboard.dart';
import 'login_page.dart';
import 'settings_page.dart';

class DashboardPage extends StatelessWidget {
  final String userId;
  const DashboardPage({super.key, required this.userId});

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (doc.exists) {
      return doc.data()?['role'];
    }
    return null;
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data;
        Widget? dash;
        if (role == 'mechanic') {
          dash = MechanicDashboard(userId: userId);
        } else if (role == 'customer') {
          dash = CustomerDashboard(userId: userId);
        } else {
          return const Scaffold(
            body: Center(child: Text('❌ Unknown role or error')),
          );
        }

        return Scaffold(
          body: dash,
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'settings_button',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                tooltip: 'Settings',
                child: const Icon(Icons.settings),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'logout_button',
                onPressed: () => _logout(context),
                tooltip: 'Logout',
                child: const Icon(Icons.logout),
              ),
            ],
          ),
        );
      },
    );
  }
}
