import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  late final Stream<Map<String, dynamic>?> _invoiceStream;
  StreamSubscription<Map<String, dynamic>?>? _invoiceSub;
  // bool _paymentPageOpened = false; // payment flow disabled
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _etaController = TextEditingController();
  File? _selectedImage;
  final TextEditingController _reportController = TextEditingController();
  File? _reportImage;

  Stream<Map<String, dynamic>?> _buildInvoiceStream() {
    return FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .snapshots()
        .asyncMap((doc) async {
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
      data['customerPhone'] =
          customerData?['phone'] ?? customerData?['phoneNumber'];
      data['customerEmail'] = customerData?['email'];

      if (data['mechanicId'] != null && data['mechanicId'] != 'any') {
        final mechDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(data['mechanicId'])
            .get();
        final mechData = mechDoc.data();
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

        if (widget.role != 'customer') {
          data['mechanicPhone'] =
              mechData?['phone'] ?? mechData?['phoneNumber'];
          data['mechanicEmail'] = mechData?['email'];
        }
      }

      return data;
    });
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate().toLocal();
    return dt.toString().split('.').first;
  }

  Color _paymentColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _scrollChatToBottom() {
    if (_chatScrollController.hasClients) {
      _chatScrollController.jumpTo(
        _chatScrollController.position.maxScrollExtent,
      );
    }
  }

  Future<void> _pickImage() async {
    final XFile? file =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final int bytes = await file.length();
    if (bytes > 5 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image must be under 5 MB.')),
        );
      }
      return;
    }
    setState(() {
      _selectedImage = File(file.path);
    });
  }

  Future<void> _sendChatMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _selectedImage == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    String? imageUrl;
    if (_selectedImage != null) {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_selectedImage!.path.split('/').last}';
      final ref = FirebaseStorage.instance
          .ref()
          .child('invoices/${widget.invoiceId}/chat_images/$fileName');
      await ref.putFile(_selectedImage!);
      imageUrl = await ref.getDownloadURL();
    }

    await FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .collection('messages')
        .add({
      'fromUserId': uid,
      if (text.isNotEmpty) 'message': text,
      if (imageUrl != null) 'imageUrl': imageUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
    setState(() {
      _selectedImage = null;
    });
    _scrollChatToBottom();
  }

  Future<void> _pickReportImage() async {
    final XFile? file =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() {
      _reportImage = File(file.path);
    });
  }

  Future<void> _showReportDialog(Map<String, dynamic> data) async {
    String? errorText;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Report an Issue'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _reportController,
                      minLines: 3,
                      maxLines: 5,
                      decoration:
                          const InputDecoration(labelText: 'Describe the issue'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.photo),
                          onPressed: () async {
                            await _pickReportImage();
                            setState(() {});
                          },
                        ),
                        if (_reportImage != null)
                          SizedBox(
                            height: 40,
                            width: 40,
                            child: Image.file(_reportImage!),
                          ),
                      ],
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
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (_reportController.text.trim().isEmpty) {
                      setState(() {
                        errorText = 'Please enter a description.';
                      });
                    } else {
                      Navigator.of(context).pop(true);
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

    if (result == true) {
      final doc = FirebaseFirestore.instance.collection('reports').doc();
      String? imageUrl;
      if (_reportImage != null) {
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${_reportImage!.path.split('/').last}';
        final ref = FirebaseStorage.instance
            .ref()
            .child('reports/${doc.id}/$fileName');
        await ref.putFile(_reportImage!);
        imageUrl = await ref.getDownloadURL();
      }
      await doc.set({
        'invoiceId': widget.invoiceId,
        'mechanicId': data['mechanicId'],
        'customerId': data['customerId'],
        'reportText': _reportController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'open',
        if (imageUrl != null) 'imageUrl': imageUrl,
      });
      _reportController.clear();
      setState(() {
        _reportImage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted.')),
        );
      }
    }
  }

  Widget _buildChatSection(Map<String, dynamic> data) {
    if (widget.role == 'admin') {
      return const SizedBox.shrink();
    }

    final mechanicId = data['mechanicId'];
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();

    return SizedBox(
      height: 250,
      child: Column(
        children: [
          const Divider(),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Chat Thread',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollChatToBottom());
                return ListView.builder(
                  controller: _chatScrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final msg = docs[index].data();
                    final from = msg['fromUserId'];
                    final bool isMechanic = from == mechanicId;
                    final alignment =
                        isMechanic ? Alignment.centerLeft : Alignment.centerRight;
                    final color =
                        isMechanic ? Colors.grey[300] : Colors.blue[100];
                    final String? text = msg['message'] as String?;
                    final String? imageUrl = msg['imageUrl'] as String?;
                    return Align(
                      alignment: alignment,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (text != null && text.isNotEmpty) Text(text),
                            if (imageUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Image.network(
                                  imageUrl,
                                  width: 150,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.broken_image),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.photo),
                    onPressed: _pickImage,
                  ),
                  if (_selectedImage != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        height: 40,
                        width: 40,
                        child: Image.file(_selectedImage!),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendChatMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _invoiceStream = _buildInvoiceStream();
    _invoiceSub = _invoiceStream.listen((data) {
      // No automatic payment processing in the confirmation flow
    });
  }

  @override
  void dispose() {
    _invoiceSub?.cancel();
    _messageController.dispose();
    _chatScrollController.dispose();
    _etaController.dispose();
    _reportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _invoiceStream,
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
        final invoiceStatus = data['invoiceStatus'] ?? status;
        final customerConfirmed = data['customerConfirmed'] == true;
        final finalPrice = data['finalPrice'];
        final paymentStatus = data['paymentStatus'] ?? 'pending';
        final Timestamp? createdAtTs = data['createdAt'];
        _etaController.text = data['etaMinutes'] != null ? data['etaMinutes'].toString() : '';

        final children = <Widget>[];
        final bool isOverdue =
            widget.role == 'customer' &&
                paymentStatus == 'pending' &&
                createdAtTs != null &&
                DateTime.now().difference(createdAtTs.toDate()).inDays > 7;
        if (isOverdue) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '⚠️ Your payment is overdue. Please complete payment immediately.',
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          );
        }
        final invoiceNum = data['invoiceNumber'] ?? widget.invoiceId;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Service Request #: $invoiceNum',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
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
          Row(
            children: [
              Text('Mechanic: ${data['mechanicUsername'] ?? 'Unknown'}'),
              const SizedBox(width: 8),
              Icon(
                data['mechanicAccepted'] == true ? Icons.check : Icons.close,
                color: data['mechanicAccepted'] == true ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
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
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _paymentColor(paymentStatus),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Payment: $paymentStatus',
                style: const TextStyle(color: Colors.white),
              ),
            ),
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
          if (data['etaMinutes'] != null)
            Text('ETA: ${data['etaMinutes']} minutes'),
          if (finalPrice != null && widget.role != 'customer')
            Text('Final Price: \$${finalPrice.toString()}'),
          if (widget.role == 'admin' && data['platformFee'] != null)
            Text(
              "Platform Fee: \$${(data['platformFee'] as num).toStringAsFixed(2)}",
            ),
          if (widget.role == 'mechanic')
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('invoices')
                  .doc(widget.invoiceId)
                  .snapshots(),
              builder: (context, paySnapshot) {
                if (!paySnapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final pStatus =
                    paySnapshot.data!.data()?['paymentStatus'] ?? 'pending';
                final bool isPaid = pStatus == 'paid';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    isPaid ? 'Payment Completed' : 'Payment Pending',
                    style: TextStyle(
                      color: isPaid ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          if (widget.role == 'mechanic')
            (data['customerReview'] ?? '').toString().isNotEmpty
                ? Text('Customer Review:\n${data['customerReview']}')
                : const Text('No customer review provided.'),
        ]);

        if (widget.role == 'mechanic' && (status == 'accepted' || status == 'arrived' || status == 'in_progress')) {
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _etaController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Estimated Arrival Time (in minutes)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final eta = int.tryParse(_etaController.text);
                      if (eta != null) {
                        await FirebaseFirestore.instance.collection('invoices').doc(widget.invoiceId).update({'etaMinutes': eta});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ETA updated.')));
                        }
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid ETA.')));
                        }
                      }
                    },
                    child: const Text('Update ETA'),
                  ),
                ],
              ),
            ),
          );
        }
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final List<dynamic>? candidates = data['mechanicCandidates'] as List<dynamic>?;
        final List<dynamic>? responded = data['mechanicResponded'] as List<dynamic>?;
        final bool canAccept = widget.role == 'mechanic' &&
            data['mechanicId'] == null &&
            currentUid != null &&
            (candidates?.contains(currentUid) ?? false) &&
            !(responded?.contains(currentUid) ?? false);

        if (canAccept) {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  final invoiceRef = FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId);
                  try {
                    await FirebaseFirestore.instance.runTransaction((tx) async {
                      final snap = await tx.get(invoiceRef);
                      if (snap.data()?['mechanicId'] != null) {
                        return;
                      }
                      final mechDoc = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUid)
                          .get();
                      final username = mechDoc.data()?['username'] ?? 'Mechanic';
                      tx.update(invoiceRef, {
                        'mechanicId': currentUid,
                        'mechanicUsername': username,
                        'mechanicAccepted': true,
                        'status': 'accepted',
                      });
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Request accepted.')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Unable to accept. Another mechanic may have claimed it.')),
                      );
                    }
                  }
                },
                child: const Text('Accept Request'),
              ),
            ),
          );
        }

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
                        final double fee =
                            double.parse((price * 0.15).toStringAsFixed(2));
                        await FirebaseFirestore.instance
                            .collection('invoices')
                            .doc(widget.invoiceId)
                            .update({
                              'status': 'completed',
                              'invoiceStatus': 'completed',
                              'finalPrice': price,
                              'postJobNotes': notes,
                              'platformFee': fee,
                              'completedAt': FieldValue.serverTimestamp(),
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


        if (widget.role == 'customer' &&
            invoiceStatus == 'completed' &&
            !customerConfirmed) {
          children.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(8),
              color: Colors.yellow[100],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Job Completed – Please Confirm Final Price: '
                    '\$${finalPrice != null ? (finalPrice as num).toDouble().toStringAsFixed(2) : '0.00'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) {
                              return AlertDialog(
                                title: const Text('Confirm Price'),
                                content: Text(
                                  'Accept final price of \$${finalPrice != null ? (finalPrice as num).toDouble().toStringAsFixed(2) : '0.00'}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Accept'),
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
                              'invoiceStatus': 'closed',
                              'status': 'closed',
                              'customerConfirmed': true,
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Price accepted. Invoice closed.')),
                              );
                              setState(() {});
                            }
                          }
                        },
                        child: const Text('Accept Price & Close'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Dispute feature coming soon.')),
                          );
                        },
                        child: const Text('Dispute Price'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }        if (widget.role == 'customer' || widget.role == 'mechanic') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () => _showReportDialog(data),
                child: const Text('Report an Issue'),
              ),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Invoice Details')),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
              _buildChatSection(data),
            ],
          ),
        );
      },
    );
  }
}

