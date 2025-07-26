import 'package:flutter/material.dart';
import 'service_records_page.dart';

/// Displays service request history for a customer using the consolidated list page.
class ServiceRequestHistoryPage extends StatelessWidget {
  final String userId;
  const ServiceRequestHistoryPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ServiceRecordsPage(userId: userId, title: 'Service Request History');
  }
}
