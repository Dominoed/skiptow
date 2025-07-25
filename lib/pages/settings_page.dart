import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'mechanic_qr_page.dart';
import 'package:skiptow/services/push_notification_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _role;
  String? _username;
  double? _radiusMiles;
  bool? _isActive;
  bool? _unavailable;
  bool _isPro = false;
  bool _loadingPro = false;
  bool _loadingCancel = false;
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadAppVersion();
  }

  Future<void> _loadUserInfo() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          final data = doc.data();
          _role = data?['role'];
          _username = data?['username'];
          _radiusMiles = (data?['radiusMiles'] as num?)?.toDouble();
          _isActive = data?['isActive'] as bool?;
          _unavailable = data?['unavailable'] as bool?;
          _isPro = data?['isPro'] == true;
        });
      }
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
        });
      }
    } catch (_) {
      // Keep default version on failure
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (user == null || uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      await user.delete();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await PushNotificationService().unregisterDevice(user.uid);
    }
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'Are you sure you want to delete your account? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _upgradeToPro() async {
    if (_loadingPro) return;
    setState(() {
      _loadingPro = true;
    });
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createProSubscriptionSession')
          .call();
      final url = (result.data['url'] ?? result.data['sessionId'])?.toString();
      if (url == null) throw Exception('Checkout URL missing');
      final uri = Uri.parse(url.startsWith('http')
          ? url
          : 'https://checkout.stripe.com/pay/$url');
      var launched = false;
      if (await canLaunchUrl(uri)) {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!launched) {
        launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      }
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not open url")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start subscription')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingPro = false;
        });
      }
    }
  }

  Future<void> _cancelPro() async {
    if (_loadingCancel) return;
    setState(() {
      _loadingCancel = true;
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('cancelProSubscription')
          .call();
      if (mounted) {
        setState(() {
          _isPro = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription cancelled')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel subscription')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingCancel = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${user?.email ?? 'N/A'}'),
            Text('Username: ${_username ?? 'Loading...'}'),
            Text('Role: ${_role ?? 'Loading...'}'),
            Text('User ID: ${user?.uid ?? 'N/A'}'),
            if (_role == 'mechanic') ...[
              const SizedBox(height: 20),
              Text('Radius: ${_radiusMiles?.toString() ?? 'N/A'} miles'),
              Text('Status: ${(_isActive ?? false) ? 'Active' : 'Inactive'}'),
              Text('Temporarily Unavailable: ${(_unavailable ?? false) ? 'Yes' : 'No'}'),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isPro || _loadingPro ? null : _upgradeToPro,
              child: _loadingPro
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Subscribe to Pro - \$10/month'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: !_isPro || _loadingCancel ? null : _cancelPro,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: _loadingCancel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unsubscribe'),
            ),
            if (_isPro) ...[
              const SizedBox(height: 8),
              const Text('You have an active Pro subscription.'),
              const SizedBox(height: 8),
              if (_role == 'mechanic')
                ElevatedButton(
                  onPressed: () {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MechanicQrPage(mechanicId: uid),
                        ),
                      );
                    }
                  },
                  child: const Text('Referral QR Code'),
                ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _logout,
              child: const Text('Log Out'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _confirmDelete,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete My Account'),
            ),
            const Spacer(),
            Center(
              child: Text(
                'App Version: $_appVersion',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
