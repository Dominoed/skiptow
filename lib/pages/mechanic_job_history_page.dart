import 'package:flutter/material.dart';
import 'service_records_page.dart';

/// Displays a mechanic's job history using the consolidated list page.
class MechanicJobHistoryPage extends StatelessWidget {
  final String mechanicId;
  const MechanicJobHistoryPage({super.key, required this.mechanicId});

  @override
  Widget build(BuildContext context) {
    return ServiceRecordsPage(userId: mechanicId, title: 'Job History');
  }
}
