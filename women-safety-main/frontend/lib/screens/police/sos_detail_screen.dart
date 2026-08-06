import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'police_chat_screen.dart';
import 'live_evidence_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/map_routing_service.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';


class SosDetailScreen extends StatefulWidget {
  final Map<String, dynamic> sosData;

  const SosDetailScreen({super.key, required this.sosData});

  @override
  State<SosDetailScreen> createState() => _SosDetailScreenState();
}

class _SosDetailScreenState extends State<SosDetailScreen> {
  late GoogleMapController mapController;
  late LatLng _center;
  Timer? _pollingTimer;
  LatLng? _liveVictimLocation;
  LatLng? _policeLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    final rawItem = widget.sosData['rawItem'];
    if (rawItem != null && rawItem['location'] != null && rawItem['location']['coordinates'] != null) {
      final coords = rawItem['location']['coordinates'];
      double lat, lng;
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      } else {
        lat = (coords['lat'] ?? 9.9674).toDouble();
        lng = (coords['lng'] ?? 76.2958).toDouble();
      }
      _center = LatLng(lat, lng);
    } else {
    _center = const LatLng(9.9674, 76.2958);
    }
    _getCurrentPoliceLocation();
    _buildMarkers();
    _startLiveTracking();
  }

  Future<void> _getCurrentPoliceLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _policeLocation = LatLng(position.latitude, position.longitude);
        _buildMarkers();
      });
      _fetchRoute();
    } catch (e) {
      debugPrint("Error getting police location: $e");
    }
  }

  void _startLiveTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
       final res = await ApiService.getAlertVictimLocation(widget.sosData['id']);
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
             _liveVictimLocation = LatLng(lat, lng);
             _buildMarkers();
             _fetchRoute();
           });
         }
       }
    });
  }

  Future<void> _fetchRoute() async {
    if (_policeLocation == null) return;
    
    final destination = _liveVictimLocation ?? _center;

    final points = await MapRoutingService.getRoutePoints(
      origin: _policeLocation!,
      destination: destination,
      mode: 'driving', // Police usually drive
    );

    if (mounted && points.isNotEmpty) {
      setState(() {
        _routePoints = points;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('police_rescue_route'),
            points: _routePoints,
            color: Colors.blue,
            width: 5,
          ),
        };
      });
    }
  }

  void _buildMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('sos_location'),
        position: _liveVictimLocation ?? _center,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Victim: ${widget.sosData['name']}'),
      ),
    };

    if (_policeLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('police_location'),
          position: _policeLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Your Location (Police)'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  void _showNoPhoneError(String role) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No phone number available for this $role.'),
        backgroundColor: Colors.orange,
      ),
    );
  }
  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    final sos = widget.sosData;
    final status = sos['status']?.toString().toLowerCase() ?? 'pending';
    final statusColor = (status == 'pending' || status == 'active') 
        ? Colors.red 
        : (status == 'accepted' || status == 'in-progress' ? const Color(0xFF2563EB) : Colors.green);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text('SOS Details', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                sos['status'].toUpperCase(),
                style: GoogleFonts.inter(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Map View
            SizedBox(
              height: 250,
              child: Stack(
                children: [
                  GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: CameraPosition(
                      target: _center,
                      zoom: 14.0,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    zoomControlsEnabled: false,
                    myLocationEnabled: true,
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FloatingActionButton.small(
                      backgroundColor: Colors.white,
                      onPressed: () {},
                      child: const Icon(Icons.my_location, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Victim Details Card
                  _buildSectionTitle('Victim Information'),
                  _buildVictimCard(sos),
                  const SizedBox(height: 24),
                  
                  // Action Panel
                  _buildSectionTitle('Quick Actions'),
                  _buildQuickActions(),
                  const SizedBox(height: 24),

                  // Communication
                  _buildSectionTitle('Communication'),
                  _buildCommunicationOptions(context),
                  const SizedBox(height: 24),

                   // SOS State Management
                  _buildSectionTitle('Incident Management'),
                  _buildStatusUpdateSection(),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildVictimCard(Map<String, dynamic> sos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _buildInfoRow(Icons.person, 'Name', sos['name']),
          const Divider(),
          _buildInfoRow(Icons.phone, 'Phone', sos['phone']),
          const Divider(),
          _buildInfoRow(Icons.badge, 'ID', sos['id']),
          const Divider(),
          _buildInfoRow(Icons.timer, 'Time Elapsed', sos['time'], color: Colors.red),
          const Divider(),
          _buildInfoRow(Icons.shield, 'Assigned Volunteer', sos['volunteer'], color: const Color(0xFF2563EB)),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B)),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final sos = widget.sosData;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                Icons.call, 
                'Call User', 
                sos['victimPhone']?.isNotEmpty == true ? Colors.green : Colors.grey, 
                sos['victimPhone']?.isNotEmpty == true ? () => _makePhoneCall(sos['victimPhone']) : () => _showNoPhoneError('User')
              )
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                Icons.support_agent, 
                'Call Volunteer', 
                sos['volunteerPhone']?.isNotEmpty == true ? const Color(0xFF2563EB) : Colors.grey, 
                sos['volunteerPhone']?.isNotEmpty == true ? () => _makePhoneCall(sos['volunteerPhone']) : () => _showNoPhoneError('Volunteer')
              )
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _buildActionButton(
            Icons.camera_alt, 
            'Watch Live Evidence Feed', 
            Colors.redAccent, 
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => LiveEvidencePlayer(alertId: sos['id'])),
              );
            }
          ),
        ),
      ],

    );
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCommunicationOptions(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PoliceChatScreen(alertId: widget.sosData['id'])),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: const Color(0xFF2563EB).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.group, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Three-way Communication',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    'Group chat with User & Volunteer',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusUpdateSection() {
    final status = widget.sosData['status']?.toString().toLowerCase() ?? 'pending';
    
    String actionLabel = '';
    String nextStatus = '';
    Color color = Colors.grey;
    IconData icon = Icons.info_outline;
    String description = '';

    if (status == 'pending' || status == 'active') {
      actionLabel = 'Start Rescue';
      nextStatus = 'in-progress';
      color = const Color(0xFF2563EB);
      icon = Icons.play_arrow;
      description = 'Mark this incident as being handled';
    } else if (status == 'accepted' || status == 'in-progress') {
      actionLabel = 'Mark as Done';
      nextStatus = 'done';
      color = Colors.green;
      icon = Icons.check_circle;
      description = 'Close this emergency request';
    } else {
      // Done / Resolved
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.green),
            const SizedBox(width: 12),
            Text(
              'This incident has been completed.',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Updated Status',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    description,
                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                  ),
                ],
              )
            ],
          ),
          ElevatedButton(
            onPressed: () => _updateSOSStatus(nextStatus),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSOSStatus(String nextStatus) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    if (nextStatus == 'in-progress') {
      // Ensure the authority joins the alert officially for 3-way chat synchronization
      await ApiService.joinAlert(widget.sosData['id']);
    }
    
    final res = await ApiService.updateAlertStatus(widget.sosData['id'], nextStatus);
    
    if (mounted) Navigator.pop(context); // dismiss loading
    
    if (res['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Incident status updated to ${nextStatus.replaceAll('-', ' ')}'))
      );
      if (mounted) {
        if (nextStatus == 'done' || nextStatus == 'resolved') {
          Navigator.pop(context, true); // Go back with refresh signal only when done
        } else {
          setState(() {
            widget.sosData['status'] = nextStatus;
          });
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to update status'))
      );
    }
  }
}
