import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

/// Placeholder page that simulates Stripe payment processing.
class PaymentProcessingPage extends StatefulWidget {
  final String invoiceId;
  const PaymentProcessingPage({super.key, required this.invoiceId});

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  @override
  void initState() {
    super.initState();
    _startCheckout();
  }

  Future<void> _startCheckout() async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('createStripeCheckout')
          .call({
        'invoiceId': widget.invoiceId,
        'userId': FirebaseAuth.instance.currentUser!.uid,
      });
      final checkoutUrl = response.data['url'];
      if (await canLaunch(checkoutUrl)) {
        await launch(checkoutUrl);
      } else {
        throw 'Could not launch $checkoutUrl';
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
