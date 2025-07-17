import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'payment_processing_page.dart';

/// Page to show full invoice details.
class InvoiceDetailPage extends StatefulWidget {
  final String invoiceId;
  final String role;

  const InvoiceDetailPage({
    super.key,
    required this.invoiceId,
    required this.role,
  });

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  late final Future<Map<String, dynamic>?> _invoiceFuture;
  Future<Map<String, dynamic>?> _loadInvoice() async {
    final doc = await FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .get();
    final data = doc.data();
    if (data == null) return null;
    if (data['flagged'] == true && widget.role != 'admin') return null;

    final customerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(data['customerId'])
        .get();
    final customerData = customerDoc.data();
    data['customerName'] =
        customerData?['displayName'] ?? customerData?['username'];
    data['customerUsername'] = customerData?['username'] ?? 'Unknown';
    // Optional contact info
    data['customerPhone'] =
        customerData?['phone'] ?? customerData?['phoneNumber'];
    data['customerEmail'] = customerData?['email'];

    // Fetch mechanic info
    if (data['mechanicId'] != 'any') {
      final mechDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(data['mechanicId'])
          .get();
      final mechData = mechDoc.data();
      // Preserve null if mechanic status isn't available so UI can show
      // "Unknown" rather than assuming inactive.
      data['mechanicIsActive'] = mechData?['isActive'];

      final mechLocation = mechData?['location'];
      final invoiceLocation = data['location'];
      if (widget.role == 'customer' &&
          mechLocation != null &&
          invoiceLocation != null &&
          mechLocation['lat'] != null &&
          mechLocation['lng'] != null &&
          invoiceLocation['lat'] != null &&
          invoiceLocation['lng'] != null) {
        final double meters = Geolocator.distanceBetween(
          invoiceLocation['lat'],
          invoiceLocation['lng'],
          mechLocation['lat'],
          mechLocation['lng'],
        );
        data['distanceToMechanic'] = meters / 1609.34;
      }

      // Contact details only for non-customer views
      if (widget.role != 'customer') {
        data['mechanicPhone'] =
            mechData?['phone'] ?? mechData?['phoneNumber'];
        data['mechanicEmail'] = mechData?['email'];
      }
    }
    return data;
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  @override
  void initState() {
    super.initState();
    _invoiceFuture = _loadInvoice();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _invoiceFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return Scaffold(
            appBar: AppBar(title: const Text('Invoice Details')),
            body: const Center(child: Text('Invoice not found')),
          );
        }

        final data = snapshot.data!;
        final car = data['carInfo'] ?? {};
        final carText =
            '${car['year'] ?? ''} ${car['make'] ?? ''} ${car['model'] ?? ''}'.trim();
        final location = data['location'];
        final status = data['status'] ?? 'active';
        final finalPrice = data['finalPrice'];
        final paymentStatus = data['paymentStatus'] ?? 'pending';

        final children = <Widget>[];
        if (widget.role == 'mechanic') {
          final name = data['customerName'] ?? data['customerUsername'];
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Customer: ${name ?? 'Unknown'}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
        children.add(
          Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
        );

        if (widget.role == 'customer') {
          if (data['distanceToMechanic'] != null) {
            children.add(
              Text(
                'Distance to Mechanic: '
                '${(data['distanceToMechanic'] as double).toStringAsFixed(1)} miles',
              ),
            );
          } else {
            children.add(const Text('Distance unavailable.'));
          }

          // Show mechanic availability status to customers
          final bool? mechActive = data['mechanicIsActive'] as bool?;
          String statusText = 'Mechanic Status: Unknown';
          Color? statusColor;
          if (mechActive != null) {
            statusText =
                'Mechanic Status: ${mechActive ? 'Active' : 'Inactive'}';
            statusColor = mechActive ? Colors.green : Colors.red;
          }
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }

        children.addAll([
          if (widget.role != 'mechanic')
            Text('Customer: ${data['customerName'] ?? data['customerUsername'] ?? 'Unknown'}'),
          if (carText.isNotEmpty) Text('Car: $carText'),
          if ((data['description'] ?? '').toString().isNotEmpty)
            Text('Problem: ${data['description']}'),
          if ((data['notes'] ?? '').toString().isNotEmpty)
            Text('Customer Notes:\n${data['notes']}')
          else
            const Text('No additional notes.'),
          if (widget.role == 'customer')
            Text(
              finalPrice != null
                  ? 'Final Total: \$${finalPrice.toStringAsFixed(2)}'
                  : 'Final Total: Pending',
            ),
          if (widget.role == 'customer')
            Text('Payment Status: $paymentStatus'),
          if (widget.role == 'customer')
            (data['postJobNotes'] ?? '').toString().isNotEmpty
                ? Text('Mechanic Notes:\n${data['postJobNotes']}')
                : const Text('No mechanic notes provided.'),
          // Show customer contact info only to mechanics
          if (widget.role == 'mechanic' &&
              (data['customerPhone'] ?? '').toString().isNotEmpty)
            Text('Phone: ${data['customerPhone']}'),
          if (widget.role == 'mechanic' &&
              (data['customerEmail'] ?? '').toString().isNotEmpty)
            Text('Email: ${data['customerEmail']}'),
          // Show mechanic contact info to non-customers (e.g. mechanic or admin)
          if (widget.role != 'customer' &&
              (data['mechanicPhone'] ?? '').toString().isNotEmpty)
            Text('Mechanic Phone: ${data['mechanicPhone']}'),
          if (widget.role != 'customer' &&
              (data['mechanicEmail'] ?? '').toString().isNotEmpty)
            Text('Mechanic Email: ${data['mechanicEmail']}'),
          if (location != null)
            Text('Location: ${location['lat']}, ${location['lng']}'),
          if (data['distance'] != null)
            Text('Distance: ${data['distance'].toStringAsFixed(1)} mi'),
          Text('Submitted: ${_formatDate(data['timestamp'])}'),
          Text('Status: $status'),
          if (finalPrice != null && widget.role != 'customer')
            Text('Final Price: \$${finalPrice.toString()}'),
          if (widget.role == 'mechanic')
            (data['customerReview'] ?? '').toString().isNotEmpty
                ? Text('Customer Review:\n${data['customerReview']}')
                : const Text('No customer review provided.'),
        ]);

        if (widget.role == 'mechanic' && status == 'accepted') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId)
                      .update({'status': 'arrived'});

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Arrival confirmed.')),
                    );
                  }
                },
                child: const Text('Confirm Arrival'),
              ),
            ),
          );
        }

        if (widget.role == 'mechanic' && status == 'arrived') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId)
                      .update({'status': 'in_progress'});

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Work marked as started.')),
                    );
                  }
                },
                child: const Text('Start Work'),
              ),
            ),
          );
        }

        if (widget.role == 'mechanic' &&
            (status == 'active' ||
                status == 'accepted' ||
                status == 'arrived' ||
                status == 'in_progress')) {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                  onPressed: () async {
                    final priceController = TextEditingController();
                    final notesController = TextEditingController();
                    final result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (context) {
                        String? errorText;
                        return StatefulBuilder(
                          builder: (context, setState) {
                            return AlertDialog(
                              title: const Text('Mark as Completed'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: priceController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: 'Enter final total price (in USD):',
                                      ),
                                    ),
                                    TextField(
                                      controller: notesController,
                                      minLines: 3,
                                      maxLines: 5,
                                      decoration: const InputDecoration(
                                        labelText: 'Post-Job Notes (required)',
                                      ),
                                    ),
                                    if (errorText != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          errorText!,
                                          style: const TextStyle(color: Colors.red),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final price = double.tryParse(priceController.text);
                                    final notes = notesController.text.trim();
                                    if (price == null || notes.isEmpty) {
                                      setState(() {
                                        errorText = 'Please enter a valid price and notes.';
                                      });
                                    } else {
                                      Navigator.of(context).pop({'price': price, 'notes': notes});
                                    }
                                  },
                                  child: const Text('Submit'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );

                    if (result != null) {
                      final double price = result['price'] as double;
                      final String notes = result['notes'] as String;
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Confirm Final Price'),
                            content: Text(
                              'Confirm final price of \$${price.toStringAsFixed(2)}? This cannot be changed later.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Confirm'),
                              ),
                            ],
                          );
                        },
                      );

                      if (confirmed == true) {
                        await FirebaseFirestore.instance
                            .collection('invoices')
                            .doc(widget.invoiceId)
                            .update({
                              'status': 'completed',
                              'finalPrice': price,
                              'postJobNotes': notes,
                            });
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid != null) {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .update({'completedJobs': FieldValue.increment(1)});
                        }

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Job marked as completed with notes.'),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      }
                    }
                  },
                child: const Text('Mark as Completed'),
              ),
            ),
          );

          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Cancel Request'),
                        content: const Text(
                            'Are you sure you want to cancel this service request?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('No'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Yes'),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed == true) {
                    await FirebaseFirestore.instance
                        .collection('invoices')
                        .doc(widget.invoiceId)
                        .update({
                      'status': 'cancelled',
                      'cancelledBy': 'mechanic',
                    });

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Request cancelled.')),
                      );
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text('Cancel Request'),
              ),
            ),
          );
        }

        if (widget.role == 'customer' && status == 'completed') {
          children.addAll([
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentProcessingPage(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Pay Now'),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  final reviewController = TextEditingController();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('Close Request'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Mark this service request as closed?'),
                            const SizedBox(height: 12),
                            TextField(
                              controller: reviewController,
                              minLines: 3,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Leave a review for your mechanic (optional)',
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      );
                    },
                  );

                  if (confirmed == true) {
                    final Map<String, dynamic> updateData = {
                      'status': 'closed',
                      'closedAt': FieldValue.serverTimestamp(),
                    };
                    final review = reviewController.text.trim();
                    if (review.isNotEmpty) {
                      updateData['customerReview'] = review;
                    }
                    await FirebaseFirestore.instance
                        .collection('invoices')
                        .doc(widget.invoiceId)
                        .update(updateData);

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Request closed. Thank you for using SkipTow.'),
                        ),
                      );
                      Navigator.pop(context);
                    }
                  }
                },
                child: const Text('Close Request'),
              ),
            ),
          ]);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Invoice Details')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

