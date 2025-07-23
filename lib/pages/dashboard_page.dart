import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'mechanic_dashboard.dart';
import 'customer_dashboard.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'admin_dashboard.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'help_support_page.dart';
import 'service_request_history_page.dart';
import 'vehicle_history_page.dart';

class DashboardPage extends StatefulWidget {
  final String userId;
  // Track if the role snackbar has been shown for this session
  static bool _snackbarShown = false;
  const DashboardPage({super.key, required this.userId});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey mechKey = GlobalKey();
  final GlobalKey custKey = GlobalKey();

  Future<String?> _getRole() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists) {
      return doc.data()?['role'];
    }
    return null;
  }

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    await const FlutterSecureStorage().delete(key: 'session_token');
    // Reset snackbar flag so message shows on next login
    DashboardPage._snackbarShown = false;
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
        if (role == 'admin') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminDashboardPage(userId: widget.userId),
                ),
              );
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!DashboardPage._snackbarShown && role != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Logged in as $role')),
              );
            }
          });
          DashboardPage._snackbarShown = true;
        }
        Widget? dash;
        if (role == 'mechanic') {
          dash = MechanicDashboard(key: mechKey, userId: widget.userId);
        } else if (role == 'customer') {
          dash = CustomerDashboard(key: custKey, userId: widget.userId);
        } else {
          return const Scaffold(
            body: Center(child: Text('❌ Unknown role or error')),
          );
        }

        return Scaffold(
          body: dash,
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FloatingActionButton(
                heroTag: 'refresh_button',
                onPressed: () {
                  if (role == 'mechanic') {
                    (mechKey.currentState as dynamic?)?.refreshLocation();
                  } else {
                    (custKey.currentState as dynamic?)?.refreshLocation();
                  }
                },
                tooltip: 'Refresh Location',
                child: const Icon(Icons.my_location),
              ),
              const SizedBox(height: 12),
              if (role == 'admin') ...[
                FloatingActionButton.extended(
                  heroTag: 'admin_button',
                  onPressed: () async {
                    final doc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.userId)
                        .get();
                    final currentRole = doc.data()?['role'];
                    if (currentRole == 'admin') {
                      // User confirmed as admin. Navigate to dashboard.
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminDashboardPage(userId: widget.userId),
                          ),
                        );
                      }
                    } else {
                      // Role changed or user not admin.
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Access denied.')),
                        );
                      }
                    }
                  },
                  label: const Text('Admin Dashboard'),
                  icon: const Icon(Icons.admin_panel_settings),
                ),
                const SizedBox(height: 12),
              ],
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
                heroTag: 'help_button',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HelpSupportPage(
                        userId: widget.userId,
                        userRole: role ?? 'user',
                      ),
                    ),
                  );
                },
                tooltip: 'Help / Support',
                child: const Icon(Icons.help_outline),
              ),
              if (role == 'customer') ...[
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'history_button',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ServiceRequestHistoryPage(userId: widget.userId),
                      ),
                    );
                  },
                  tooltip: 'My Service Requests',
                  child: const Icon(Icons.history),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'vehicles_button',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VehicleHistoryPage(userId: widget.userId),
                      ),
                    );
                  },
                  tooltip: 'My Vehicles',
                  child: const Icon(Icons.directions_car),
                ),
              ],
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
