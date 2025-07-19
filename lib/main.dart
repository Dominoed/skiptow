import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/push_notification_service.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/mechanic_request_queue_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _pushService.initialize(onNotificationTap: _handleNotificationTap);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final user = FirebaseAuth.instance.currentUser;
  runApp(MyApp(initialUserId: user?.uid));
}

final PushNotificationService _pushService = PushNotificationService();

void _handleNotificationTap(NotificationResponse response) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => MechanicRequestQueuePage(mechanicId: user.uid),
    ),
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  await _pushService.handleMessage(message);
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  final String? initialUserId;
  const MyApp({super.key, this.initialUserId});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription<User?> _authSub;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = widget.initialUserId;
    _pushService.listenToForegroundMessages();
    if (_currentUserId != null) {
      _pushService.registerDevice(_currentUserId!);
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && _currentUserId != null) {
        setState(() {
          _currentUserId = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = navigatorKey.currentContext;
          if (context != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session expired. Please log in again.')),
            );
          }
        });
      } else if (user != null) {
        setState(() {
          _currentUserId = user.uid;
        });
        _pushService.registerDevice(user.uid);
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SkipTow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
      home: _currentUserId != null
          ? DashboardPage(userId: _currentUserId!)
          : const LoginPage(),
    );
  }
}
