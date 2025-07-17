import 'package:flutter/material.dart';

/// Displays the app's privacy policy.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          'This privacy policy explains how your information is handled. '
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit.\n\n'
          'Praesent id velit et sapien mattis maximus. Etiam semper, '
          'tortor vitae consectetur eleifend, purus lectus malesuada '
          'orci, nec pulvinar lectus neque sit amet justo.\n\n'
          'Sed euismod, mauris in fermentum bibendum, risus nisl cursus '
          'quam, vitae tempus massa nulla sit amet risus.',
        ),
      ),
    );
  }
}
