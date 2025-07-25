import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Handles Firebase Cloud Messaging and local notifications.
class PushNotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  /// Initialize messaging and local notification plugins.
  ///
  /// [onNotificationTap] is triggered when the user taps a displayed
  /// notification.
  Future<void> initialize({void Function(NotificationResponse)? onNotificationTap}) async {
    await _messaging.requestPermission();
    final settings = const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );
  }

  /// Listen for foreground messages.
  void listenToForegroundMessages() {
    FirebaseMessaging.onMessage.listen(handleMessage);
  }

  /// Registers the current device token for the given user in Firestore.
  Future<void> registerDevice(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('tokens')
        .doc(token);
    await ref.set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': Platform.operatingSystem,
    });
  }

  /// Removes the current device token for the given user in Firestore
  /// and attempts to delete it from Firebase Messaging.
  Future<void> unregisterDevice(String userId) async {
    final token = await _messaging.getToken();
    if (token == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('tokens')
        .doc(token);
    await ref.delete();
    try {
      await _messaging.deleteToken();
    } catch (_) {}
  }

  /// Display the notification locally when received.
  Future<void> handleMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'default_channel',
        'Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _localPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
    );
  }

  /// Show a notification that a new service request was received.
  Future<void> showNewRequest(String body) async {
    await _showSimple('New Service Request Received', body);
  }

  /// Show a notification that a mechanic accepted a request.
  Future<void> showRequestAccepted(String body) async {
    await _showSimple('Mechanic Accepted Your Request', body);
  }

  /// Show a payment reminder notification.
  Future<void> showPaymentReminder(String body) async {
    await _showSimple('Payment Reminder: Invoice Overdue', body);
  }

  Future<void> _showSimple(String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'default_channel',
        'Notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _localPlugin.show(title.hashCode, title, body, details);
  }
}
