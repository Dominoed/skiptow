import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple helper for fetching and caching a global alert.
class AlertService {
  static Map<String, dynamic>? _cachedAlert;
  static bool _dismissed = false;

  /// Fetch the current global alert if one exists and it hasn't
  /// been dismissed for this session.
  static Future<Map<String, dynamic>?> fetchAlert() async {
    if (_dismissed) return null;
    if (_cachedAlert != null) return _cachedAlert;
    try {
      final doc = await FirebaseFirestore.instance
          .doc('alerts/global/currentAlert')
          .get();
      if (doc.exists) {
        _cachedAlert = doc.data();
      }
    } catch (_) {
      // Ignore errors and treat as no alert
    }
    return _cachedAlert;
  }

  /// Mark the alert as dismissed for the current session.
  static void dismiss() {
    _dismissed = true;
  }
}
