import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final user = FirebaseAuth.instance.currentUser;
  runApp(MyApp(initialUserId: user?.uid));
}

class MyApp extends StatelessWidget {
  final String? initialUserId;
  const MyApp({super.key, this.initialUserId});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkipTow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
      home: initialUserId != null
          ? DashboardPage(userId: initialUserId!)
          : const LoginPage(),
    );
  }
}
