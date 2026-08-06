import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;
import 'dart:async';
import '../../services/api_service.dart';
import '../../services/location_service.dart';

class SafetyResource {
  final String id;
  final String title;
  final String subtitle;
  final String distance;
  final String status;
  final String iconName;
  final Color color;
  final Color iconColor;
  final String category;
  final String phone;
  final double? lat;
  final double? lng;

  SafetyResource({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.distance,
    required this.status,
    required this.iconName,
    required this.color,
    required this.iconColor,
    required this.category,
    this.phone = '112',
    this.lat,
    this.lng,
  });

  factory SafetyResource.fromJson(Map<String, dynamic> json, {double? userLat, double? userLng}) {
    // Handle new GeoJSON format: location: { type: 'Point', coordinates: [lng, lat] }
    final location = json['location'];
    double? lat, lng;
    if (location != null && location['coordinates'] != null) {
      final coords = location['coordinates'] as List;
      if (coords.length >= 2) {
        lng = coords[0].toDouble();
        lat = coords[1].toDouble();
      }
    }

    String distanceStr = json['distance'] ?? 'Unknown';
    if (userLat != null && userLng != null && lat != null && lng != null) {
      final double distMeters = _calculateDistance(userLat, userLng, lat, lng);
      distanceStr = '${(distMeters / 1000).toStringAsFixed(1)} km';
    }

    return SafetyResource(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      distance: distanceStr,
      status: json['status'] ?? '',
      iconName: json['icon'] ?? 'help_outline',
      color: _parseColor(json['color'], const Color(0xFFEFF6FF)),
      iconColor: _parseColor(json['iconColor'], const Color(0xFF2563EB)),
      category: json['category'] ?? 'General',
      phone: json['phone'] ?? '112',
      lat: lat,
      lng: lng,
    );
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        Math.cos((lat2 - lat1) * p) / 2 +
        Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * Math.asin(Math.sqrt(a)) * 1000;
  }

  static Color _parseColor(String? colorStr, Color fallback) {
    if (colorStr == null || colorStr.isEmpty) return fallback;
    try {
      String hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      return fallback;
    }
  }

  IconData get icon {
    switch (iconName) {
      case 'verified_user': return Icons.verified_user;
      case 'favorite': return Icons.favorite;
      case 'night_shelter': return Icons.night_shelter;
      case 'pan_tool_outlined': return Icons.pan_tool_outlined;
      case 'air': return Icons.air;
      case 'visibility': return Icons.visibility;
      case 'contact_phone': return Icons.contact_phone;
      default: return Icons.help_outline;
    }
  }
}

class GuideItem {
  final String id;
  final String title;
  final String duration;
  final String iconName;
  final String? url;
  final Color color;

  GuideItem({required this.id, required this.title, required this.duration, required this.iconName, this.url, required this.color});

  factory GuideItem.fromJson(Map<String, dynamic> json) {
    return GuideItem(
      id: json['_id'] ?? '',
      title: json['title'] ?? '',
      duration: json['duration'] ?? '',
      iconName: json['icon'] ?? 'book',
      url: json['url'],
      color: SafetyResource._parseColor(json['color'], const Color(0xFF9C27B0)),
    );
  }

  IconData get icon {
    switch (iconName) {
      case 'pan_tool_outlined': return Icons.pan_tool_outlined;
      case 'air': return Icons.air;
      case 'visibility': return Icons.visibility;
      case 'contact_phone': return Icons.contact_phone;
      default: return Icons.book;
    }
  }
}

class HelplineItem {
  final String id;
  final String name;
  final String number;
  final String description;

  HelplineItem({required this.id, required this.name, required this.number, required this.description});

  factory HelplineItem.fromJson(Map<String, dynamic> json) {
    return HelplineItem(
      id: json['_id'] ?? '',
      name: json['title'] ?? '',
      number: json['phone'] ?? '',
      description: json['description'] ?? '',
    );
  }
}

class SafetyReport {
  final String title;
  final String location;
  final String time;
  final String severity;
  final double distance;

  SafetyReport({
    required this.title,
    required this.location,
    required this.time,
    required this.severity,
    required this.distance,
  });

  factory SafetyReport.fromIncident(Map<String, dynamic> j, double userLat, double userLng) {
    final coords = j['location']?['coordinates'];
    double dist = 0.0;
    if (coords != null && coords is List && coords.length >= 2) {
      double incLng = coords[0].toDouble();
      double incLat = coords[1].toDouble();
      dist = _calculateDistance(userLat, userLng, incLat, incLng);
    }

    // Simple "time ago" formatting
    String timeAgo = 'Recently';
    if (j['createdAt'] != null) {
      final created = DateTime.parse(j['createdAt']);
      final diff = DateTime.now().difference(created);
      if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes} mins ago';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours} hours ago';
      } else {
        timeAgo = '${diff.inDays} days ago';
      }
    }

    return SafetyReport(
      title: j['type'] ?? 'Report',
      location: j['location']?['address'] ?? 'Nearby',
      time: timeAgo,
      severity: j['severity'] ?? 'Medium',
      distance: (dist / 1000).toDouble(), // Convert to km
    );
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        Math.cos((lat2 - lat1) * p) / 2 +
        Math.cos(lat1 * p) * Math.cos(lat2 * p) * (1 - Math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * Math.asin(Math.sqrt(a)) * 1000;
  }
}

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isLoading = true;
  StreamSubscription? _locationSubscription;
  Position? _lastFetchedPosition;

  List<SafetyResource> _allResources = [];
  List<GuideItem> _guides = [];
  List<HelplineItem> _helplines = [];
  List<SafetyReport> _reports = [
    SafetyReport(title: 'Suspicious Activity', location: 'Near Marine Drive', time: '10 mins ago', severity: 'Medium', distance: 0.8),
    SafetyReport(title: 'Inadequate Street Lighting', location: 'Subhash Park Area', time: '2 hours ago', severity: 'Low', distance: 1.2),
    SafetyReport(title: 'Protest/Crowd Warning', location: 'Vytilla Junction', time: 'Just now', severity: 'High', distance: 2.5),
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupLocationListener();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _setupLocationListener() {
    _locationSubscription = LocationService().locationStream.listen((position) {
      if (_lastFetchedPosition == null) {
        _lastFetchedPosition = position;
        return;
      }

      // Re-fetch only if moved more than 500 meters
      double distance = Geolocator.distanceBetween(
        _lastFetchedPosition!.latitude,
        _lastFetchedPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distance > 500) {
        _lastFetchedPosition = position;
        _fetchData();
      } else {
        // Just update distances locally without re-fetching from API
        setState(() {
           // This will trigger a rebuild and SafetyResource.fromJson logic (or manual update)
           // Actually, since SafetyResource instances store distances as strings, we should re-map them
           _updateLocalDistances(position);
        });
      }
    });
  }

  void _updateLocalDistances(Position userPos) {
    setState(() {
      _allResources = _allResources.map((res) {
        if (res.lat != null && res.lng != null) {
          final double distMeters = SafetyResource._calculateDistance(userPos.latitude, userPos.longitude, res.lat!, res.lng!);
          return SafetyResource(
            id: res.id,
            title: res.title,
            subtitle: res.subtitle,
            distance: '${(distMeters / 1000).toStringAsFixed(1)} km',
            status: res.status,
            iconName: res.iconName,
            color: res.color,
            iconColor: res.iconColor,
            category: res.category,
            phone: res.phone,
            lat: res.lat,
            lng: res.lng,
          );
        }
        return res;
      }).toList();
    });
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Get Current Location for Radius Search
      double lat = 0.0;
      double lng = 0.0;
      
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        lat = position.latitude;
        lng = position.longitude;
      } catch (e) {
        debugPrint('Location fetching failed: $e');
        // If we don't have location, we should probably stop or show a message
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location to see Safe Havens')),
          );
        }
        return;
      }

      // 2. Fetch Resources from custom endpoint with radius
      final String resourceUrl = '${ApiService.baseUrl}/resources?lat=$lat&lng=$lng&radius=5000';
      final resResponse = await http.get(Uri.parse(resourceUrl));
      
      // 3. Fetch Nearby Incidents (10km Radius, 24 Hours)
      final incResponse = await ApiService.getNearbyIncidents(lat, lng, radius: 10000, hours: 24);

      if (resResponse.statusCode == 200) {
        final Map<String, dynamic> resBody = jsonDecode(resResponse.body);
        final List<dynamic> resData = resBody['data'] ?? [];
        
        debugPrint('Safe Havens Found: ${resData.length}');
        
        setState(() {
          _allResources = resData.where((item) => item['type'] == 'haven' && item['status'] == 'Open Now')
              .map((j) => SafetyResource.fromJson(j, userLat: lat, userLng: lng)).toList();
          _guides = resData.where((item) => item['type'] == 'guide')
              .map((j) => GuideItem.fromJson(j)).toList();
          _helplines = resData.where((item) => item['type'] == 'helpline')
              .map((j) => HelplineItem.fromJson(j)).toList();
        });
      }

      if (incResponse['success']) {
        final List<dynamic> incData = incResponse['data'];
        setState(() {
          _reports = incData.map((j) => SafetyReport.fromIncident(j, lat, lng)).toList();
        });
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Phone calls not supported on this device ($phoneNumber)')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error launching dialer: $e');
    }
  }

  Future<void> _openNavigation(double destLat, double destLng) async {
    double? originLat;
    double? originLng;

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
           Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
           originLat = position.latitude;
           originLng = position.longitude;
        }
      }
    } catch (e) {
      debugPrint("Could not fetch origin location for navigation: $e");
    }

    String googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=$destLat,$destLng&travelmode=driving';
    if (originLat != null && originLng != null) {
       googleMapsUrl += '&origin=$originLat,$originLng';
    }

    // Google Maps Intent for Android that explicitly starts Turn-by-Turn navigation
    final String nativeMapsUrl = 'google.navigation:q=$destLat,$destLng&mode=d';
    
    try {
      // For mobile, try native maps first
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
        final nativeUri = Uri.parse(nativeMapsUrl);
        if (await canLaunchUrl(nativeUri)) {
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
          return;
        }
      }
      
      // Fallback to browser for everything else (Web, Windows, or if native fails)
      final browserUri = Uri.parse(googleMapsUrl);
      await launchUrl(browserUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error opening navigation: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open navigation')),
        );
      }
    }
  }

  List<SafetyResource> get _filteredResources {
    return _allResources.where((res) {
      bool categoryMatch = _selectedCategory == 'All' || res.category == _selectedCategory;
      bool searchMatch = res.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          res.subtitle.toLowerCase().contains(_searchQuery.toLowerCase());
      return categoryMatch && searchMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 120), // Extra bottom padding for overflow and Nav bar
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildExpandableSection(
                  title: 'Safe Havens Nearby',
                  icon: Icons.location_on_outlined,
                  iconColor: const Color(0xFF2563EB),
                  content: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildSafePlacesList(),
                ),
                const SizedBox(height: 16),
                _buildExpandableSection(
                  title: 'Guides & Tutorials',
                  icon: Icons.book_outlined,
                  iconColor: Colors.purple,
                  content: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildGuidesGrid(),
                ),
                const SizedBox(height: 16),
                _buildExpandableSection(
                  title: 'Local Safety Reports',
                  icon: Icons.error_outline,
                  iconColor: Colors.orange,
                  content: _buildReportsList(),
                ),
                const SizedBox(height: 16),
                _buildExpandableSection(
                  title: 'Emergency Helplines',
                  icon: Icons.phone_outlined,
                  iconColor: Colors.green,
                  content: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildHelplinesList(),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 240,
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Safety Resources',
                style: GoogleFonts.dancingScript(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Knowledge and tools to stay prepared',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              const SizedBox(height: 24),
              _buildSearchInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Center(
        child: TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search resources...',
            hintStyle: GoogleFonts.inter(color: Colors.white.withOpacity(0.7), fontSize: 15),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget content,
    bool initiallyExpanded = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: iconColor, size: 24),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF1E293B),
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [content],
        ),
      ),
    );
  }

  Widget _buildSafePlacesList() {
    return Column(
      children: [
        if (_filteredResources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('No results found.', style: GoogleFonts.inter(color: Colors.grey)),
          ),
        ..._filteredResources.map((res) => InkWell(
          onTap: () {
            if (res.lat != null && res.lng != null) {
              _openNavigation(res.lat!, res.lng!);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(res.icon, color: res.iconColor, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(res.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Open Now',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF166534)),
                            ),
                          ),
                        ],
                      ),
                      Text(res.subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                const Icon(Icons.navigation_outlined, size: 24, color: Colors.blue),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildGuidesGrid() {
    return Column(
      children: _guides.map((guide) => InkWell(
        onTap: () async {
          if (guide.url != null && guide.url!.isNotEmpty) {
            final String urlString = guide.url!.trim();
            final Uri uri = Uri.parse(urlString);
            try {
              // On many platforms, canLaunchUrl returns false for https but launchUrl still works.
              // We'll attempt a launch and catch any failures.
              bool success = await launchUrl(
                uri,
                mode: LaunchMode.platformDefault,
              );
              
              if (!success) {
                // Try external application if default fails
                success = await launchUrl(uri, mode: LaunchMode.externalApplication);
              }

              if (!success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not open: ${guide.title}')),
                );
              }
            } catch (e) {
              debugPrint('Error launching URL: $e');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error opening link: $e')),
                );
              }
            }
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: guide.color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: guide.color.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Icon(guide.icon, color: guide.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  guide.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              const Icon(Icons.play_circle_outline, color: Colors.red, size: 20),
            ],
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildHelplinesList() {
    return Column(
      children: _helplines.map((h) => InkWell(
        onTap: () => _makePhoneCall(h.number),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(h.number, style: GoogleFonts.inter(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
              const Icon(Icons.call, color: Colors.green, size: 20),
            ],
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildReportsList() {
    return Column(
      children: _reports.map((r) {
        Color severityColor = r.severity == 'High' ? Colors.red : (r.severity == 'Medium' ? Colors.orange : Colors.blue);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: severityColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: severityColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('${r.location} • ${r.time}', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Text('${r.distance.toStringAsFixed(1)}km', style: TextStyle(fontSize: 11, color: severityColor, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
