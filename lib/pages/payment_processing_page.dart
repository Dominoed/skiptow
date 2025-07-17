import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Placeholder page that simulates Stripe payment processing.
class PaymentProcessingPage extends StatefulWidget {
  final String invoiceId;
  const PaymentProcessingPage({super.key, required this.invoiceId});

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () async {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(widget.invoiceId)
          .update({'paymentStatus': 'paid'});
      if (mounted) {
        setState(() {
          _done = true;
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Center(
        child: !_done
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Processing payment via Stripe…'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Payment successful (placeholder).'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Return to Invoice'),
                  ),
                ],
              ),
      ),
    );
  }
}
