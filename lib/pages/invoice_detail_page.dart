import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/pdf_downloader.dart';
import '../services/invoice_pdf.dart';
import 'payment_processing_page.dart';
import 'image_viewer_page.dart';
import 'customer_mechanic_tracking_page.dart';

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
  final TextEditingController _feedbackController = TextEditingController();
  final TextEditingController _paymentIssueController = TextEditingController();

  Widget _buildTimeline(Map<String, dynamic> data) {
    final Timestamp? createdAt = data['createdAt'] as Timestamp?;
    final Timestamp? acceptedAt =
        data['acceptedAt'] as Timestamp? ??
        data['mechanicAcceptedAt'] as Timestamp? ??
        data['mechanicAcceptedTimestamp'] as Timestamp?;
    final Timestamp? completedAt =
        data['completedAt'] as Timestamp? ??
        data['jobCompletedTimestamp'] as Timestamp?;
    final Timestamp? closedAt = data['closedAt'] as Timestamp?;
    final bool mechanicAccepted = data['mechanicAccepted'] == true;
    final bool etaProvided = data['etaMinutes'] != null;
    final bool mechanicCompleted = completedAt != null;
    final bool customerConfirmed = data['customerConfirmed'] == true;
    final bool paymentCompleted =
        (data['paymentStatus'] ?? '') == 'paid' ||
            (data['paymentStatus'] ?? '') == 'paid_in_person';
    final bool invoiceClosed = closedAt != null ||
        (data['invoiceStatus'] ?? data['status']) == 'closed';

    int currentStep = 0;
    if (invoiceClosed) {
      currentStep = 6;
    } else if (paymentCompleted) {
      currentStep = 5;
    } else if (customerConfirmed) {
      currentStep = 4;
    } else if (mechanicCompleted) {
      currentStep = 3;
    } else if (etaProvided) {
      currentStep = 2;
    } else if (mechanicAccepted) {
      currentStep = 1;
    }

    Step buildStep(String title, {String subtitle = '', required int index}) {
      return Step(
        title: Text(title),
        subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
        content: const SizedBox.shrink(),
        isActive: currentStep >= index,
        state: currentStep > index
            ? StepState.complete
            : currentStep == index
                ? StepState.editing
                : StepState.indexed,
      );
    }

    final steps = [
      buildStep('Request Submitted',
          subtitle: formatDate(createdAt), index: 0),
      buildStep('Mechanic Accepted',
          subtitle: formatDate(acceptedAt), index: 1),
      buildStep('ETA Provided',
          subtitle:
              data['etaMinutes'] != null ? '${data['etaMinutes']} min' : '',
          index: 2),
      buildStep('Mechanic Marked Completed',
          subtitle: formatDate(completedAt), index: 3),
      buildStep('Customer Confirmed Price',
          subtitle: customerConfirmed ? formatDate(closedAt) : '', index: 4),
      buildStep('Payment Completed',
          subtitle: paymentCompleted ? formatDate(closedAt) : '', index: 5),
      buildStep('Invoice Closed',
          subtitle: formatDate(closedAt), index: 6),
    ];

    return Stepper(
      currentStep: currentStep,
      type: StepperType.vertical,
      controlsBuilder: (_, __) => const SizedBox.shrink(),
      steps: steps,
    );
  }

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
        data['mechanicIsActive'] = mechData?['isActive'] ?? false;

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

      final tipSnap = await doc.reference
          .collection('tipIntent')
          .doc('intent')
          .get();
      if (tipSnap.exists) {
        data['tipIntent'] = tipSnap.data();
      }

      return data;
    });
  }


  Color _paymentColor(String status) {
    switch (status) {
      case 'paid':
      case 'paid_in_person':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'unpaid':
        return Colors.orange;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _invoiceStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
      case 'accepted':
        return Colors.blue;
      case 'arrived':
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.purple;
      case 'closed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
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

  Future<void> _openNavigation(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _downloadInvoicePdf(Map<String, dynamic> data) async {
    final bytes = await generateInvoicePdf(data, widget.invoiceId);
    final num = data['invoiceNumber'] ?? widget.invoiceId;
    await downloadPdf(bytes, fileName: 'invoice_\$num.pdf');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice PDF downloaded')),
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

  void _openImageViewer(List<String> urls, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          imageUrls: urls,
          initialIndex: index,
        ),
        fullscreenDialog: true,
      ),
    );
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
              title: const Text('Report Issue with This Service'),
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await doc.set({
        'reportText': _reportController.text.trim(),
        'reportedBy': uid,
        'role': widget.role,
        'relatedInvoiceId': widget.invoiceId,
        'type': 'service_issue',
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
        if (imageUrl != null) 'imageUrl': imageUrl,
        // legacy fields for backward compatibility
        'invoiceId': widget.invoiceId,
        'mechanicId': data['mechanicId'],
        'customerId': data['customerId'],
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

  Future<void> _showPaymentIssueDialog(Map<String, dynamic> data) async {
    String? errorText;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Report Payment Issue'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _paymentIssueController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Describe the issue',
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (_paymentIssueController.text.trim().isEmpty) {
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
      await doc.set({
        'type': 'payment_issue',
        'invoiceId': widget.invoiceId,
        'customerId': data['customerId'],
        'reportText': _paymentIssueController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'open',
      });
      _paymentIssueController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment issue reported.')),
        );
      }
    }
  }

  Future<void> _showTipDialog() async {
    final amount = await showDialog<double>(
      context: context,
      builder: (context) {
        bool custom = false;
        final TextEditingController controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Tip Your Mechanic?'),
              content: custom
                  ? TextField(
                      controller: controller,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Enter amount'),
                    )
                  : Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, 5.0),
                          child: const Text('\$5'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, 10.0),
                          child: const Text('\$10'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, 15.0),
                          child: const Text('\$15'),
                        ),
                        ElevatedButton(
                          onPressed: () => setState(() => custom = true),
                          child: const Text('Custom'),
                        ),
                      ],
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('No Thanks'),
                ),
                if (custom)
                  TextButton(
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null && val > 0) {
                        Navigator.pop(context, val);
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

    if (amount != null) {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(widget.invoiceId)
          .collection('tipIntent')
          .doc('intent')
          .set({'amount': amount, 'status': 'pending'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment will be processed in-app soon.')),
        );
      }
    }
  }

  Future<void> _showFeedbackDialog(String invoiceId) async {
    int rating = 0;
    _feedbackController.clear();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('How was your service?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                          color: Colors.orange,
                        ),
                        onPressed: () => setState(() => rating = index + 1),
                      );
                    }),
                  ),
                  TextField(
                    controller: _feedbackController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Additional Feedback (optional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Skip'),
                ),
                TextButton(
                  onPressed: rating == 0
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(invoiceId)
          .collection('feedback')
          .add({
        'rating': rating,
        if (_feedbackController.text.trim().isNotEmpty)
          'feedbackText': _feedbackController.text.trim(),
        'submittedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Widget _buildChatSection(Map<String, dynamic> data) {
    if (widget.role == 'admin') {
      return const SizedBox.shrink();
    }

    final mechanicId = data['mechanicId'];
    final String invoiceState =
        (data['invoiceStatus'] ?? data['status'] ?? 'active').toString();
    final bool chatDisabled =
        invoiceState == 'closed' || invoiceState == 'cancelled';
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

                final imageUrls = <String>[];
                final Map<String, int> imageIndexMap = {};
                for (final doc in docs) {
                  final url = doc.data()['imageUrl'] as String?;
                  if (url != null) {
                    imageIndexMap[doc.id] = imageUrls.length;
                    imageUrls.add(url);
                  }
                }

                return ListView.builder(
                  controller: _chatScrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final msg = doc.data();
                    final from = msg['fromUserId'];
                    final bool isMechanic = from == mechanicId;
                    final alignment =
                        isMechanic ? Alignment.centerLeft : Alignment.centerRight;
                    final color =
                        isMechanic ? Colors.grey[300] : Colors.blue[100];
                    final String? text = msg['message'] as String?;
                    final String? imageUrl = msg['imageUrl'] as String?;
                    final int? imageIndex = imageIndexMap[doc.id];

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
                                child: GestureDetector(
                                  onTap: imageIndex != null
                                      ? () => _openImageViewer(imageUrls, imageIndex)
                                      : null,
                                  child: Image.network(
                                    imageUrl,
                                    width: 150,
                                    errorBuilder: (context, error, stackTrace) =>
                                        const Icon(Icons.broken_image),
                                  ),
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
          if (!chatDisabled)
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
    _paymentIssueController.dispose();
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

        // Mechanics should not view closed or cancelled invoices
        if (widget.role == 'mechanic' &&
            (invoiceStatus == 'closed' || invoiceStatus == 'cancelled')) {
          return Scaffold(
            appBar: AppBar(title: const Text('Invoice Details')),
            body: const Center(
              child: Text('This job has been closed or cancelled.'),
            ),
          );
        }
        final customerConfirmed = data['customerConfirmed'] == true;
        final finalPrice = data['finalPrice'];
        final estimatedPrice = finalPrice == null
            ? (data['estimatedPrice'] ?? data['quotedPrice'])
            : null;
        final List<String> attachments =
            (data['photoUrls'] as List?)?.cast<String>() ??
            (data['photos'] as List?)?.cast<String>() ??
            (data['images'] as List?)?.cast<String>() ??
            [];
        final paymentStatus = data['paymentStatus'] ?? 'pending';
        final Timestamp? createdAtTs = data['createdAt'];
        final Timestamp? acceptedAtTs =
            data['mechanicAcceptedAt'] ?? data['acceptedAt'];
        final Timestamp? closedAtTs = data['closedAt'];
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
        children.add(
          Row(
            children: [
              const Text('Status: '),
              Chip(
                label: Text(
                  invoiceStatus,
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: _invoiceStatusColor(invoiceStatus),
              ),
              const SizedBox(width: 8),
              Text('Created: ${formatDate(createdAtTs)}'),
              if (acceptedAtTs != null) ...[
                const SizedBox(width: 8),
                Text('Accepted: ${formatDate(acceptedAtTs)}'),
              ],
              if (closedAtTs != null) ...[
                const SizedBox(width: 8),
                Text('Closed: ${formatDate(closedAtTs)}'),
              ],
            ],
          ),
        );
        children.add(_buildTimeline(data));
        if (data['adminOverride'] == true)
          children.add(
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Chip(
                label: Text(
                  invoiceStatus == 'cancelled'
                      ? 'Force Cancelled by Admin'
                      : 'Force Closed by Admin',
                  style: const TextStyle(color: Colors.white),
                ),
                backgroundColor: invoiceStatus == 'cancelled'
                    ? Colors.red
                    : Colors.orange,
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
          final bool mechActive = getBool(data, 'mechanicIsActive');
          String statusText =
              'Mechanic Status: ${mechActive ? 'Active' : 'Inactive'}';
          Color? statusColor = mechActive ? Colors.green : Colors.red;
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
          if (attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Attachments:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: attachments
                        .map(
                          (url) => SizedBox(
                            height: 80,
                            width: 80,
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (c, e, s) =>
                                  const Icon(Icons.broken_image),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          if (finalPrice != null)
            Text('Final Total: \$${(finalPrice as num).toStringAsFixed(2)}')
          else if (estimatedPrice != null)
            Text('Estimated Total: \$${(estimatedPrice as num).toStringAsFixed(2)}')
          else
            const Text('Estimated Total: Pending'),
          if (widget.role == 'mechanic' && data['tipIntent'] != null)
            Text(
              "Intended Tip: \$${(data['tipIntent']['amount'] as num).toStringAsFixed(2)}",
            ),
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
          if (location != null &&
              location['lat'] != null &&
              location['lng'] != null)
            SizedBox(
              height: 200,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        (location['lat'] as num).toDouble(),
                        (location['lng'] as num).toDouble(),
                      ),
                      zoom: 14,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('service'),
                        position: LatLng(
                          (location['lat'] as num).toDouble(),
                          (location['lng'] as num).toDouble(),
                        ),
                      ),
                    },
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: ElevatedButton.icon(
                      onPressed: () => _openNavigation(
                        (location['lat'] as num).toDouble(),
                        (location['lng'] as num).toDouble(),
                      ),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Navigate'),
                    ),
                  ),
                ],
              ),
            ),
          if (data['distance'] != null)
            Text('Distance: ${data['distance'].toStringAsFixed(1)} mi'),
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
                if (paySnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!paySnapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final pStatus =
                    paySnapshot.data!.data()?['paymentStatus'] ?? 'pending';
                final bool isPaid =
                    pStatus == 'paid' || pStatus == 'paid_in_person';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Text(
                    isPaid
                        ? 'Payment Completed'
                        : (pStatus == 'unpaid'
                            ? 'Payment Unrecorded'
                            : 'Payment Pending'),
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
          if (widget.role == 'customer' || widget.role == 'admin')
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('invoices')
                  .doc(widget.invoiceId)
                  .collection('mechanicFeedback')
                  .get(),
              builder: (context, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const SizedBox.shrink();
                }
                final fb = snap.data!.docs.first.data();
                final rating = fb['rating'];
                final text = fb['feedbackText'];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mechanic Rating: ${rating ?? ''}/5'),
                    if (text != null && text.toString().isNotEmpty)
                      Text('Mechanic Feedback:\n$text'),
                  ],
                );
              },
            ),
          if (invoiceStatus == 'closed')
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _downloadInvoicePdf(data),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Download Invoice PDF'),
              ),
            ),
        ]);

        if (widget.role == 'mechanic' &&
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled' &&
            (status == 'accepted' || status == 'arrived' || status == 'in_progress')) {
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
            !(responded?.contains(currentUid) ?? false) &&
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled';

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
                        'mechanicAcceptedAt': FieldValue.serverTimestamp(),
                        'acceptedAt': FieldValue.serverTimestamp(),
                        'status': 'accepted',
                        'invoiceStatus': 'accepted',
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

        if (widget.role == 'mechanic' &&
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled' &&
            status == 'accepted') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId)
                      .update({'status': 'arrived', 'invoiceStatus': 'arrived'});

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

        if (widget.role == 'mechanic' &&
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled' &&
            status == 'arrived') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: () async {
                  await FirebaseFirestore.instance
                      .collection('invoices')
                      .doc(widget.invoiceId)
                      .update({'status': 'in_progress', 'invoiceStatus': 'in_progress'});

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
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled' &&
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
                            double.parse((price * 0.10).toStringAsFixed(2));
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
                      'invoiceStatus': 'cancelled',
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
                            final docRef = FirebaseFirestore.instance
                                .collection('invoices')
                                .doc(widget.invoiceId);
                            final existing = await docRef.get();
                            final updateData = {
                              'invoiceStatus': 'closed',
                              'status': 'closed',
                              'customerConfirmed': true,
                            };
                            if (existing.data()?['closedAt'] == null) {
                              updateData['closedAt'] = FieldValue.serverTimestamp();
                            }
                            await docRef.update(updateData);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Price accepted. Invoice closed.')),
                              );
                              await _showTipDialog();
                              await _showFeedbackDialog(widget.invoiceId);
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
        }
        if (widget.role == 'customer' &&
            data['mechanicId'] != null &&
            invoiceStatus != 'closed' &&
            invoiceStatus != 'cancelled') {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerMechanicTrackingPage(
                        customerId: data['customerId'],
                        mechanicId: data['mechanicId'],
                        invoiceId: widget.invoiceId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.directions_car),
                label: const Text('Track Mechanic'),
              ),
            ),
          );
      }
      if (widget.role == 'customer' &&
          (paymentStatus == 'pending' || paymentStatus == 'overdue') &&
          invoiceStatus != 'closed' &&
          invoiceStatus != 'cancelled') {
        children.add(
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentProcessingPage(invoiceId: widget.invoiceId),
                  ),
                );
              },
              child: const Text('💳 Pay Now'),
            ),
          ),
        );
      }
      if (widget.role == 'customer' || widget.role == 'mechanic') {
        children.add(
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
                onPressed: () => _showReportDialog(data),
                child: const Text('Report Issue with This Service'),
              ),
            ),
          );
        }

        if (widget.role == 'customer' && customerConfirmed) {
          children.add(
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _showPaymentIssueDialog(data),
                child: const Text('Report Payment Issue'),
              ),
            ),
          );
        }

        if (widget.role == 'customer' && invoiceStatus == 'closed') {
          children.add(
            FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('invoices')
                  .doc(widget.invoiceId)
                  .collection('feedback')
                  .get(),
              builder: (context, fbSnap) {
                if (!fbSnap.hasData) {
                  return const SizedBox.shrink();
                }
                final hasFb = fbSnap.data!.docs.isNotEmpty;
                if (!hasFb) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _showFeedbackDialog(widget.invoiceId),
                      child: const Text('Leave Feedback'),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
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

