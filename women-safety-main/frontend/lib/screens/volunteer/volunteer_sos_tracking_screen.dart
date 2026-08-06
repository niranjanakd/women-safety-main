import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/api_service.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

class VolunteerSosTrackingScreen extends StatefulWidget {
  final Map<String, dynamic> alert;
  const VolunteerSosTrackingScreen({super.key, required this.alert});

  @override
  State<VolunteerSosTrackingScreen> createState() =>
      _VolunteerSosTrackingScreenState();
}

class _VolunteerSosTrackingScreenState
    extends State<VolunteerSosTrackingScreen> {
  late LatLng _victimLocation;
  LatLng? _myLocation;
  Timer? _pollingTimer;
  Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    final coords = widget.alert['location']['coordinates'];
    double lat, lng;
    if (coords is List && coords.length >= 2) {
      lng = (coords[0] as num).toDouble();
      lat = (coords[1] as num).toDouble();
    } else {
      lat = (coords['lat'] ?? 0.0).toDouble();
      lng = (coords['lng'] ?? 0.0).toDouble();
    }
    _victimLocation = LatLng(lat, lng);

    _getCurrentLocation();
    _startLiveTracking();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _myLocation = LatLng(position.latitude, position.longitude);
        _updateMarkers();
      });
    } catch (e) {
      debugPrint("Error getting volunteer location: $e");
    }
  }

  void _startLiveTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final res = await ApiService.getAlertVictimLocation(widget.alert['_id']);
      if (res['success']) {
        final coords = res['data']['coordinates'];
        if (mounted) {
          setState(() {
            double lat, lng;
            if (coords is List && coords.length >= 2) {
              lng = (coords[0] as num).toDouble();
              lat = (coords[1] as num).toDouble();
            } else {
              lat = (coords['lat'] as num).toDouble();
              lng = (coords['lng'] as num).toDouble();
            }
            _victimLocation = LatLng(lat, lng);
            _updateMarkers();
          });
        }
      }
    });
  }

  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('victim'),
        position: _victimLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Victim: ${widget.alert['user']?['name'] ?? 'Unknown'}',
        ),
      ),
    };

    if (_myLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('volunteer'),
          position: _myLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'You (Volunteer)'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final victimName = widget.alert['user']?['name'] ?? 'Victim';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Tracking - $victimName',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF9333EA),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _victimLocation,
              zoom: 15.0,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: _buildActionPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel() {
    final phone = widget.alert['user']?['phone'] ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFF1F5F9),
                child: Icon(Icons.person, color: Colors.grey.shade600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.alert['user']?['name'] ?? 'Victim',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'SOS Alert Active',
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.red),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.phone, color: Colors.green),
                onPressed: () {
                  if (phone.isNotEmpty) launchUrl(Uri.parse('tel:$phone'));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final lat = _victimLocation.latitude;
                    final lng = _victimLocation.longitude;
                    final url = 'google.navigation:q=$lat,$lng&mode=d';
                    launchUrl(Uri.parse(url));
                  },
                  icon: const Icon(Icons.navigation),
                  label: const Text('Open Maps'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9333EA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
