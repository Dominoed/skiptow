import 'package:flutter/material.dart';
import 'service_records_page.dart';

/// Wrapper page that displays invoices for the logged in user.
class InvoicesPage extends StatelessWidget {
  final String userId;
  const InvoicesPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ServiceRecordsPage(userId: userId, title: 'Invoices');
  }
}
