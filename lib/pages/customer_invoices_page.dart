import 'package:flutter/material.dart';
import 'service_records_page.dart';

/// Displays invoices for the logged in customer using the consolidated page.
class CustomerInvoicesPage extends StatelessWidget {
  final String userId;
  const CustomerInvoicesPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ServiceRecordsPage(userId: userId, title: 'My Invoices');
  }
}
