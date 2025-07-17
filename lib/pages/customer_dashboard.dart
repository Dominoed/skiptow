import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:skiptow/pages/create_invoice_page.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:skiptow/services/error_logger.dart';
import 'package:intl/intl.dart';
import 'dart:async';
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
  bool _locationBannerVisible = false;
  bool _hasAccountData = true;
  int availableMechanicCount = 0;
  bool _noMechanicsSnackbarShown = false;
  bool _requestAcceptedBannerVisible = false;
  bool _completedBannerVisible = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _acceptedInvoiceSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _completedInvoiceSub;
  Timer? _etaTimer;
  String _etaText = '';
  String? _acceptedMechanicId;

  void _showLocationBanner() {
    if (_locationBannerVisible || !mounted) return;
    _locationBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
            'Location access is required for real-time updates. Please enable location.'),
        actions: [
          TextButton(
            onPressed: () async {
              _hideLocationBanner();
              await Geolocator.requestPermission();
              _checkLocationPermissionOnLoad();
            },
            child: const Text('Grant'),
          ),
        ],
      ),
    );
  }

  void _hideLocationBanner() {
    if (!_locationBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _locationBannerVisible = false;
  }

  void _showRequestAcceptedBanner() {
    if (_requestAcceptedBannerVisible || !mounted) return;
    _requestAcceptedBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      const MaterialBanner(
        content: Text('✅ Mechanic has accepted your service request!'),
        actions: [SizedBox.shrink()],
      ),
    );
  }

  void _hideRequestAcceptedBanner() {
    if (!_requestAcceptedBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _requestAcceptedBannerVisible = false;
  }

  void _listenForAcceptedInvoices() {
    _acceptedInvoiceSub?.cancel();
    _acceptedInvoiceSub = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _showRequestAcceptedBanner();
        final data = snapshot.docs.first.data();
        final mechId = data['mechanicId'] as String?;
        if (mechId != null) {
          _startEtaUpdates(mechId);
        } else {
          _etaTimer?.cancel();
          setState(() {
            _etaText = 'ETA unavailable';
            _acceptedMechanicId = null;
          });
        }
      } else {
        _hideRequestAcceptedBanner();
        _etaTimer?.cancel();
        setState(() {
          _etaText = '';
          _acceptedMechanicId = null;
        });
      }
    }, onError: (e) {
      logError('Accepted invoice listen error: $e');
    });
  }

  void _showCompletedBanner() {
    if (_completedBannerVisible || !mounted) return;
    _completedBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      const MaterialBanner(
        content: Text('✅ Work completed. Please verify payment and service outcome.'),
        backgroundColor: Colors.green,
        actions: [SizedBox.shrink()],
      ),
    );
  }

  void _hideCompletedBanner() {
    if (!_completedBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _completedBannerVisible = false;
  }

  void _listenForCompletedInvoices() {
    _completedInvoiceSub?.cancel();
    _completedInvoiceSub = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .where('status', whereIn: ['completed', 'closed'])
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _showCompletedBanner();
      } else {
        _hideCompletedBanner();
      }
    }, onError: (e) {
      logError('Completed invoice listen error: $e');
    });
  }

  bool get _hasAvailableMechanics {
    for (var data in mechanicsInRange.values) {
      if (data['withinActive'] == true) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _verifyAccountData();
    _listenForAcceptedInvoices();
    _listenForCompletedInvoices();
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

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services are disabled.')),
      );
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    bool requested = false;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      requested = true;
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location permissions are permanently denied.')),
      );
      return false;
    }

    final granted =
        permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;

    return requested && granted;
  }

  Future<void> _checkLocationPermissionOnLoad() async {
    final newlyGranted = await _ensureLocationPermission();
    final permission = await Geolocator.checkPermission();
    final granted =
        permission == LocationPermission.always || permission == LocationPermission.whileInUse;
    if (!granted) {
      setState(() {
        _locationPermissionGranted = false;
      });
      _showLocationBanner();
    } else {
      _hideLocationBanner();
      setState(() {
        _locationPermissionGranted = true;
      });
      if (newlyGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission granted.')),
        );
      }
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
      logError('Error getting location: $e');
      debugPrint('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get current location')),
      );
    }
  }

  Future<void> _refreshLocation() async {
    await _getCurrentLocation();
    if (currentPosition != null) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
        ),
      );
    }
  }

  void _centerMap() {
    if (currentPosition != null) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
        ),
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
    bool requested = false;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      requested = true;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _locationPermissionGranted = false;
      });
      _showLocationBanner();
      return false;
    }

    final wasGranted = _locationPermissionGranted;
    setState(() {
      _locationPermissionGranted = true;
    });
    _hideLocationBanner();
    if (!wasGranted && requested && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission granted.')),
      );
    }

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
    int count = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data.containsKey('location') && data.containsKey('radiusMiles')) {
        final double lat = data['location']['lat'];
        final double lng = data['location']['lng'];
        final double radius = data['radiusMiles'];
        final double extendedRadius = radius + 2;

        double? distance;
        if (currentPosition != null) {
          distance = Geolocator.distanceBetween(
                currentPosition!.latitude,
                currentPosition!.longitude,
                lat,
                lng,
              ) /
              1609.34; // meters to miles
        }

        if (distance != null) {
          if (distance <= radius) {
            insideActive = true;
          } else if (distance <= extendedRadius) {
            insideExtended = true;
          }
          if (distance <= extendedRadius) {
            count++;
          }
        }

        tempMarkers.add(
          Marker(
            markerId: MarkerId(doc.id),
            position: LatLng(lat, lng),
            icon: wrenchIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  distance != null && distance <= radius
                      ? BitmapDescriptor.hueGreen
                      : BitmapDescriptor.hueAzure,
                ),
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(
              title: data['username'] ?? 'Unnamed',
              snippet: distance != null
                  ? 'You are ${distance.toStringAsFixed(1)} miles from this mechanic.'
                  : 'Distance unknown.',
            ),
            onTap: () {
              mapController?.showMarkerInfoWindow(MarkerId(doc.id));
              if (chooseTechMode) {
                if (!_hasAvailableMechanics) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No mechanics available nearby.')),
                  );
                  return;
                }

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
                      distance: distance ?? 0,
                    ),
                  ),
                );
              } else {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MessagesPage(
                      currentUserId: widget.userId,
                      otherUserId: doc.id,
                      initialMessage:
                          "I'm nearby your radius. Are you available for service?",
                    ),
                  ),
                );
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateInvoicePage(
                      customerId: widget.userId,
                      mechanicId: doc.id,
                      mechanicUsername: data['username'] ?? 'Unnamed',
                      distance: distance ?? 0,
                      defaultDescription:
                          'My car is near your location. Please assist.',
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
          'withinActive': distance != null && distance <= radius,
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

    final bool noMechanics = !insideActive && !insideExtended;

    setState(() {
      showNoMechanics = noMechanics;
      markers = noMechanics ? {} : tempMarkers;
      mechanicsInRange = inRange;
      mechanicStatusMessage = insideActive
          ? "✅ Mechanic nearby"
          : insideExtended
              ? "❗❓Mechanic nearby, but you're ${inRange.values.first['distance'].toStringAsFixed(1)} mi outside their range"
              : "❌ No active mechanics nearby";
      availableMechanicCount = count;
    });

    if (noMechanics && !_noMechanicsSnackbarShown && mounted) {
      _noMechanicsSnackbarShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mechanics available nearby.')),
      );
    }
    if (!noMechanics) {
      _noMechanicsSnackbarShown = false;
    }
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

  Widget _buildMessagesIcon() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collectionGroup('threads')
          .where('recipientId', isEqualTo: widget.userId)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.size : 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.mail),
              tooltip: 'Messages',
              onPressed: _openMessages,
            ),
            if (count > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildActiveInvoiceOverlay() {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.docs.first.data();
        final car = data['carInfo'] ?? {};
        final year = (car['year'] ?? '').toString();
        final make = (car['make'] ?? '').toString();
        final model = (car['model'] ?? '').toString();
        final vehicle = [year, make, model].where((e) => e.isNotEmpty).join(' ');

        if (vehicle.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('Your Request: $vehicle'),
        );
      },
    );
  }

  Widget _buildArrivalOverlay() {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'arrived')
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('🚗 Mechanic has arrived!'),
        );
      },
    );
  }

  Widget _buildInProgressOverlay() {
    final stream = FirebaseFirestore.instance
        .collection('invoices')
        .where('customerId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'in_progress')
        .limit(1)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('🛠️ Mechanic is working on your vehicle.'),
        );
      },
    );
  }

  Widget _buildMechanicCountOverlay() {
    final text = availableMechanicCount > 0
        ? 'Available Mechanics Nearby: ' + availableMechanicCount.toString()
        : 'No mechanics currently available.';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text),
    );
  }

  Widget _buildEtaOverlay() {
    if (_etaText.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _etaText,
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _startEtaUpdates(String mechanicId) {
    _acceptedMechanicId = mechanicId;
    _etaTimer?.cancel();
    _updateEta();
    _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updateEta());
  }

  Future<void> _updateEta() async {
    if (_acceptedMechanicId == null || currentPosition == null) {
      if (mounted) {
        setState(() {
          _etaText = 'ETA unavailable';
        });
      }
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_acceptedMechanicId)
          .get();
      final data = doc.data();
      final loc = data?['location'];
      if (loc == null || loc['lat'] == null || loc['lng'] == null) {
        if (mounted) {
          setState(() {
            _etaText = 'ETA unavailable';
          });
        }
        return;
      }

      final meters = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
      final miles = meters / 1609.34;
      final etaMinutes = (miles / 30) * 60;
      final eta = etaMinutes.isFinite ? etaMinutes.ceil() : null;

      if (mounted) {
        setState(() {
          _etaText = eta != null
              ? 'Estimated arrival: ${eta.toString()} minutes'
              : 'ETA unavailable';
        });
      }
    } catch (e) {
      logError('ETA update error: $e');
      if (mounted) {
        setState(() {
          _etaText = 'ETA unavailable';
        });
      }
    }
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

    if (!_hasAvailableMechanics) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mechanics available nearby.')),
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
          _buildMessagesIcon(),
        ],
      ),
      body: !_locationPermissionGranted
          ? const Center(
              child: Text('Location permission is required to view the map.'),
            )
          : currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : showNoMechanics
                  ? const Center(
                      child: Text('No active mechanics nearby.'),
                    )
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
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('invoices')
                        .where('customerId', isEqualTo: widget.userId)
                        .where('status', isEqualTo: 'active')
                        .limit(1)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final data = snapshot.data!.docs.first.data();
                      final Timestamp? ts = data['createdAt'];
                      if (ts == null) return const SizedBox.shrink();
                      final timeStr =
                          DateFormat('h:mm a').format(ts.toDate().toLocal());
                      return Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Service request submitted at $timeStr',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 60,
                  left: 10,
                  right: 10,
                  child: _buildMechanicCountOverlay(),
                ),
                Positioned(
                  top: 100,
                  left: 10,
                  right: 10,
                  child: _buildEtaOverlay(),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: FloatingActionButton(
                    heroTag: 'refresh_location_cust',
                    tooltip: 'Refresh Location',
                    mini: true,
                    onPressed: _refreshLocation,
                    child: const Icon(Icons.refresh),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton.extended(
                    heroTag: 'center_map_cust',
                    tooltip: 'Center Map',
                    label: const Text('Center Map'),
                    icon: const Icon(Icons.my_location),
                    onPressed: _centerMap,
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _buildActiveInvoiceOverlay(),
                ),
                Positioned(
                  top: 90,
                  left: 10,
                  child: _buildArrivalOverlay(),
                ),
                Positioned(
                  top: 130,
                  left: 10,
                  child: _buildInProgressOverlay(),
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
                              onPressed: _hasAvailableMechanics
                                  ? _handleAnyTech
                                  : () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('No mechanics available nearby.')),
                                      );
                                    },
                              child: const Text("Any Tech"),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _hasAvailableMechanics
                                  ? () {
                                      setState(() {
                                        chooseTechMode = true;
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text("☝🏽 Find and tap a mechanic icon")),
                                      );
                                    }
                                  : () {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('No mechanics available nearby.')),
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

  @override
  void dispose() {
    _acceptedInvoiceSub?.cancel();
    _completedInvoiceSub?.cancel();
    _etaTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }
}
