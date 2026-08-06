import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import 'dart:async';


class PoliceMapTab extends StatefulWidget {
  const PoliceMapTab({super.key});

  @override
  State<PoliceMapTab> createState() => _PoliceMapTabState();
}

class _PoliceMapTabState extends State<PoliceMapTab> {
  late GoogleMapController mapController;
  final LatLng _center = const LatLng(9.9674, 76.2958);
  
  List<dynamic> _activeAlerts = [];
  List<dynamic> _onlineVolunteers = [];
  bool _isLoading = true;
  Set<Marker> _markers = {};
  StreamSubscription? _locationSubscription;
  LatLng? _currentLocation;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupLocationListener();
    _startPolling();
  }

  void _setupLocationListener() {
    _locationSubscription?.cancel();
    _locationSubscription = LocationService().locationStream.listen((position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    });
    
    // Initial sync
    if (LocationService().currentPosition != null) {
      final pos = LocationService().currentPosition!;
      _currentLocation = LatLng(pos.latitude, pos.longitude);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    final alertRes = await ApiService.getPoliceActiveAlerts();
    final volunteerRes = await ApiService.getPoliceOnlineVolunteers();

    if (mounted) {
      setState(() {
        if (alertRes['success']) _activeAlerts = alertRes['data'];
        if (volunteerRes['success']) _onlineVolunteers = volunteerRes['data'];
        _buildMarkers();
        _isLoading = false;
      });
    }
  }

  void _buildMarkers() {
    final Set<Marker> markers = {};

    // 1. SOS Alert Markers (Red = Active, Orange = In-Progress)
    for (var i = 0; i < _activeAlerts.length; i++) {
      final alert = _activeAlerts[i];
      final user = alert['user'];
      final loc = alert['location']?['coordinates'];
      if (loc != null) {
        double lat, lng;
        if (loc is List && loc.length >= 2) {
          lng = (loc[0] as num).toDouble();
          lat = (loc[1] as num).toDouble();
        } else {
          lat = (loc['lat'] as num).toDouble();
          lng = (loc['lng'] as num).toDouble();
        }
        final status = alert['status'];
        final name = user?['name'] ?? 'Unknown Victim';

        markers.add(
          Marker(
            markerId: MarkerId('alert_$i'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: 'SOS: $name',
              snippet: status == 'active' ? 'Status: PENDING' : 'Status: ACCEPTED (Rescue in Progress)',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              status == 'active' ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
            ),
          ),
        );
      }
    }

    // 2. Volunteer Markers (Blue)
    for (var i = 0; i < _onlineVolunteers.length; i++) {
      final volunteer = _onlineVolunteers[i];
      final loc = volunteer['currentLocation']?['coordinates'];
      // coordinates is [longitude, latitude] in GeoJSON
      if (loc != null && loc.length >= 2) {
        final lng = loc[0].toDouble();
        final lat = loc[1].toDouble();
        final name = volunteer['name'] ?? 'Volunteer';

        markers.add(
          Marker(
            markerId: MarkerId('volunteer_$i'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: 'Volunteer: $name',
              snippet: 'Status: ONLINE & AVAILABLE',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ),
        );
      }
    }

    _markers = markers;
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: _center,
                zoom: 12.0,
              ),
              markers: _markers,
              polylines: {},
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
            ),
          
          // Custom Header
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.track_changes, color: Color(0xFF2563EB)),
                  const SizedBox(width: 12),
                  Text(
                    'Live Tracking System',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text('${_isLoading ? "..." : _activeAlerts.length} Active', style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                  )
                ],
              ),
            ),
          ),

          // Map Legend
          Positioned(
            bottom: 30,
            left: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(Colors.red, 'Pending SOS'),
                  const SizedBox(height: 8),
                  _buildLegendItem(Colors.orange, 'Accepted SOS'),
                  const SizedBox(height: 8),
                  _buildLegendItem(Colors.blue, 'Volunteer Units'),
                ],
              ),
            ),
          ),

          // My Location Button
          Positioned(
            bottom: 30,
            right: 16,
            child: FloatingActionButton(
              backgroundColor: Colors.white,
              onPressed: () {
                if (_currentLocation != null) {
                  mapController.animateCamera(CameraUpdate.newLatLng(_currentLocation!));
                } else {
                  mapController.animateCamera(CameraUpdate.newLatLng(_center));
                }
              },
              child: const Icon(Icons.my_location, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF475569))),
      ],
    );
  }
}
