import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'invoices_page.dart';
import 'messages_page.dart';

BitmapDescriptor? wrenchIcon;

class MechanicDashboard extends StatefulWidget {
  final String userId;
  const MechanicDashboard({super.key, required this.userId});

  @override
  State<MechanicDashboard> createState() => _MechanicDashboardState();
}

class _MechanicDashboardState extends State<MechanicDashboard> {
  Timer? backgroundTimer;
  StreamSubscription<Position>? positionStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? invoiceSubscription;
  bool _initialInvoiceLoad = true;
  bool isActive = false;
  double radiusMiles = 5;
  String status = 'Inactive';
  Position? currentPosition;
  GoogleMapController? mapController;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadWrenchIcon();
    _loadStatus();
    _handleLocationPermission();
    _listenForInvoices();
  }

  Future<void> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location permissions are permanently denied.')),
      );
      return;
    }
  }

  Future<void> _loadWrenchIcon() async {
    wrenchIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/wrench.png',
    );
    setState(() {});
  }

  Future<void> _loadStatus() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    final data = doc.data();
    if (data != null) {
      setState(() {
        isActive = data['isActive'] ?? false;
        radiusMiles = (data['radiusMiles'] ?? 5).toDouble();
        if (data.containsKey('location')) {
          currentPosition = Position(
            latitude: data['location']['lat'],
            longitude: data['location']['lng'],
            timestamp: DateTime.now(),
            accuracy: 1,
            altitude: 1,
            altitudeAccuracy: 1,
            heading: 1,
            headingAccuracy: 1,
            speed: 1,
            speedAccuracy: 1,
          );
        }
        status = isActive ? 'Active' : 'Inactive';
      });

      // ✅ Start live updates if mechanic is active
      if (isActive) {
        _startPositionUpdates();
      }
    }
  }

  Future<void> _toggleStatus() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    if (!isActive) {
      currentPosition = await Geolocator.getCurrentPosition();
    }

    final data = {
      'isActive': !isActive,
      'radiusMiles': radiusMiles,
      'location': currentPosition != null
          ? {'lat': currentPosition!.latitude, 'lng': currentPosition!.longitude}
          : FieldValue.delete(),
    };

    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update(data);
    await FirebaseFirestore.instance.collection('mechanics').doc(widget.userId).update(data);

    setState(() {
      isActive = !isActive;
      status = isActive ? 'Active' : 'Inactive';
    });

    if (isActive) {
      _startPositionUpdates();
    } else {
      positionStream?.cancel();
      backgroundTimer?.cancel();
    }
  }

  void _listenForInvoices() {
    invoiceSubscription?.cancel();
    invoiceSubscription = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      if (_initialInvoiceLoad) {
        _initialInvoiceLoad = false;
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('New service request received')),
            );
          }
        }
      }
    });
  }

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

  Set<Circle> _buildRadiusCircles() {
    if (currentPosition == null || !isActive) return {};
    final LatLng center = LatLng(currentPosition!.latitude, currentPosition!.longitude);
    final meters = radiusMiles * 1609.34;

    return {
      Circle(
        circleId: const CircleId('working-radius'),
        center: center,
        radius: meters,
        fillColor: Colors.blue.withOpacity(0.2),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      ),
    };
  }

  Set<Marker> _buildMarkers() {
    if (currentPosition == null) return {};
    final LatLng pos =
        LatLng(currentPosition!.latitude, currentPosition!.longitude);

    if (isActive && wrenchIcon != null) {
      return {
        Marker(
          markerId: const MarkerId('mechanic'),
          position: pos,
          icon: wrenchIcon!,
          anchor: const Offset(0.5, 0.5),
          infoWindow: const InfoWindow(title: 'You (Mechanic)'),
        ),
      };
    }

    return {
      Marker(
        markerId: const MarkerId('mechanic'),
        position: pos,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You (Mechanic)'),
      ),
    };
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    if (currentPosition != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
        ),
      );
    }
  }

  void _openMessages() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Recipient ID'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'User ID'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final otherId = controller.text.trim();
                if (otherId.isNotEmpty) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MessagesPage(
                        currentUserId: widget.userId,
                        otherUserId: otherId,
                      ),
                    ),
                  );
                }
              },
              child: const Text('Chat'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng initialMapPos = currentPosition != null
        ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
        : const LatLng(37.7749, -122.4194); // Default SF location

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mechanic Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'View My Invoices',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoicesPage(userId: widget.userId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.mail),
            tooltip: 'Messages',
            onPressed: _openMessages,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: initialMapPos,
                    zoom: 13,
                  ),
                  myLocationEnabled: !kIsWeb,
                  myLocationButtonEnabled: !kIsWeb,
                  markers: _buildMarkers(),
                  circles: _buildRadiusCircles(),
                ),
                if (kIsWeb)
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton(
                      heroTag: 'center_map',
                      onPressed: () {
                        if (currentPosition != null) {
                          mapController?.animateCamera(
                            CameraUpdate.newLatLng(
                              LatLng(
                                currentPosition!.latitude,
                                currentPosition!.longitude,
                              ),
                            ),
                          );
                        }
                      },
                      child: const Icon(Icons.my_location),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text('Status: $status', style: const TextStyle(fontSize: 20)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _toggleStatus,
                  child: Text(isActive ? 'Go Inactive' : 'Go Active'),
                ),
                const SizedBox(height: 20),
                Slider(
                  min: 1,
                  max: 50,
                  value: radiusMiles,
                  label: '${radiusMiles.toInt()} miles',
                  divisions: 49,
                  onChanged: (val) {
                    setState(() {
                      radiusMiles = val;
                    });
                  },
                  onChangeEnd: (val) {
                    if (isActive) {
                      FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
                        'radiusMiles': val,
                      });
                      FirebaseFirestore.instance.collection('mechanics').doc(widget.userId).update({
                        'radiusMiles': val,
                      });
                    }
                  },
                ),
                Text('Service Radius: ${radiusMiles.toInt()} miles'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    positionStream?.cancel();
    backgroundTimer?.cancel();
    invoiceSubscription?.cancel();
    super.dispose();
  }

  void _startPositionUpdates() async {
    positionStream?.cancel(); // cancel previous stream
    backgroundTimer?.cancel(); // cancel any background timer

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 2),
    );

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((position) async {
      setState(() {
        currentPosition = position;
      });

      if (isActive && currentPosition != null) {
        await FirebaseFirestore.instance.collection('mechanics').doc(widget.userId).update({
          'location': {
            'lat': currentPosition!.latitude,
            'lng': currentPosition!.longitude,
          },
          'timestamp': DateTime.now(),
        });
        await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
          'location': {
            'lat': currentPosition!.latitude,
            'lng': currentPosition!.longitude,
          },
          'timestamp': DateTime.now(),
        });
      }
    });
  }
}