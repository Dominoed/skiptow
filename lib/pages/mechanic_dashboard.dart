import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

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
    //Move map to current location
    if (mapController != null && currentPosition != null) {
      mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    final LatLng initialMapPos = currentPosition != null
        ? LatLng(currentPosition!.latitude, currentPosition!.longitude)
        : const LatLng(37.7749, -122.4194); // Default SF location

    return Scaffold(
      appBar: AppBar(title: const Text('Mechanic Dashboard')),
      body: Column(
        children: [
          SizedBox(
            height: 300,
            child: GoogleMap(
              onMapCreated: (controller) => mapController = controller,
              initialCameraPosition: CameraPosition(
                target: initialMapPos,
                zoom: 13,
              ),
              myLocationEnabled: false,
              markers: _buildMarkers(),
              circles: _buildRadiusCircles(),
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