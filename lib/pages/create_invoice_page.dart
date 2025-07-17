import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class CreateInvoicePage extends StatefulWidget {
  final String customerId;
  final String mechanicId;
  final String mechanicUsername;
  final double distance;

  const CreateInvoicePage({
    super.key,
    required this.customerId,
    required this.mechanicId,
    required this.mechanicUsername,
    required this.distance,
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

  bool isSubmitting = false;
  bool get isAnyTech => widget.mechanicId == 'any';

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
    if (!isFormValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    setState(() {
      isSubmitting = true;
    });

    try {
      final position = await Geolocator.getCurrentPosition();
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
        'customerPhone': phoneController.text.trim(),
        'customerEmail': userEmail,
        'timestamp': DateTime.now(),
        'status': 'active',
      });

      carYearController.clear();
      carMakeController.clear();
      carModelController.clear();
      descriptionController.clear();
      phoneController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice submitted')),
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
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
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isFormValid && !isSubmitting ? _submitInvoice : null,
              child: const Text('Submit Invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
