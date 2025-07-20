import 'package:flutter/material.dart';

/// Displays legal terms and conditions.
class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Text(
                'These terms and conditions are provided as a placeholder. '
                'Replace this text with your actual legal agreement.\n\n'
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                'Suspendisse potenti. Nulla facilisi.\n\n'
                'Aliquam erat volutpat. Donec consequat, nunc eget gravida '
                'tincidunt, lorem mauris ultrices dui, a hendrerit turpis '
                'massa id velit.\n\n'
                'Curabitur vehicula, nisl sit amet varius dignissim, orci '
                'diam dictum arcu, et tempor metus nisi eget leo.',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('I Agree'),
            ),
          ),
        ],
      ),
    );
  }
}
