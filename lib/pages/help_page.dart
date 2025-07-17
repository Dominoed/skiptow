import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simple help and support page with usage instructions.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  Future<void> _contactSupport() async {
    final uri = Uri.parse('mailto:support@skiptow.com');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('How to use the app'),
            const Text(
              'Customers can browse nearby mechanics on the map and send service '
              'requests directly from their profile. Mechanics can toggle their '
              'availability and manage jobs from the dashboard.',
            ),
            _sectionTitle('How to submit requests'),
            const Text(
              'From a mechanic profile, tap \"Request Service\" and fill out the '
              'vehicle details and problem description. You will be notified once '
              'a mechanic accepts the job.',
            ),
            _sectionTitle('How to receive jobs'),
            const Text(
              'Mechanics get notified of new requests in real time. View open '
              'invoices to accept or complete a job.',
            ),
            _sectionTitle('How to contact support'),
            const Text(
              'If you have any issues with the app or your account, you can reach '
              'our support team at any time.',
            ),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: _contactSupport,
                child: const Text('Contact Support'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
