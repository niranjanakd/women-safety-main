import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../services/api_service.dart';
import 'package:geolocator/geolocator.dart';
import './volunteer_chat_screen.dart';
import './volunteer_profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/location_service.dart';

class VolunteerDashboardScreen extends StatefulWidget {
  const VolunteerDashboardScreen({super.key});

  @override
  State<VolunteerDashboardScreen> createState() => _VolunteerDashboardScreenState();
}

class _VolunteerDashboardScreenState extends State<VolunteerDashboardScreen> {
  bool _isActiveDuty = true; // Default to online for test
  List<dynamic> _incidents = [];
  Position? _currentPosition;
  int _selectedIndex = 0;
  StreamSubscription? _locationSubscription;
  int _lastIncidentCount = 0;

  // Real stats from API
  String _peopleHelped = "0";
  String _activeAlertsCount = "0";
  String _avgResponseTime = "0 min";
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
    _fetchStats();
    _setupLocationListener();
  }

  void _setupLocationListener() {
    _locationSubscription?.cancel();
    _locationSubscription = LocationService().locationStream.listen((position) {
      if (mounted && _isActiveDuty) {
        setState(() {
          _currentPosition = position;
        });
        _fetchIncidents();
      }
    });
    
    // Initial sync
    if (LocationService().currentPosition != null) {
      _currentPosition = LocationService().currentPosition;
      if (_isActiveDuty) _fetchIncidents();
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    LocationService().startTracking(); // Re-ensure tracking is started
  }

  Future<void> _fetchStats() async {
    final result = await ApiService.getVolunteerStats();
    if (mounted && result['success']) {
      setState(() {
        _peopleHelped = result['data']['peopleHelped'].toString();
        _activeAlertsCount = result['data']['activeAlerts'].toString();
        _avgResponseTime = result['data']['avgResponse'];
        _isLoadingStats = false;
      });
    } else {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }


  Future<void> _fetchIncidents() async {
    if (_currentPosition == null || !_isActiveDuty) return;

    final result = await ApiService.getNearbySOSAlerts(
      _currentPosition!.latitude, 
      _currentPosition!.longitude, 
      radius: 3000
    );

    if (mounted && result['success']) {
      final List newIncidents = result['data'] as List;
      final int newNearbyCount = newIncidents.where((i) => i['isJoined'] != true).length;
      
      if (newNearbyCount > _lastIncidentCount && _lastIncidentCount != 0) {
        // New incident detected nearby!
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'NEW EMERGENCY NEARBY! Please check and respond if possible.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'VIEW',
              textColor: Colors.white,
              onPressed: () {
                // Focus on dashboard if needed
              },
            ),
          ),
        );
      }

      setState(() {
        _incidents = newIncidents;
        _lastIncidentCount = newNearbyCount;
      });
    }
  }

  Future<void> _launchNavigation(String alertId) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA))),
    );

    final result = await ApiService.getAlertDetails(alertId);
    
    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (result['success']) {
      final alert = result['data'];
      final coords = alert['location']['coordinates'];
      double lat, lng;
      if (coords is List && coords.length >= 2) {
        lng = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      } else {
        lat = (coords['lat'] as num).toDouble();
        lng = (coords['lng'] as num).toDouble();
      }

      // Construct Google Maps URL (works on both platforms)
      final String googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
      final String appleMapsUrl = 'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d';

      if (Platform.isIOS) {
        if (await canLaunchUrl(Uri.parse(appleMapsUrl))) {
          await launchUrl(Uri.parse(appleMapsUrl), mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
        }
      } else {
        if (await canLaunchUrl(Uri.parse(googleMapsUrl))) {
          await launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch maps application')),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching live location: ${result['message']}')),
      );
    }
  }

  Future<void> _makeCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) return;
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch dialer')),
        );
      }
    }
  }

  double _calculateDistance(double lat, double lng) {
    if (_currentPosition == null) return 0.0;
    double distanceInMeters = Geolocator.distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude, lat, lng);
    return distanceInMeters / 1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Index 0: Dashboard
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: !_isActiveDuty 
                  ? _buildOfflineView()
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           _buildSectionTitle("Your Active Cases"),
                           if (_incidents.where((i) => i['isJoined'] == true).isEmpty)
                             _buildEmptyActiveState()
                           else
                             ..._incidents.where((i) => i['isJoined'] == true).map((i) => _buildActiveCaseCard(i, key: ValueKey(i['_id'] ?? i.toString()))),

                           _buildSectionTitle("Nearby Emergencies"),
                           if (_incidents.where((i) => i['isJoined'] != true).isEmpty)
                             _buildNearbyAllHandled()
                           else
                             ..._incidents.where((i) => i['isJoined'] != true).map((i) => _buildNearbyEmergencyCard(i, key: ValueKey(i['_id'] ?? i.toString()))),
                           
                           const SizedBox(height: 20),
                        ],
                      ),
                    ),
              ),
            ],
          ),
          // Index 1: Profile
          const VolunteerProfileScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildOfflineView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.power_settings_new_rounded,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "You are Offline",
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              "Toggle your status to 'Online' to start receiving emergency alerts in your community.",
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF9333EA), // Brand Purple
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Volunteer Dashboard',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Community Safety Network',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _buildStatusPill(),
            ],
          ),
          const SizedBox(height: 32),
                // Stats section
                _isLoadingStats 
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator(color: Color(0xFF9333EA))),
                    )
                  : Row(
                      children: [
                        _buildStatCard("People Helped", _peopleHelped),
                        const SizedBox(width: 8),
                        _buildStatCard("Active Alerts", _activeAlertsCount),
                        const SizedBox(width: 8),
                        _buildStatCard("Avg Response", _avgResponseTime),
                      ],
                    ),
        ],
      ),
    );
  }

  Widget _buildStatusPill() {
    return GestureDetector(
      onTap: () async {
        final newStatus = !_isActiveDuty;
        final result = await ApiService.updateVolunteerStatus(newStatus);
        
        if (mounted && result['success']) {
          setState(() {
            _isActiveDuty = newStatus;
            if (!_isActiveDuty) {
              _incidents = []; // Clear incidents when offline
            }
          });
          if (_isActiveDuty) {
             _setupLocationListener(); // Re-establish listener/check
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to update status')),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isActiveDuty ? const Color(0xFF22C55E) : Colors.white24,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _isActiveDuty ? 'Online' : 'Offline',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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

  Widget _buildActiveCaseCard(dynamic i, {Key? key}) {
    String name = i['user']?['name'] ?? 'Unknown User';
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFACC15), width: 1.5), // Yellow border
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF9C3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person, color: Color(0xFFEAB308)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    _buildStatusLabel(i['status'] ?? 'active'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildActionButton("Chat", const Color(0xFF9333EA), Icons.chat_bubble_outline, i, type: 'chat'),
                    const SizedBox(width: 8),
                    _buildActionButton("Call", const Color(0xFF2563EB), Icons.phone_outlined, i, type: 'call'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildActionButton("Navigate", const Color(0xFF0D9488), Icons.navigation_outlined, i, type: 'navigate'),
                    const SizedBox(width: 8),
                    _buildStatusActionButton(i),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLabel(String status) {
    Color color = const Color(0xFFEAB308); // Yellow for in-progress/active
    String label = 'IN PROGRESS';
    
    if (status == 'resolved') {
       color = const Color(0xFF16A34A); // Green for resolved
       label = 'DONE';
    } else if (status == 'active') {
       color = const Color(0xFF3B82F6); // Blue for just started
       label = 'STARTED';
    }

    return Text(
      label,
      style: GoogleFonts.inter(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatusActionButton(dynamic i) {
    String status = i['status'] ?? 'active';
    String label = "Done";
    Color color = const Color(0xFF16A34A);
    IconData icon = Icons.check_circle_outline;

    if (status == 'active') {
      label = "In Progress";
      color = const Color(0xFF3B82F6);
      icon = Icons.timer_outlined;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () async {
          String nextStatus = (status == 'active') ? 'in-progress' : 'resolved';
          final result = await ApiService.updateAlertStatus(i['_id'], nextStatus);
          if (result['success']) {
            _fetchIncidents();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, IconData icon, dynamic i, {String type = 'chat'}) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (type == 'chat') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VolunteerChatScreen(alert: i),
              ),
            );
          } else if (type == 'call') {
            final victimPhone = i['user']?['phone'] ?? '';
            _makeCall(victimPhone);
          } else if (type == 'navigate') {
            _launchNavigation(i['_id']);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyEmergencyCard(dynamic i, {Key? key}) {
    String name = i['user']?['name'] ?? 'Unknown User';
    double lat = 0.0, lng = 0.0;
    try {
      final coords = i['location']?['coordinates'];
      if (coords is List) { lng = (coords[0] as num).toDouble(); lat = (coords[1] as num).toDouble(); }
      else if (coords is Map) { lat = (coords['lat'] as num).toDouble(); lng = (coords['lng'] as num).toDouble(); }
    } catch (_) {}
    
    double distKm = _calculateDistance(lat, lng);

    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.red.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: Colors.red.withOpacity(0.1)),
      ),
      child: Row(
        children: [
           Container(
             padding: const EdgeInsets.all(10),
             decoration: const BoxDecoration(color: Color(0xFFFEF2F2), shape: BoxShape.circle),
             child: const Icon(Icons.warning_rounded, color: Color(0xFFDC2626), size: 24),
           ),
           const SizedBox(width: 16),
           Expanded(
             child: Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                  Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  Text('${distKm.toStringAsFixed(1)} km away • SOS Alert', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade500)),
               ],
             ),
           ),
           ElevatedButton(
             onPressed: () async {
                final result = await ApiService.joinAlert(i['_id']);
                if (mounted && result['success']) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VolunteerChatScreen(alert: result['data'] ?? i),
                    ),
                  ).then((_) => _fetchIncidents());
                } else if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text(result['message'] ?? 'Failed to join alert')),
                   );
                }
             },
             style: ElevatedButton.styleFrom(
               backgroundColor: const Color(0xFFDC2626),
               foregroundColor: Colors.white,
               elevation: 0,
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
               padding: const EdgeInsets.symmetric(horizontal: 16),
             ),
              child: const Text('ACCEPT'),
           )
        ],
      ),
    );
  }

  Widget _buildEmptyActiveState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          "No active cases as a primary responder",
          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildNearbyAllHandled() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF0FDF4), // Green 50
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 40),
          ),
          const SizedBox(height: 12),
          Text(
            "All Handled",
            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            "Your area is safe for now",
            style: GoogleFonts.inter(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF9333EA),
        unselectedItemColor: const Color(0xFF64748B),
        selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
