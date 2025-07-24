import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard_page.dart';

class CancelPage extends StatelessWidget {
  const CancelPage({super.key});

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
      appBar: AppBar(title: const Text('Payment Canceled')),
      body: const Center(
        child: Text(
          '❌ Payment canceled. Redirecting...',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
