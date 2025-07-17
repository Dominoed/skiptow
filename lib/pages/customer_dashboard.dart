import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:skiptow/pages/create_invoice_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'service_request_history_page.dart';
import 'messages_page.dart';

class CustomerDashboard extends StatefulWidget {
  final String userId;
  const CustomerDashboard({required this.userId, super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  Position? currentPosition;
  GoogleMapController? mapController;
  Map<String, dynamic> mechanicsInRange = {};
  Set<Marker> markers = {};
  BitmapDescriptor? wrenchIcon;
  bool showNoMechanics = true;
  String mechanicStatusMessage = "";
  bool chooseTechMode = false;
  String? selectedMechanicId;
  bool _locationPermissionGranted = false;
  bool _hasAccountData = true;

  @override
  void initState() {
    super.initState();
    _verifyAccountData();
  }

  Future<void> _verifyAccountData() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    if (!doc.exists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Account data not found. Please contact support.')),
        );
      }
      setState(() {
        _hasAccountData = false;
      });
      return;
    }

    _loadWrenchIcon();
    _checkLocationPermissionOnLoad();
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
    // ✅ Permission granted — you can now get location
  }

  Future<void> _checkLocationPermissionOnLoad() async {
    await _ensureLocationPermission();
    final permission = await Geolocator.checkPermission();
    final granted =
        permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text('Location permission is required for map features.'),
            action: SnackBarAction(
              label: 'Grant',
              onPressed: () async {
                await Geolocator.requestPermission();
                _checkLocationPermissionOnLoad();
              },
            ),
          ),
        );
      }
    } else {
      setState(() {
        _locationPermissionGranted = true;
      });
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        currentPosition = position;
      });

      if (kIsWeb && currentPosition != null) {
        markers.add(
          Marker(
            markerId: const MarkerId('web-user-location'),
            position: LatLng(currentPosition!.latitude, currentPosition!.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          ),
        );
      }

      _loadMechanics();
    } catch (e) {
      debugPrint('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location')),
      );
    }
  }

  Future<bool> _handleLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Location permission is required for map features.'),
          action: SnackBarAction(
            label: 'Grant',
            onPressed: () async {
              await Geolocator.requestPermission();
            },
          ),
        ),
      );
      setState(() {
        _locationPermissionGranted = false;
      });
      return false;
    }

    setState(() {
      _locationPermissionGranted = true;
    });

    return true;
  }

  Future<void> _loadWrenchIcon() async {
    wrenchIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/icons/wrench.png',
    );
    if (mounted) setState(() {});
  }

  void _loadMechanics() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').where('isActive', isEqualTo: true).get();

    Map<String, dynamic> inRange = {};
    Set<Marker> tempMarkers = {};
    bool insideActive = false;
    bool insideExtended = false;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data.containsKey('location') && data.containsKey('radiusMiles')) {
        final double lat = data['location']['lat'];
        final double lng = data['location']['lng'];
        final double radius = data['radiusMiles'];
        final double extendedRadius = radius + 2;

        final double distance = Geolocator.distanceBetween(
          currentPosition!.latitude,
          currentPosition!.longitude,
          lat,
          lng,
        ) / 1609.34; // meters to miles

        if (distance <= radius) {
          insideActive = true;
        } else if (distance <= extendedRadius) {
          insideExtended = true;
        }

        tempMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: wrenchIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  distance <= radius
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueAzure,
                ),
            anchor: const Offset(0.5, 0.5),
            onTap: () {
              if (chooseTechMode) {
                setState(() {
                  selectedMechanicId = doc.id;
                  chooseTechMode = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Mechanic technician chosen")),
                );

                // 👇 Navigate to invoice creation page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateInvoicePage(
                      customerId: widget.userId,
                      mechanicId: doc.id,
                      mechanicUsername: data['username'] ?? 'Unnamed',
                      distance: distance,
                    ),
                  ),
                );
              }
            },
          ),
        );

        inRange[doc.id] = {
          'username': data['username'] ?? 'Unnamed',
          'distance': distance,
          'withinActive': distance <= radius,
        };
      }
    }

    if (kIsWeb && currentPosition != null) {
      tempMarkers.add(
        Marker(
          markerId: const MarkerId('web-user-location'),
          position:
              LatLng(currentPosition!.latitude, currentPosition!.longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    setState(() {
      markers = tempMarkers;
      mechanicsInRange = inRange;
      showNoMechanics = !insideActive && !insideExtended;
      mechanicStatusMessage = insideActive
          ? "✅ Mechanic nearby"
          : insideExtended
              ? "❗❓Mechanic nearby, but you're ${inRange.values.first['distance'].toStringAsFixed(1)} mi outside their range"
              : "❌ No active mechanics nearby";
    });
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

  void _handleAnyTech() {
    final activeMechanics = <Map<String, dynamic>>[];
    mechanicsInRange.forEach((id, data) {
      if (data['withinActive'] == true) {
        activeMechanics.add({
          'id': id,
          'username': data['username'],
          'distance': data['distance'],
        });
      }
    });

    if (activeMechanics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mechanics in range')),
      );
      return;
    }

    Future<void> continueFn() async {
      Navigator.pop(context); // close dialog if open
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateInvoicePage(
            customerId: widget.userId,
            mechanicId: 'any',
            mechanicUsername: 'Any Tech',
            distance: 0,
          ),
        ),
      );
    }

    if (activeMechanics.length > 1) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Nearby Mechanics'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: activeMechanics.length,
                itemBuilder: (context, index) {
                  final m = activeMechanics[index];
                  final dist = (m['distance'] as double).toStringAsFixed(1);
                  return ListTile(
                    title: Text(m['username'] ?? 'Unnamed'),
                    subtitle: Text('$dist mi away'),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: continueFn,
                child: const Text('Request Service'),
              ),
            ],
          );
        },
      );
    } else {
      continueFn();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccountData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer Map')),
        body: const Center(
          child: Text('Account data not found. Please contact support.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Customer Map"),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'View My Requests',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceRequestHistoryPage(
                    userId: widget.userId,
                  ),
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
      body: !_locationPermissionGranted
          ? Center(
              child: ElevatedButton(
                onPressed: _checkLocationPermissionOnLoad,
                child: const Text('Grant Location Permission'),
              ),
            )
          : currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  markers: markers,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      currentPosition!.latitude,
                      currentPosition!.longitude,
                    ),
                    zoom: 13,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                if (kIsWeb)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: FloatingActionButton(
                      mini: true,
                      heroTag: 'webLocationBtn',
                      onPressed: () {
                        if (currentPosition != null) {
                          mapController?.animateCamera(CameraUpdate.newLatLng(
                            LatLng(currentPosition!.latitude, currentPosition!.longitude),
                          ));
                        }
                      },
                      child: const Icon(Icons.my_location),
                    ),
                  ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: showNoMechanics ? Colors.red[100] : Colors.green[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          mechanicStatusMessage,
                          style: const TextStyle(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (!showNoMechanics)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: _handleAnyTech,
                              child: const Text("Any Tech"),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  chooseTechMode = true;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("☝🏽 Find and tap a mechanic icon")),
                                );
                              },
                              child: const Text("Choose Tech"),
                            ),
                          ],
                        )
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
