import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:skiptow/pages/dashboard_page.dart';
import 'package:skiptow/pages/signup_page.dart';
import 'package:skiptow/pages/terms_of_service_page.dart';
import 'package:skiptow/pages/privacy_policy_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  String _status = '';
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _login() async {
    setState(() { _status = 'Signing in...'; });
    try {
      UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passController.text.trim(),
      );
      final uid = cred.user?.uid;
      if (uid != null) {
        // Optional: You can fetch extra user data here
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DashboardPage(userId: uid)),
        );
      } else {
        _status = 'No user ID found';
      }
    } on FirebaseAuthException catch (e) {
      _status = '❌ ${e.message}';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SkipTow Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _login, child: const Text('Login')),
            TextButton(onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupPage()));
            }, child: const Text('Create new account')),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TermsOfServicePage(),
                      ),
                    );
                  },
                  child: const Text('Terms of Service'),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyPage(),
                      ),
                    );
                  },
                  child: const Text('Privacy Policy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
