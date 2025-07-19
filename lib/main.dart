import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'services/push_notification_service.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/mechanic_request_queue_page.dart';
import 'pages/customer_invoices_page.dart';
import 'pages/invoice_detail_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pages/maintenance_mode_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _pushService.initialize(onNotificationTap: _handleNotificationTap);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const MyApp());
}

final PushNotificationService _pushService = PushNotificationService();

void _handleNotificationTap(NotificationResponse response) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get()
      .then((doc) {
    final role = doc.data()?['role'];
    final defaultPage = role == 'customer'
        ? CustomerInvoicesPage(userId: user.uid)
        : MechanicRequestQueuePage(mechanicId: user.uid);

    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = jsonDecode(response.payload!);
        final invoiceId = data['invoiceId'];
        if (invoiceId is String) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => InvoiceDetailPage(
                invoiceId: invoiceId,
                role: role,
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => defaultPage),
    );
  });
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform);
  await _pushService.handleMessage(message);
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription<User?> _authSub;
  StreamSubscription<ConnectivityResult>? _connectSub;
  String? _currentUserId;
  bool _loading = true;
  bool _offlineBannerVisible = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _maintSub;
  bool? _maintenanceMode;
  String _maintenanceMessage = '';

  @override
  void initState() {
    super.initState();
    _pushService.listenToForegroundMessages();
    _initConnectivity();
    _listenMaintenance();
    _initAuth();
  }

  void _listenMaintenance() {
    _maintSub = FirebaseFirestore.instance
        .collection('system')
        .doc('config')
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data != null) {
        setState(() {
          _maintenanceMode = data['maintenanceMode'] == true;
          _maintenanceMessage =
              (data['maintenanceMessage'] ?? '').toString();
        });
      }
    });
  }

  Future<void> _initAuth() async {
    final storage = const FlutterSecureStorage();
    final token = await storage.read(key: 'session_token');
    if (token != null && FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInWithCustomToken(token);
      } catch (_) {
        await storage.delete(key: 'session_token');
      }
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
    setState(() { _loading = false; });
  }

  Future<void> _initConnectivity() async {
    final connectivity = Connectivity();
    final result = await connectivity.checkConnectivity();
    _updateConnectivityStatus(result);
    _connectSub = connectivity.onConnectivityChanged.listen(_updateConnectivityStatus);
  }

  void _updateConnectivityStatus(ConnectivityResult result) {
    final offline = result == ConnectivityResult.none;
    final context = navigatorKey.currentContext;
    void showBanner() {
      if (context != null) {
        ScaffoldMessenger.of(context).showMaterialBanner(
          const MaterialBanner(
            content: Text('⚠️ Offline Mode – Data may be outdated.'),
            backgroundColor: Colors.orange,
            actions: [SizedBox.shrink()],
          ),
        );
      }
    }
    if (offline && !_offlineBannerVisible) {
      if (context == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => showBanner());
      } else {
        showBanner();
      }
      _offlineBannerVisible = true;
    } else if (!offline && _offlineBannerVisible) {
      if (context != null) {
        ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
      }
      _offlineBannerVisible = false;
    }
  }

  @override
  void dispose() {
    _authSub.cancel();
    _connectSub?.cancel();
    _maintSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _maintenanceMode == null) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_maintenanceMode == true) {
      return MaterialApp(
        navigatorKey: navigatorKey,
        title: 'SkipTow',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange)),
        home: MaintenanceModePage(message: _maintenanceMessage),
      );
    }
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
