import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:skiptow/services/error_logger.dart';
import 'invoices_page.dart';
import 'messages_page.dart';
import 'mechanic_request_queue_page.dart';
import 'mechanic_requests_page.dart';
import 'mechanic_job_history_page.dart';
import 'mechanic_profile_page.dart';
import 'mechanic_earnings_report_page.dart';
import 'mechanic_notifications_page.dart';
import 'mechanic_radius_history_page.dart';
import 'mechanic_location_history_page.dart';
import '../services/alert_service.dart';

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
  bool _locationPermissionGranted = false;
  bool _locationBannerVisible = false;
  bool _alertBannerVisible = false;
  bool _unavailableBannerVisible = false;
  bool _hasAccountData = true;
  bool _blocked = false;
  int completedJobs = 0;
  bool unavailable = false;

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

  void _showAlertBanner(Map<String, dynamic> alert) {
    if (_alertBannerVisible || !mounted) return;
    _alertBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alert['title'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if ((alert['body'] ?? '').toString().isNotEmpty)
              Text(alert['body'] ?? '')
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _hideAlertBanner();
              AlertService.dismiss();
            },
            child: const Text('Dismiss'),
          )
        ],
      ),
    );
  }

  void _hideAlertBanner() {
    if (!_alertBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _alertBannerVisible = false;
  }

  void _showUnavailableBanner() {
    if (_unavailableBannerVisible || !mounted) return;
    _unavailableBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        backgroundColor: Colors.orange,
        content: const Text(
            'You are marked as temporarily unavailable and will not receive requests.'),
        actions: [
          TextButton(
            onPressed: _hideUnavailableBanner,
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  void _hideUnavailableBanner() {
    if (!_unavailableBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _unavailableBannerVisible = false;
  }

  Future<void> _checkGlobalAlert() async {
    final alert = await AlertService.fetchAlert();
    if (alert != null) {
      _showAlertBanner(alert);
    }
  }

  @override
  void initState() {
    super.initState();
    _verifyAccountData();
    _checkGlobalAlert();
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

    final data = doc.data();
    if (data != null && data['blocked'] == true) {
      setState(() {
        _blocked = true;
      });
      return;
    }

    _loadWrenchIcon();
    _listenForInvoices();
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
      _loadStatus();
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

    final data = doc.data();
    if (data != null) {
      if (data['blocked'] == true) {
        setState(() {
          _blocked = true;
        });
        return;
      }
      setState(() {
        isActive = data['isActive'] ?? false;
        radiusMiles = (data['radiusMiles'] ?? 5).toDouble();
        completedJobs = data['completedJobs'] ?? 0;
        unavailable = data['unavailable'] ?? false;
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

      if (unavailable) {
        _showUnavailableBanner();
      } else {
        _hideUnavailableBanner();
      }

      // ✅ Start live updates if mechanic is active and permission granted
      if (isActive && _locationPermissionGranted) {
        _startPositionUpdates();
      }
    }
  }

  Future<void> _toggleStatus() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    // Determine if the mechanic is going from inactive to active
    final goingActive = !isActive;

    if (!isActive) {
      try {
        currentPosition = await Geolocator.getCurrentPosition();
      } catch (e) {
        logError('Get current position error: $e');
        currentPosition = null;
      }
      if (currentPosition == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Cannot go active. Location unavailable.')),
          );
        }
        return;
      }
    }

    final data = {
      'isActive': !isActive,
      'radiusMiles': radiusMiles,
      'location': currentPosition != null
          ? {'lat': currentPosition!.latitude, 'lng': currentPosition!.longitude}
          : FieldValue.delete(),
      'role': 'mechanic',
      'timestamp': DateTime.now(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(data);
    } catch (e) {
      logError('Toggle status update error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('An error occurred. Please try again.')),
        );
      }
      debugPrint('$e');
      return;
    }

    setState(() {
      isActive = !isActive;
      status = isActive ? 'Active' : 'Inactive';
    });

    if (isActive && _locationPermissionGranted) {
      _startPositionUpdates();
    } else {
      positionStream?.cancel();
      backgroundTimer?.cancel();
    }

    // Navigate to the request queue page when activating
    if (goingActive && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MechanicRequestQueuePage(mechanicId: widget.userId),
        ),
      );
    }
  }

  Future<void> _toggleUnavailable(bool value) async {
    final data = <String, dynamic>{
      'unavailable': value,
      'timestamp': DateTime.now(),
    };
    if (value) {
      data['isActive'] = false;
    }
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update(data);
    } catch (e) {
      logError('Toggle unavailable error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('An error occurred. Please try again.')),
        );
      }
      return;
    }

    setState(() {
      unavailable = value;
      if (value) {
        isActive = false;
        status = 'Inactive';
      }
    });

    if (value) {
      positionStream?.cancel();
      backgroundTimer?.cancel();
      _showUnavailableBanner();
    } else {
      _hideUnavailableBanner();
    }
  }

  Future<void> _onTogglePressed() async {
    if (unavailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disable Temporarily Unavailable to go active.')),
        );
      }
      return;
    }
    if (!isActive) {
      if (!_locationPermissionGranted || currentPosition == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Enable location access to go active.')),
          );
        }
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Confirm Activation'),
            content: const Text(
                'Are you ready to go active and start receiving service requests?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes'),
              ),
            ],
          );
        },
      );

      if (confirm != true) {
        return;
      }
    }

    await _toggleStatus();
  }

  void _listenForInvoices() {
    invoiceSubscription?.cancel();
    invoiceSubscription = FirebaseFirestore.instance
        .collection('invoices')
        // Monitor only invoices assigned to this mechanic
        .where('mechanicId', isEqualTo: widget.userId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen((snapshot) {
      if (_initialInvoiceLoad) {
        _initialInvoiceLoad = false;
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added &&
            change.doc.data()?['flagged'] != true) {
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

  Set<Circle> _buildRadiusCircles() {
    if (!_locationPermissionGranted || currentPosition == null || !isActive) {
      return {};
    }
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
    if (!_locationPermissionGranted || currentPosition == null) return {};
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagesPage(currentUserId: widget.userId),
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MechanicNotificationsPage(userId: widget.userId),
      ),
    );
  }

  Widget _buildMessagesIcon() {
    return IconButton(
      icon: const Icon(Icons.mail),
      tooltip: 'Messages',
      onPressed: _openMessages,
    );
  }

  Widget _buildNotificationsIcon() {
    return IconButton(
      icon: const Icon(Icons.notifications),
      tooltip: 'Notifications',
      onPressed: _openNotifications,
    );
  }

  Widget _buildActiveRequests() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('invoices')
          .where('mechanicId', isEqualTo: widget.userId)
          .where('status', whereIn: [
            'accepted',
            'arrived',
            'in_progress',
            'completed'
          ])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          );
        }
        final docs = (snapshot.data?.docs ?? [])
            .where((d) => d.data()['flagged'] != true)
            .where((d) => d.data()['invoiceStatus'] != 'cancelled')
            .toList();
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No active requests'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Active Requests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...docs.map(
              (d) => _ActiveRequestCard(
                invoiceId: d.id,
                data: d.data(),
                mechanicId: widget.userId,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccountData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mechanic Dashboard')),
        body: const Center(
          child: Text('Account data not found. Please contact support.'),
        ),
      );
    }

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
            icon: const Icon(Icons.work_outline),
            tooltip: 'Request Queue',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MechanicRequestsPage(
                    mechanicId: widget.userId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.inbox),
            tooltip: 'Service Requests',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MechanicRequestQueuePage(
                    mechanicId: widget.userId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Job History',
            onPressed: _blocked
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MechanicJobHistoryPage(
                          mechanicId: widget.userId,
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Earnings Report',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MechanicEarningsReportPage(
                    mechanicId: widget.userId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: 'Radius History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MechanicRadiusHistoryPage(mechanicId: widget.userId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.location_searching),
            tooltip: 'Location History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MechanicLocationHistoryPage(mechanicId: widget.userId),
                ),
              );
            },
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MechanicProfilePage(userId: widget.userId),
                ),
              );
            },
            icon: const Icon(Icons.person, color: Colors.white),
            label: const Text(
              'Profile',
              style: TextStyle(color: Colors.white),
            ),
          ),
          _buildMessagesIcon(),
          _buildNotificationsIcon(),
        ],
      ),
      body: _blocked
          ? const Center(
              child:
                  Text('Your account has been blocked. Contact admin.'),
            )
          : !_locationPermissionGranted
              ? const Center(
                  child:
                      Text('Location permission is required to view the map.'),
                )
              : Column(
              children: [
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('invoices')
                      .where('mechanicId', isEqualTo: widget.userId)
                      .where('paymentStatus', isEqualTo: 'paid')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];
                    final jobs = docs.length;
                    double earnings = 0.0;
                    for (final doc in docs) {
                      earnings += (doc.data()['finalPrice'] as num?)?.toDouble() ?? 0.0;
                    }
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Text(
                            'Total Jobs Completed: $jobs',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total Earnings (Paid Invoices): \$${earnings.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('invoices')
                      .where('mechanicId', isEqualTo: widget.userId)
                      .where('status', isEqualTo: 'active')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final activeCount = snapshot.hasData ? snapshot.data!.docs.where((d) => d.data()["flagged"] != true).length : 0;
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Active Jobs: $activeCount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.userId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    final completedCount = data?['completedJobs'] ?? completedJobs;
                    final blocked = data?['blocked'] == true;
                    if (blocked != _blocked) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _blocked = blocked;
                          });
                        }
                      });
                    }
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Total Completed Jobs: $completedCount',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
                _buildActiveRequests(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: isActive ? Colors.green : Colors.red,
                  child: Column(
                    children: [
                      Text(
                        'Service Status: ${isActive ? 'Active' : 'Inactive'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isActive
                            ? 'Customers in your radius can now send you service requests.'
                            : 'You are not visible to customers.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
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
                      Positioned(
                        bottom: 16,
                        left: 16,
                        child: FloatingActionButton(
                          heroTag: 'refresh_location',
                          tooltip: 'Refresh Location',
                          mini: true,
                          onPressed: _refreshLocation,
                          child: const Icon(Icons.refresh),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: FloatingActionButton.extended(
                          heroTag: 'center_map_mech',
                          tooltip: 'Center Map',
                          label: const Text('Center Map'),
                          icon: const Icon(Icons.my_location),
                          onPressed: _centerMap,
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
                  onPressed: _blocked ? null : _onTogglePressed,
                  child: Text(isActive ? 'Go Inactive' : 'Go Active'),
                ),
                SwitchListTile(
                  title: const Text('Temporarily Unavailable'),
                  value: unavailable,
                  onChanged: _blocked ? null : _toggleUnavailable,
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
                  onChangeEnd: (val) async {
                    if (isActive) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.userId)
                            .update({
                          'radiusMiles': val,
                          'role': 'mechanic',
                          'timestamp': DateTime.now(),
                        });
                      } catch (e) {
                        logError('Update radius error: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('An error occurred. Please try again.')),
                          );
                        }
                        debugPrint('$e');
                      }
                    }
                    try {
                      await FirebaseFirestore.instance
                          .collection('mechanics')
                          .doc(widget.userId)
                          .collection('radius_history')
                          .add({
                        'timestamp': DateTime.now(),
                        'newRadiusMiles': val,
                      });
                    } catch (e) {
                      logError('Radius history log error: $e');
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

  void _centerMap() {
    if (currentPosition != null) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(currentPosition!.latitude, currentPosition!.longitude),
        ),
      );
    }
  }

  Future<void> _refreshLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        currentPosition = position;
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );

      if (isActive) {
        await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({
          'location': {'lat': position.latitude, 'lng': position.longitude},
          'role': 'mechanic',
          'timestamp': DateTime.now(),
        });
        await _storeLocationHistory();
      }
    } catch (e) {
      logError('Error refreshing location: $e');
      debugPrint('Error refreshing location: $e');
    }
  }

  Future<void> _storeLocationHistory() async {
    if (!isActive || currentPosition == null) return;
    try {
      final now = DateTime.now();
      await FirebaseFirestore.instance
          .collection('mechanics')
          .doc(widget.userId)
          .collection('location_history')
          .doc(now.millisecondsSinceEpoch.toString())
          .set({
        'lat': currentPosition!.latitude,
        'lng': currentPosition!.longitude,
        'timestamp': now,
      });
    } catch (e) {
      logError('Location history save error: $e');
    }
  }

  void _startPositionUpdates() async {
    if (!_locationPermissionGranted) return;
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
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .update({
            'location': {
              'lat': currentPosition!.latitude,
              'lng': currentPosition!.longitude,
            },
            'role': 'mechanic',
            'timestamp': DateTime.now(),
          });
        } catch (e) {
          logError('Position update error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('An error occurred. Please try again.')),
            );
          }
          debugPrint('$e');
        }
      }
    });

    // store initial history and schedule periodic updates every 2 minutes
    await _storeLocationHistory();
    backgroundTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _storeLocationHistory();
    });
  }
}

class _ActiveRequestCard extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;
  final String mechanicId;

  const _ActiveRequestCard({
    required this.invoiceId,
    required this.data,
    required this.mechanicId,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'closed':
        return Colors.blueGrey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.yellow[700]!;
    }
  }

  Future<void> _updateEstimate(BuildContext context) async {
    final controller = TextEditingController(
      text: (data['estimatedPrice'] as num?)?.toString(),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Update Estimate'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Estimated Price (USD)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, double.tryParse(controller.text)),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (value != null) {
      await FirebaseFirestore.instance
          .collection('invoices')
          .doc(invoiceId)
          .update({'estimatedPrice': value});
    }
  }

  Future<void> _markCompleted(BuildContext context) async {
    final priceController = TextEditingController();
    final notesController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>?>(
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
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
        final double fee = double.parse((price * 0.15).toStringAsFixed(2));
        await FirebaseFirestore.instance
            .collection('invoices')
            .doc(invoiceId)
            .update({
          'status': 'completed',
          'finalPrice': price,
          'postJobNotes': notes,
          'platformFee': fee,
        });
        await FirebaseFirestore.instance
            .collection('users')
            .doc(mechanicId)
            .update({'completedJobs': FieldValue.increment(1)});
      }
    }
  }

  void _viewDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailPage(
          invoiceId: invoiceId,
          role: 'mechanic',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = data['description'] ?? '';
    final location = data['location'];
    final status = (data['status'] ?? 'active').toString();

    final actions = <Widget>[];
    if (status != 'completed' && status != 'closed' && status != 'cancelled') {
      actions.add(
        ElevatedButton(
          onPressed: () => _markCompleted(context),
          child: const Text('Mark Completed'),
        ),
      );
      actions.add(
        TextButton(
          onPressed: () => _updateEstimate(context),
          child: const Text('Update Estimate'),
        ),
      );
    }
    actions.add(
      TextButton(
        onPressed: () => _viewDetails(context),
        child: const Text('Details'),
      ),
    );

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(data['customerId'])
          .get(),
      builder: (context, snapshot) {
        final customerName = snapshot.data?.data()?['username'] ?? data['customerId'];
        return Card(
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Customer: $customerName'),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(status),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (description.toString().isNotEmpty) Text(description),
                if (location != null &&
                    location['lat'] != null &&
                    location['lng'] != null)
                  Text('Location: ${location['lat']}, ${location['lng']}')
                else
                  const Text('Location unavailable.'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions
                      .map((w) => Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: w,
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
