import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

bool getBool(Map<String, dynamic>? data, String key, {bool defaultValue = false}) {
  final value = data?[key];
  if (value is bool) return value;
  if (value == null) return defaultValue;
  if (value is num) return value != 0;
  final str = value.toString().toLowerCase();
  if (str == 'true') return true;
  if (str == 'false') return false;
  return defaultValue;
}

/// Display a dialog for mechanics to rate a customer.
/// Stores the result in Firestore under `mechanicFeedback`.
Future<void> showCustomerRatingDialog(
    BuildContext context, String invoiceId) async {
  int rating = 0;
  final controller = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Rate Customer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.orange,
                      ),
                      onPressed: () => setState(() => rating = index + 1),
                    );
                  }),
                ),
                TextField(
                  controller: controller,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Additional Feedback (optional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              TextButton(
                onPressed:
                    rating == 0 ? null : () => Navigator.pop(context, true),
                child: const Text('Submit'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == true) {
    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(invoiceId)
        .collection('mechanicFeedback')
        .add({
      'rating': rating,
      if (controller.text.trim().isNotEmpty)
        'feedbackText': controller.text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
