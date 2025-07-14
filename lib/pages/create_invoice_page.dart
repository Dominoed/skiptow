import 'package:flutter/material.dart';

class CreateInvoicePage extends StatelessWidget {
  final String customerId;
  final String mechanicId;
  final String mechanicUsername;
  final double distance;

  const CreateInvoicePage({
    super.key,
    required this.customerId,
    required this.mechanicId,
    required this.mechanicUsername,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Invoice")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text("Mechanic: $mechanicUsername"),
            Text("Distance: ${distance.toStringAsFixed(1)} mi"),
            Text("Customer ID: $customerId"),
            // TODO: add the rest of your form here
          ],
        ),
      ),
    );
  }
}
