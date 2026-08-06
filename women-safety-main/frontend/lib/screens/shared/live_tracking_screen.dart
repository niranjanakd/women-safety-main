import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../services/api_service.dart';

class LiveTrackingScreen extends StatefulWidget {
  final String sessionId;
  final String victimName;

  const LiveTrackingScreen({
    super.key,
    required this.sessionId,
    required this.victimName,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  GoogleMapController? _mapController;
  Timer? _trackingTimer;
  LatLng? _currentLoc;
  LatLng? _destinationLoc;
  String _destinationAddress = "Loading destination...";
  bool _isLoading = true;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  List<LatLng> _historyPath = [];

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    // Update every 10 seconds for "movements"
    _trackingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateLocation();
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    final result = await ApiService.getSessionLiveLocation(widget.sessionId);
    if (result['success']) {
      final data = result['data'];
      setState(() {
        _currentLoc = LatLng(data['latitude'], data['longitude']);
        
        if (data['path'] != null) {
          _historyPath = (data['path'] as List).map((p) => LatLng(p['latitude'], p['longitude'])).toList();
        }

        if (data['destination'] != null && data['destination']['coordinates'] != null) {
          final dest = data['destination']['coordinates'];
          _destinationLoc = LatLng(dest['lat'], dest['lng']);
          _destinationAddress = data['destination']['address'] ?? "Destination";
        }

        if (data['routePoints'] != null) {
          _routePoints = (data['routePoints'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList();
        }
        
        _updateMarkers();
        _updatePolylines();
        _isLoading = false;
      });
      
      if (_mapController != null && _currentLoc != null) {
        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentLoc!, 15));
      }
    }
  }

  Future<void> _updateLocation() async {
    final result = await ApiService.getSessionLiveLocation(widget.sessionId);
    if (result['success']) {
      final data = result['data'];
      final newLoc = LatLng(data['latitude'], data['longitude']);
      if (mounted) {
        setState(() {
          _currentLoc = newLoc;
          if (data['path'] != null) {
            _historyPath = (data['path'] as List).map((p) => LatLng(p['latitude'], p['longitude'])).toList();
          }
          if (data['routePoints'] != null && _routePoints.isEmpty) {
             _routePoints = (data['routePoints'] as List).map((p) => LatLng(p['lat'], p['lng'])).toList();
          }
          _updateMarkers();
          _updatePolylines();
        });
      }
    }
  }

  void _updateMarkers() {
    if (_currentLoc == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('current_pos'),
          position: _currentLoc!,
          infoWindow: InfoWindow(title: "${widget.victimName}'s Current Location"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      };

      if (_destinationLoc != null) {
        _markers.add(
          Marker(
            markerId: const MarkerId('destination'),
            position: _destinationLoc!,
            infoWindow: InfoWindow(title: "Destination: $_destinationAddress"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }
    });
  }

  void _updatePolylines() {
    setState(() {
      _polylines = {};
      
      // 1. Traveled Path (History)
      if (_historyPath.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('history_path'),
            points: _historyPath,
            color: Colors.blue.withOpacity(0.7),
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }

      // 2. Planned Route (if available)
      if (_routePoints.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('live_route'),
            points: _routePoints,
            color: Colors.grey.withOpacity(0.5),
            width: 4,
            patterns: [PatternItem.dash(10), PatternItem.gap(10)],
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Live Tracking: ${widget.victimName}",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _currentLoc ?? const LatLng(0, 0),
                    zoom: 15,
                  ),
                  onMapCreated: (controller) => _mapController = controller,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapType: MapType.normal,
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton(
                    heroTag: "focus_victim",
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: () {
                      if (_currentLoc != null && _mapController != null) {
                        _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentLoc!, 16));
                      }
                    },
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.directions_walk, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${widget.victimName} is on the move",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    "Updating live every 10 seconds",
                                    style: GoogleFonts.inter(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
