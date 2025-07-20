import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'terms_of_service_page.dart';

/// Page with emergency contact info and dispute instructions for customers.
class EmergencySupportPage extends StatelessWidget {
  const EmergencySupportPage({super.key});

  Future<void> _emailSupport() async {
    final uri = Uri.parse('mailto:support@skiptow.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Support'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For urgent issues, mechanic no-shows, or payment disputes, '
              'please contact our support team immediately. Include your '
              'invoice number or job details so we can assist quickly.',
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _emailSupport,
                child: const Text('Email support@skiptow.com'),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TermsOfServicePage(),
                  ),
                );
              },
              child: const Text('View Terms & Conditions'),
            ),
          ],
        ),
      ),
    );
  }
}
