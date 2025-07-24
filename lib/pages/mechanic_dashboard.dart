import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:skiptow/services/error_logger.dart';
import 'dart:typed_data';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../services/image_downloader.dart';
import 'package:intl/intl.dart';
import 'invoices_page.dart';
import 'messages_page.dart';
import 'jobs_page.dart';
import 'mechanic_profile_page.dart';
import 'settings_page.dart';
import 'mechanic_earnings_report_page.dart';
import 'mechanic_notifications_page.dart';
import 'mechanic_radius_history_page.dart';
import 'mechanic_location_history_page.dart';
import 'help_support_page.dart';
import 'mechanic_performance_stats_page.dart';
import '../services/alert_service.dart';
import 'mechanic_current_job_page.dart';
import 'invoice_detail_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'login_page.dart';

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
  // These streams are initialized once in initState to avoid recreating
  // Firestore listeners on every build, which caused loading spinners to
  // briefly appear whenever state updated (e.g. location updates).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeJobsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _activeRequestsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _awaitingFeedbackStream;
  bool isActive = false;
  double radiusMiles = 5;
  String status = 'Inactive';
  Position? currentPosition;
  GoogleMapController? mapController;
  bool _locationPermissionGranted = false;
  bool _locationBannerVisible = false;
  bool _alertBannerVisible = false;
  bool _unavailableBannerVisible = false;
  bool _activeRequestsBannerVisible = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _activeRequestsSub;
  bool _hasAccountData = true;
  bool _blocked = false;
  bool _suspicious = false;
  bool _proUser = false;
  int completedJobs = 0;
  bool unavailable = false;
  String? _currentSessionId;
  String? _referralLink;
  final GlobalKey _qrKey = GlobalKey();

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

  void _showActiveRequestsBanner() {
    if (_activeRequestsBannerVisible || !mounted) return;
    _activeRequestsBannerVisible = true;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text('⚠️ You have active jobs.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobsPage(userId: widget.userId),
                ),
              );
            },
            child: const Text('View Current Jobs'),
          ),
        ],
      ),
    );
  }

  void _hideActiveRequestsBanner() {
    if (!_activeRequestsBannerVisible || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    _activeRequestsBannerVisible = false;
  }

  void _listenForActiveRequests() {
    _activeRequestsSub?.cancel();
    _activeRequestsSub = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.userId)
        .where('invoiceStatus', whereIn: ['accepted', 'in_progress'])
        .snapshots()
        .listen((snapshot) {
      final docs = snapshot.docs
          .where((d) => d.data()['flagged'] != true)
          .toList();
      if (docs.isNotEmpty) {
        _showActiveRequestsBanner();
      } else {
        _hideActiveRequestsBanner();
      }
    }, onError: (e) {
      logError('Active requests listen error: $e');
    });
  }

  Future<void> _checkGlobalAlert() async {
    final alert = await AlertService.fetchAlert();
    if (alert != null) {
      _showAlertBanner(alert);
    }
  }

  Future<void> _updateLastActive() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'lastActiveAt': FieldValue.serverTimestamp()});
    } catch (e) {
      logError('Update lastActiveAt error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _activeJobsStream = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.userId)
        .where('invoiceStatus', whereIn: ['accepted', 'arrived', 'in_progress'])
        .snapshots();

    _activeRequestsStream = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.userId)
        .where('status', whereIn: [
          'accepted',
          'arrived',
          'in_progress',
          'completed'
        ])
        .snapshots();

    _awaitingFeedbackStream = FirebaseFirestore.instance
        .collection('invoices')
        .where('mechanicId', isEqualTo: widget.userId)
        .where('invoiceStatus', whereIn: ['completed', 'closed'])
        .snapshots();
    _updateLastActive();
    _verifyAccountData();
    _checkGlobalAlert();
    _listenForActiveRequests();
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

    _proUser = getBool(data, 'isProUser');
    if (_proUser) {
      _loadReferralLink();
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

  Future<void> _loadReferralLink() async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(widget.userId);
      final snap = await docRef.get();
      String? link = snap.data()?['referralLink'];
      link ??= 'https://skiptow.site/mechanic/${widget.userId}';
      if (snap.data()?['referralLink'] == null) {
        await docRef.update({'referralLink': link});
      }
      if (mounted) {
        setState(() {
          _referralLink = link;
        });
      }
    } catch (e) {
      logError('Load referral link error: $e');
    }
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
      _suspicious = data['suspicious'] == true;
      setState(() {
        isActive = getBool(data, 'isActive');
        radiusMiles = (data['radiusMiles'] ?? 5).toDouble();
        completedJobs = data['completedJobs'] ?? 0;
        unavailable = getBool(data, 'unavailable');
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
        await _fetchActiveSession();
        if (_currentSessionId == null) {
          await _startSession();
        }
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

    if (isActive) {
      await _startSession();
      if (_locationPermissionGranted) {
        _startPositionUpdates();
      }
    } else {
      await _endSession();
      positionStream?.cancel();
      backgroundTimer?.cancel();
    }

    // Navigate to the jobs page when activating
    if (goingActive && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JobsPage(userId: widget.userId),
        ),
      );
    }
  }

  Future<void> _toggleUnavailable(bool value) async {
    final data = <String, dynamic>{
      'unavailable': value,
      'isActive': !value,
      'timestamp': DateTime.now(),
    };
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
      isActive = !value;
      status = isActive ? 'Active' : 'Inactive';
    });

    if (value) {
      positionStream?.cancel();
      backgroundTimer?.cancel();
      await _endSession();
      _showUnavailableBanner();
    } else {
      _hideUnavailableBanner();
      if (isActive) {
        await _startSession();
        if (_locationPermissionGranted) {
          _startPositionUpdates();
        }
      }
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
                'Are you ready to go active and start receiving jobs?'),
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
              const SnackBar(content: Text('New job received')),
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
    return TextButton.icon(
      onPressed: _openNotifications,
      icon: Icon(
        Icons.notifications,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
      label: Text(
        'Notifications',
        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
      ),
    );
  }

  Widget _buildActiveJobs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeJobsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          );
        }
        final docs = (snapshot.data?.docs ?? [])
            .where((d) => d.data()['flagged'] != true)
            .toList();
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No active jobs'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Your Active Jobs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...docs.map(
              (d) => _ActiveJobCard(
                invoiceId: d.id,
                data: d.data(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveRequests() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeRequestsStream,
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

  Widget _buildAwaitingFeedback() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _awaitingFeedbackStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          );
        }
        final docs = (snapshot.data?.docs ?? [])
            .where((d) => d.data()['flagged'] != true)
            .toList();
        if (docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Awaiting Feedback',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...docs.map(
              (d) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: d.reference.collection('mechanicFeedback').snapshots(),
                builder: (context, fbSnap) {
                  if (!fbSnap.hasData || fbSnap.data!.docs.isNotEmpty) {
                    return const SizedBox.shrink();
                  }
                  final data = d.data();
                  return ListTile(
                    title: Text('Invoice ${d.id}'),
                    subtitle: Text((data['description'] ?? '').toString()),
                    trailing: TextButton(
                      onPressed: () =>
                          showCustomerRatingDialog(context, d.id),
                      child: const Text('Rate'),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }




  Widget _buildReferralQr() {
    if (!_proUser) return const SizedBox.shrink();
    if (_referralLink == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Referral QR Code',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _qrKey,
            child: QrImageView(
              data: _referralLink!,
              version: QrVersions.auto,
              size: 200.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: _shareReferralLink,
                child: const Text('Share Referral Link'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _downloadQrCode,
                child: const Text('Download QR Code Image'),
              ),
            ],
          ),
        ],
      ),
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
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
              child: const Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('View My Invoices'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoicesPage(userId: widget.userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.work_outline),
              title: const Text('Jobs'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JobsPage(userId: widget.userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Earnings Report'),
              onTap: () {
                Navigator.pop(context);
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
            ListTile(
              leading: const Icon(Icons.query_stats),
              title: const Text('Performance Stats'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MechanicPerformanceStatsPage(mechanicId: widget.userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.timeline),
              title: const Text('Radius History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MechanicRadiusHistoryPage(mechanicId: widget.userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.location_searching),
              title: const Text('Location History'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MechanicLocationHistoryPage(mechanicId: widget.userId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MechanicProfilePage(
                      mechanicId: widget.userId,
                      referral: false,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Account Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettingsPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('Help & Support'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HelpSupportPage(
                      userId: widget.userId,
                      userRole: 'mechanic',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.mail),
              title: const Text('Messages'),
              onTap: () {
                Navigator.pop(context);
                _openMessages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notifications'),
              onTap: () {
                Navigator.pop(context);
                _openNotifications();
              },
            ),
          ],
        ),
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
                if (_suspicious)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.red,
                    child: const Text(
                      '⚠️ Suspicious User',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_suspicious) const SizedBox(height: 8),
                _buildActiveJobs(),
                _buildAwaitingFeedback(),
                _buildReferralQr(),
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
                            ? 'Customers in your radius can now send you jobs.'
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
                      // Map refresh is triggered from the dashboard page
                      Positioned(
                        top: 10,
                        left: 10,
                        child: _buildFloatingButtons(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Status: $status',
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _blocked ? null : _onTogglePressed,
                            child:
                                Text(isActive ? 'Go Inactive' : 'Go Active'),
                          ),
                        ],
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
      floatingActionButton: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('invoices')
            .where('mechanicId', isEqualTo: widget.userId)
            .where('invoiceStatus', whereIn: ['accepted', 'in_progress'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(),
            );
          }
          final docs = (snapshot.data?.docs ?? [])
              .where((d) => d.data()['flagged'] != true)
              .toList();
          if (docs.isEmpty) return const SizedBox.shrink();

          void openJob(String id) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MechanicCurrentJobPage(invoiceId: id),
              ),
            );
          }

          return FloatingActionButton.extended(
            onPressed: () {
              if (docs.length == 1) {
                openJob(docs.first.id);
              } else {
                showModalBottomSheet(
                  context: context,
                  builder: (_) {
                    return ListView(
                      children: [
                        for (final d in docs)
                          ListTile(
                            title: Text('Invoice ${d.id}'),
                            subtitle: Text(
                                (d.data()['invoiceStatus'] ?? '').toString()),
                            trailing: const Icon(Icons.arrow_forward),
                            onTap: () {
                              Navigator.pop(context);
                              openJob(d.id);
                            },
                          ),
                      ],
                    );
                  },
                );
              }
            },
            label: Text(docs.length == 1 ? 'View Current Job' : 'Manage Jobs'),
            icon: const Icon(Icons.work),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    if (isActive) {
      _endSession();
    }
    positionStream?.cancel();
    backgroundTimer?.cancel();
    invoiceSubscription?.cancel();
    _activeRequestsSub?.cancel();
    super.dispose();
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

  /// Expose location refresh for parent widgets
  void refreshLocation() {
    _refreshLocation();
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

  void _shareReferralLink() {
    if (_referralLink != null) {
      Share.share(_referralLink!);
    }
  }

  Future<void> _downloadQrCode() async {
    if (_referralLink == null) return;
    try {
      final painter = QrPainter(
        data: _referralLink!,
        version: QrVersions.auto,
        gapless: true,
      );
      final ByteData? data = await painter.toImageData(300);
      if (data == null) return;
      await downloadImage(data.buffer.asUint8List(),
          fileName: 'referral_${widget.userId}.png');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR code image downloaded')),
        );
      }
    } catch (e) {
      logError('QR code download error: $e');
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await const FlutterSecureStorage().delete(key: 'session_token');
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Widget _buildFloatingButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          heroTag: 'refresh_button',
          onPressed: _refreshLocation,
          tooltip: 'Refresh Location',
          child: const Icon(Icons.my_location),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'settings_button',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            );
          },
          tooltip: 'Settings',
          child: const Icon(Icons.settings),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'help_button',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HelpSupportPage(
                  userId: widget.userId,
                  userRole: 'mechanic',
                ),
              ),
            );
          },
          tooltip: 'Help / Support',
          child: const Icon(Icons.help_outline),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'logout_button',
          onPressed: _logout,
          tooltip: 'Logout',
          child: const Icon(Icons.logout),
        ),
      ],
    );
  }

  Future<void> _startSession() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('mechanic_sessions')
          .doc(widget.userId)
          .collection('sessions')
          .add({'startTime': DateTime.now(), 'endTime': null});
      _currentSessionId = doc.id;
    } catch (e) {
      logError('Start session error: $e');
    }
  }

  Future<void> _endSession() async {
    try {
      String? id = _currentSessionId;
      if (id == null) {
        final snap = await FirebaseFirestore.instance
            .collection('mechanic_sessions')
            .doc(widget.userId)
            .collection('sessions')
            .where('endTime', isNull: true)
            .orderBy('startTime', descending: true)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) id = snap.docs.first.id;
      }
      if (id != null) {
        await FirebaseFirestore.instance
            .collection('mechanic_sessions')
            .doc(widget.userId)
            .collection('sessions')
            .doc(id)
            .update({'endTime': DateTime.now()});
      }
    } catch (e) {
      logError('End session error: $e');
    } finally {
      _currentSessionId = null;
    }
  }

  Future<void> _fetchActiveSession() async {
    final snap = await FirebaseFirestore.instance
        .collection('mechanic_sessions')
        .doc(widget.userId)
        .collection('sessions')
        .where('endTime', isNull: true)
        .orderBy('startTime')
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      _currentSessionId = snap.docs.first.id;
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

class _ActiveJobCard extends StatelessWidget {
  final String invoiceId;
  final Map<String, dynamic> data;

  const _ActiveJobCard({required this.invoiceId, required this.data});

  @override
  Widget build(BuildContext context) {
    final description = data['description'] ?? '';
    final status =
        (data['invoiceStatus'] ?? data['status'] ?? '').toString();
    final paymentStatus = (data['paymentStatus'] ?? 'pending').toString();
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(data['customerId'])
          .get(),
      builder: (context, snapshot) {
        final customerName =
            snapshot.data?.data()?['username'] ?? data['customerId'];
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invoice $invoiceId',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text('Customer: $customerName'),
                          if (description.toString().isNotEmpty)
                            Text(
                              description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _invoiceStatusColor(status),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _paymentColor(paymentStatus),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            paymentStatus,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => InvoiceDetailPage(
                              invoiceId: invoiceId,
                              role: 'mechanic',
                            ),
                          ),
                        );
                      },
                      child: const Text('Details'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MechanicCurrentJobPage(invoiceId: invoiceId),
                          ),
                        );
                      },
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
        final double fee = double.parse((price * 0.10).toStringAsFixed(2));
        final docRef =
            FirebaseFirestore.instance.collection('invoices').doc(invoiceId);
        final existing = await docRef.get();
        final updateData = {
          'status': 'completed',
          'invoiceStatus': 'completed',
          'finalPrice': price,
          'postJobNotes': notes,
          'platformFee': fee,
        };
        if (existing.data()?['closedAt'] == null) {
          updateData['closedAt'] = FieldValue.serverTimestamp();
        }
        await docRef.update(updateData);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(mechanicId)
            .update({'completedJobs': FieldValue.increment(1)});

        // Ask mechanic if payment was collected in person
        final paidInPerson = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Mark as Paid in Person?'),
              content: const Text(
                  'Has the customer paid you directly for this job?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('No'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Yes'),
                ),
              ],
            );
          },
        );

        if (paidInPerson == true) {
          await docRef.update({'paymentStatus': 'paid_in_person'});
        } else if (paidInPerson == false) {
          await docRef.update({'paymentStatus': 'unpaid'});
        }

        await showCustomerRatingDialog(context, invoiceId);
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
    final invoiceStatus =
        (data['invoiceStatus'] ?? data['status'] ?? 'active').toString();

    final actions = <Widget>[];
    if (invoiceStatus != 'closed' && invoiceStatus != 'cancelled') {
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

Color _paymentColor(String status) {
  switch (status) {
    case 'paid':
    case 'paid_in_person':
      return Colors.green;
    case 'failed':
      return Colors.red;
    case 'unpaid':
    case 'pending':
      return Colors.orange;
    default:
      return Colors.grey;
  }
}
