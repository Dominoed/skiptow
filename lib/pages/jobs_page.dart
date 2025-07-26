import 'package:flutter/material.dart';
import 'service_records_page.dart';

/// Wrapper page that displays service jobs for the logged in user.
class JobsPage extends StatelessWidget {
  final String userId;
  const JobsPage({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return ServiceRecordsPage(userId: userId, title: 'Jobs');
  }
}
