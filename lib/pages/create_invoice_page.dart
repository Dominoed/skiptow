import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:skiptow/services/error_logger.dart';

class CreateInvoicePage extends StatefulWidget {
  final String customerId;
  final String mechanicId;
  final String mechanicUsername;
  final double distance;
  final String? defaultDescription;

  const CreateInvoicePage({
    super.key,
    required this.customerId,
    required this.mechanicId,
    required this.mechanicUsername,
    required this.distance,
    this.defaultDescription,
  });

  @override
  State<CreateInvoicePage> createState() => _CreateInvoicePageState();
}

class _CreateInvoicePageState extends State<CreateInvoicePage> {
  final TextEditingController carYearController = TextEditingController();
  final TextEditingController carMakeController = TextEditingController();
  final TextEditingController carModelController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  bool isSubmitting = false;
  bool hasActiveRequest = false;
  bool get isAnyTech => widget.mechanicId == 'any';

  @override
  void initState() {
    super.initState();
    if (widget.defaultDescription != null) {
      descriptionController.text = widget.defaultDescription!;
    }
    _checkActiveRequest();
  }

  Future<void> _checkActiveRequest() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.customerId;
    final snapshot = await FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (mounted) {
      setState(() {
        hasActiveRequest = snapshot.docs.isNotEmpty;
      });
      if (hasActiveRequest) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You already have an active service request.')),
        );
      }
    }
  }

  bool get isFormValid =>
      carYearController.text.isNotEmpty &&
      carMakeController.text.isNotEmpty &&
      carModelController.text.isNotEmpty &&
      descriptionController.text.isNotEmpty;

  Future<bool> _handleLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied.')),
        );
      }
      return false;
    }

    return true;
  }

  Future<void> _submitInvoice() async {
    if (isSubmitting) return;
    setState(() {
      isSubmitting = true;
    });

    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      setState(() {
        isSubmitting = false;
      });
      return;
    }

    // Check for an existing active invoice for this customer before proceeding
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.customerId;
    final activeSnapshot = await FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    if (activeSnapshot.docs.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You already have an active service request.')),
        );
      }
      setState(() {
        isSubmitting = false;
      });
      return;
    }

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      setState(() {
        isSubmitting = false;
      });
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final position = await Geolocator.getCurrentPosition();

      // Re-check for any active invoice before submitting to avoid duplicates
      final uidCheck = FirebaseAuth.instance.currentUser?.uid ?? widget.customerId;
      final dupSnapshot = await FirebaseFirestore.instance
          .collection('invoices')
          .where('customerId', isEqualTo: uidCheck)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (dupSnapshot.docs.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop(); // hide loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You already have an active request.')),
          );
        }
        setState(() {
          isSubmitting = false;
        });
        return;
      }

      final userEmail = FirebaseAuth.instance.currentUser?.email ?? '';

      await FirebaseFirestore.instance.collection('invoices').add({
        'mechanicId': widget.mechanicId,
        'customerId': widget.customerId,
        'mechanicUsername': widget.mechanicUsername,
        if (!isAnyTech) 'distance': widget.distance,
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
        },
        'carInfo': {
          'year': carYearController.text,
          'make': carMakeController.text,
          'model': carModelController.text,
        },
        'description': descriptionController.text,
        if (notesController.text.trim().isNotEmpty)
          'notes': notesController.text.trim(),
        'customerPhone': phoneController.text.trim(),
        'customerEmail': userEmail,
        'createdAt': FieldValue.serverTimestamp(),
        'timestamp': DateTime.now(),
        'status': 'active',
      });

      carYearController.clear();
      carMakeController.clear();
      carModelController.clear();
      descriptionController.clear();
      phoneController.clear();
      notesController.clear();

      if (mounted) {
        Navigator.of(context).pop(); // hide loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice submitted')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      logError('Submit invoice error: $e');
      if (mounted) {
        Navigator.of(context).pop(); // hide loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('An error occurred. Please try again.')),
        );
      }
      debugPrint('$e');
    } finally {
      if (mounted) {
        setState(() {
          isSubmitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    carYearController.dispose();
    carMakeController.dispose();
    carModelController.dispose();
    descriptionController.dispose();
    phoneController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Invoice')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mechanic: ${widget.mechanicUsername}'),
            if (!isAnyTech)
              Text('Distance: ${widget.distance.toStringAsFixed(1)} mi'),
            const SizedBox(height: 16),
            TextField(
              controller: carYearController,
              decoration: const InputDecoration(labelText: 'Car Year'),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: carMakeController,
              decoration: const InputDecoration(labelText: 'Car Make'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: carModelController,
              decoration: const InputDecoration(labelText: 'Car Model'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(labelText: 'Problem Description'),
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: 'Additional Notes (optional)'),
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: !isFormValid || isSubmitting
                  ? null
                  : hasActiveRequest
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'You already have an active service request.')),
                          );
                        }
                      : _submitInvoice,
              child: const Text('Submit Invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
