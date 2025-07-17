import 'package:flutter/material.dart';

/// Displays the app's terms of service.
class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
          'Suspendisse potenti. Nulla facilisi.\n\n'
          'Aliquam erat volutpat. Donec consequat, nunc eget gravida '
          'tincidunt, lorem mauris ultrices dui, a hendrerit turpis '
          'massa id velit.\n\n'
          'Curabitur vehicula, nisl sit amet varius dignissim, orci '
          'diam dictum arcu, et tempor metus nisi eget leo.',
        ),
      ),
    );
  }
}