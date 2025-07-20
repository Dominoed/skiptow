import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../services/error_logger.dart';
import 'messages_page.dart';

/// Page that allows a customer to track an assigned mechanic in real time.
class CustomerMechanicTrackingPage extends StatefulWidget {
  final String customerId;
  final String mechanicId;
  final String invoiceId;
  const CustomerMechanicTrackingPage({
    super.key,
    required this.customerId,
    required this.mechanicId,
    required this.invoiceId,
  });

  @override
  State<CustomerMechanicTrackingPage> createState() =>
      _CustomerMechanicTrackingPageState();
}

class _CustomerMechanicTrackingPageState
    extends State<CustomerMechanicTrackingPage> {
  GoogleMapController? _mapController;
  Marker? _mechanicMarker;
  LatLng? _mechanicLatLng;
  Position? _customerPos;
  int? _etaCountdown;
  int? _lastEtaMinutes;
  Timer? _etaTimer;
  String? _distanceText;
  String _mechanicName = '';
  String? _mechanicPhone;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _locationSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _invoiceSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _customerPos = await Geolocator.getCurrentPosition();
    } catch (e) {
      logError('Tracking get location error: $e');
    }
    _listenMechanicLocation();
    _listenInvoice();
  }

  void _listenMechanicLocation() {
    _locationSub?.cancel();
    _locationSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.mechanicId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final loc = data['location'];
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      _mechanicName = data['username'] ?? data['displayName'] ?? '';
      _mechanicPhone = data['phone'] ?? data['phoneNumber'];
      if (lat != null && lng != null) {
        _mechanicLatLng = LatLng(lat, lng);
        _mechanicMarker = Marker(
          markerId: const MarkerId('mechanic'),
          position: _mechanicLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          anchor: const Offset(0.5, 0.5),
        );
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_mechanicLatLng!),
          );
        }
        if (_customerPos != null) {
          final meters = Geolocator.distanceBetween(
            _customerPos!.latitude,
            _customerPos!.longitude,
            lat,
            lng,
          );
          _distanceText = '${(meters / 1609.34).toStringAsFixed(1)} mi away';
        }
      }
      setState(() {});
    }, onError: (e) {
      logError('Tracking mechanic location error: $e');
    });
  }

  void _listenInvoice() {
    _invoiceSub?.cancel();
    _invoiceSub = FirebaseFirestore.instance
        .collection('invoices')
        .doc(widget.invoiceId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (data == null) return;
      final eta = data['etaMinutes'];
      final status = (data['invoiceStatus'] ?? data['status'] ?? '').toString();
      if (eta != null) {
        final etaInt = (eta as num).toInt();
        if (_lastEtaMinutes != etaInt) {
          _startEtaCountdown(etaInt);
        }
      } else {
        _stopEtaCountdown();
      }
      if (status == 'completed' || status == 'closed' || status == 'cancelled') {
        if (mounted) Navigator.pop(context);
      } else {
        setState(() {});
      }
    }, onError: (e) {
      logError('Tracking invoice listen error: $e');
    });
  }

  void _startEtaCountdown(int minutes) {
    _etaTimer?.cancel();
    _lastEtaMinutes = minutes;
    _etaCountdown = minutes;
    _etaTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) return;
      if (_etaCountdown != null && _etaCountdown! > 0) {
        setState(() {
          _etaCountdown = _etaCountdown! - 1;
        });
      } else {
        timer.cancel();
        setState(() {});
      }
    });
    setState(() {});
  }

  void _stopEtaCountdown() {
    _etaTimer?.cancel();
    _etaTimer = null;
    _etaCountdown = null;
    _lastEtaMinutes = null;
    setState(() {});
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _invoiceSub?.cancel();
    _etaTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesPage(
          currentUserId: widget.customerId,
          otherUserId: widget.mechanicId,
        ),
      ),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{};
    if (_mechanicMarker != null) markers.add(_mechanicMarker!);

    return Scaffold(
      appBar: AppBar(title: const Text('Mechanic Tracking')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openMessages,
        label: const Text('Message Mechanic'),
        icon: const Icon(Icons.chat),
      ),
      body: _mechanicLatLng == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _mechanicLatLng!,
                    zoom: 14,
                  ),
                  markers: markers,
                  myLocationEnabled: true,
                  onMapCreated: (c) => _mapController = c,
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_etaCountdown != null && _etaCountdown! > 0)
                        _infoBox('Mechanic Arriving In: $_etaCountdown minutes'),
                      if (_etaCountdown != null && _etaCountdown! <= 0)
                        _infoBox('Mechanic should have arrived.'),
                      if (_distanceText != null) _infoBox(_distanceText!),
                      if (_mechanicName.isNotEmpty)
                        _infoBox('Mechanic: $_mechanicName'),
                      if (_mechanicPhone != null && _mechanicPhone!.isNotEmpty)
                        _infoBox('Phone: $_mechanicPhone'),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
