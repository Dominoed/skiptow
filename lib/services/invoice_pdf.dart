import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';

String _fmt(Timestamp? ts) {
  if (ts == null) return '';
  final dt = ts.toDate().toLocal();
  return dt.toString().split('.').first;
}

Future<List<int>> generateInvoicePdf(Map<String, dynamic> data, String invoiceId) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      build: (context) {
        final location = data['location'];
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Invoice #${data['invoiceNumber'] ?? invoiceId}',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            pw.Text('Customer: ${data['customerName'] ?? data['customerUsername'] ?? 'Unknown'}'),
            pw.Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
            if ((data['description'] ?? '').toString().isNotEmpty)
              pw.Text('Issue: ${data['description']}'),
            if (data['finalPrice'] != null)
              pw.Text('Final Price: \$${(data['finalPrice'] as num).toStringAsFixed(2)}'),
            if (location != null)
              pw.Text('Location: ${location['lat']}, ${location['lng']}'),
            pw.SizedBox(height: 12),
            pw.Text('Timeline:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: 'Requested: ${_fmt(data['createdAt'] as Timestamp?)}'),
            if (data['acceptedAt'] != null || data['mechanicAcceptedAt'] != null || data['mechanicAcceptedTimestamp'] != null)
              pw.Bullet(text: 'Accepted: ${_fmt((data['mechanicAcceptedAt'] ?? data['acceptedAt'] ?? data['mechanicAcceptedTimestamp']) as Timestamp?)}'),
            if (data['completedAt'] != null || data['jobCompletedTimestamp'] != null)
              pw.Bullet(text: 'Completed: ${_fmt((data['completedAt'] ?? data['jobCompletedTimestamp']) as Timestamp?)}'),
            if (data['closedAt'] != null)
              pw.Bullet(text: 'Closed: ${_fmt(data['closedAt'] as Timestamp?)}'),
          ],
        );
      },
    ),
  );
  return pdf.save();
}
