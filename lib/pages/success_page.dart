import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_page.dart';

class SuccessPage extends StatelessWidget {
  const SuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    Future.delayed(const Duration(seconds: 4), () {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DashboardPage(userId: uid)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Success')),
      body: const Center(
        child: Text(
          '✅ Subscription successful! Redirecting...',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
