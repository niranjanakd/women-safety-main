import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/background_guarding_service.dart';
import '../../services/guarding_api_service.dart';
import '../../services/api_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as Math;
import '../sos/active_sos_screen.dart';
import '../sos/fake_call_screen.dart';
import '../shared/map_picker_screen.dart';
import 'package:perfect_volume_control/perfect_volume_control.dart';
import '../../services/location_service.dart';
import '../../services/map_routing_service.dart';

class GuardingModeScreen extends StatefulWidget {
  const GuardingModeScreen({super.key});

  @override
  State<GuardingModeScreen> createState() => _GuardingModeScreenState();
}

class _GuardingModeScreenState extends State<GuardingModeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isGuarding = false;
  int _secondsElapsed = 0;
  int _safetyCheckCount = 0; // Tracks how many persistent failures
  Timer? _safetyTimer; // Timer for the 60s response window
  bool _isCheckingSafety = false;
  Timer? _timer;
  String _currentAddress = "Detecting location...";
  double? _lat;
  double? _lng;

  late AnimationController _pulseController;

  String _currentDestinationInput = "";

  double? _destinationLat;
  double? _destinationLng;
  StreamSubscription<Position>? _positionStream;
  late TextEditingController _destinationController;

  bool _hasEnteredTracking = false;

  // Frequent places

  // Map state
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _routePoints = [];
  List<LatLng> _historyPath = [];
  List<Map<String, dynamic>> _incidents = [];
  List<dynamic> _frequentDestinations = [];
  bool _isPathUnsafe = false;
  String _backgroundHeardWords = "";

  // Advanced Triggers State
  String _sosTriggerWord = "red"; // Default
  int _volumeClickCount = 0;
  DateTime? _lastVolumeClick;
  StreamSubscription<double>? _volumeSubscription;
  String _travelMode = 'walking'; // driving, walking, two_wheeler
  bool _isAppInForeground = true;

  @override
  void initState() {
    super.initState();
    _destinationController = TextEditingController(); // Initialize here
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _checkInitialState();
    _fetchIncidents();
    _initAdvancedTriggers();
    _fetchSosTriggerWord();
    _setupGlobalLocationListener();
    WidgetsBinding.instance.addObserver(this);
  }

  void _setupGlobalLocationListener() {
    LocationService().addListener(_onLocationUpdate);
    // Initial sync
    if (LocationService().currentPosition != null) {
      _onLocationUpdate();
    }
  }

  void _onLocationUpdate() {
    final pos = LocationService().currentPosition;
    if (pos == null) return;

    if (mounted) {
      bool wasLatNull = _lat == null;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        
        final newPoint = LatLng(pos.latitude, pos.longitude);
        if (_historyPath.isEmpty || _calculateDistance(_historyPath.last.latitude, _historyPath.last.longitude, newPoint.latitude, newPoint.longitude) > 2) {
           _historyPath.add(newPoint);
        }

        // Optionally update address less frequently to save battery/quota
        _updateAddressFromCoords(pos.latitude, pos.longitude);
      });
      _updateMapState();
      
      // SYNC TO BACKEND
      if (_isGuarding) {
        SharedPreferences.getInstance().then((prefs) {
          final sessionId = prefs.getString('active_guarding_session');
          if (sessionId != null && sessionId != 'local_offline_session') {
            GuardingApiService.updateLocation(sessionId, pos.latitude, pos.longitude);
          }
        });
      }

      // 4. Trigger route fetch if we had a loaded destination but were waiting for GPS lock
      if (wasLatNull && _destinationLat != null) {
        _fetchDirections();
      }

      // 5. Auto-Arrival Detection
      if (_isGuarding && _destinationLat != null && _destinationLng != null) {
        double distance = _calculateDistance(_lat!, _lng!, _destinationLat!, _destinationLng!);
        if (distance < 20) {
          _stopGuardingLocally();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Arrived at destination. Guarding mode deactivated."),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _updateAddressFromCoords(double lat, double lng) async {
     // We'll throttle this or only do it if moved significantly in future
     try {
       List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
       if (placemarks.isNotEmpty && mounted) {
         Placemark place = placemarks[0];
         setState(() {
           _currentAddress = "${place.name}, ${place.locality}, ${place.administrativeArea}";
         });
       }
     } catch (e) {
       debugPrint("Address update error: $e");
     }
  }

  Future<void> _fetchSosTriggerWord() async {
    final result = await ApiService.getProfile();
    if (result['success']) {
      setState(() {
        _sosTriggerWord = result['data']['sosTriggerWord']?.toLowerCase() ?? "help";
        _frequentDestinations = result['data']['destinations'] ?? [];
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_sos_trigger_word', _sosTriggerWord);
    }
  }

  void _initAdvancedTriggers() {
    // 1. Volume Button Clicks
    _volumeSubscription = PerfectVolumeControl.stream.listen((volume) {
      _handleVolumePattern();
    });

    // 2. Background Voice Events
    final service = FlutterBackgroundService();
    service.on('voice_result').listen((event) {
      if (event != null && event['words'] != null) {
        if (mounted) {
          setState(() {
            _backgroundHeardWords = event['words'];
          });
        }
        
        // Clear after a short delay of silence
        Timer(const Duration(seconds: 4), () {
          if (mounted && _backgroundHeardWords == event['words']) {
            setState(() {
              _backgroundHeardWords = "";
            });
          }
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isAppInForeground = (state == AppLifecycleState.resumed);
    });
    debugPrint("GuardingMode lifecycle: $state, isForeground: $_isAppInForeground");
  }

  void _handleVolumePattern() {
    if (!_isAppInForeground) return; // Prevent triggering from background
    
    final now = DateTime.now();
    if (_lastVolumeClick == null || now.difference(_lastVolumeClick!) > const Duration(seconds: 3)) {
      _volumeClickCount = 1;
    } else {
      _volumeClickCount++;
    }
    _lastVolumeClick = now;

    if (_volumeClickCount >= 3) {
      _volumeClickCount = 0;
      _triggerManualSOS();
    }
  }

  LatLng? _saferWaypoint;

  Timer? _incidentPollTimer;
  bool _warnedAboutNewIncident = false;

  Future<void> _fetchIncidents() async {
    try {
      final result = await ApiService.getMapIncidents();
      if (result['success']) {
        final newIncidents = List<Map<String, dynamic>>.from(result['data']['data'] ?? []);
        
        // Check if any NEW incidents affect our path
        if (_isGuarding && _destinationLat != null && _destinationLng != null) {
          final userPos = LatLng(_lat!, _lng!);
          final destPos = LatLng(_destinationLat!, _destinationLng!);
          bool wasUnsafe = _isPathUnsafe;
          
          // Temporary update to check proximity
          _incidents = newIncidents;
          bool isNowUnsafe = _checkPathProximity(userPos, destPos);
          
          if (isNowUnsafe && !wasUnsafe && !_warnedAboutNewIncident) {
            _showSafetyWarning("New Emergency Reported Near Your Path!");
            _warnedAboutNewIncident = true;
          }
        }

        setState(() {
          _incidents = newIncidents;
        });
        _updateMapState();
      }
    } catch (e) {
      debugPrint("Error fetching incidents: $e");
    }
  }

  void _showSafetyWarning(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'DETOUR',
          textColor: Colors.white,
          onPressed: () {
            _updateMapState(); // Force recalculation and waypoint
          },
        ),
      ),
    );
  }

  Future<void> _checkInitialState() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if already guarding in background
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();

    // Check if we have an active session saved
    String? sessionId = prefs.getString('active_guarding_session');

    if (isRunning && sessionId != null) {
      _currentDestinationInput =
          prefs.getString('active_destination_name') ?? "";
      _destinationController.text = _currentDestinationInput;
      double? savedLat = prefs.getDouble('active_destination_lat');
      double? savedLng = prefs.getDouble('active_destination_lng');
      if (savedLat != null && savedLng != null) {
        _destinationLat = savedLat;
        _destinationLng = savedLng;
        _fetchDirections();
      }

      setState(() {
        _isGuarding = true;
        _hasEnteredTracking = true; // Auto-skip intro if already active
        _pulseController.repeat();
        // Fallback timer visual
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _secondsElapsed++;
          });
        });
        
        // Start polling for incidents every 30 seconds
        _incidentPollTimer?.cancel();
        _incidentPollTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
          _fetchIncidents();
        });
      });
      _startLocationStream();
    }

    _detectLocation();
  }


  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    _safetyTimer?.cancel();
    _destinationController.dispose();
    _positionStream?.cancel();
    _volumeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _detectLocation() async {
    final pos = LocationService().currentPosition;
    if (pos != null && mounted) {
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      _updateMapState();
    }
  }

  void _updateMapState() {
    if (_lat == null || _lng == null) return;

    final userPos = LatLng(_lat!, _lng!);
    final destPos = (_destinationLat != null && _destinationLng != null)
        ? LatLng(_destinationLat!, _destinationLng!)
        : null;

    setState(() {
      _markers.clear();
      _markers.add(Marker(
        markerId: const MarkerId('user'),
        position: userPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));

      if (destPos != null) {
        _polylines.clear(); // Clear all polylines before adding new ones
        _markers.add(Marker(
          markerId: const MarkerId('destination'),
          position: destPos,
          icon: BitmapDescriptor.defaultMarker,
        ));

        _isPathUnsafe = _checkPathProximity(userPos, destPos);
        
        if (_saferWaypoint != null) {
          _markers.add(Marker(
            markerId: const MarkerId('safer_waypoint'),
            position: _saferWaypoint!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: const InfoWindow(
              title: 'Safety Haven',
              snippet: 'A recommended safer point to deviate towards',
            ),
          ));
        }
        
        // Draw Road Path
        if (_routePoints.isNotEmpty) {
           List<LatLng> finalPoints = List.from(_routePoints);
           // Ensure path starts exactly at user location for "perfect" drawing
           if (finalPoints.isNotEmpty) {
             finalPoints[0] = userPos;
           }

           _polylines.add(Polyline(
             polylineId: const PolylineId('path_road'),
             points: finalPoints,
             color: _isPathUnsafe ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
             width: 6,
          ));
        }

        // Live Movements Trail (Breadcrumb)
        if (_historyPath.isNotEmpty) {
           _polylines.add(Polyline(
             polylineId: const PolylineId('history_trail'),
             points: _historyPath,
             color: const Color(0xFF94A3B8).withOpacity(0.6),
             width: 4,
             patterns: [PatternItem.dot, PatternItem.gap(10)],
           ));
        }
      } else {
        _polylines.clear();
      }

      // Incident markers removed per user request to keep UI clean
    });

    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: userPos,
        zoom: destPos != null ? 16.0 : 15.0,
        tilt: 0.0, // Reduced tilt for better overview
      )));
    }
  }

  bool _checkPathProximity(LatLng start, LatLng end) {
    if (_incidents.isEmpty) return false;

    for (var incident in _incidents) {
      final loc = incident['location']?['coordinates'];
      if (loc != null && loc.length >= 2) {
        final incidentPos = LatLng(loc[1].toDouble(), loc[0].toDouble());
        double dist = _distanceToSegment(incidentPos, start, end);
        
        // If within ~500 meters of an incident, or ~1km for SOS
        bool isSOS = incident['type'] == 'SOS Alert';
        double threshold = isSOS ? 0.01 : 0.005; // ~1km for SOS, ~500m for others
        
        if (dist < threshold) {
          return true;
        }
      }
    }
    return false;
  }

  double _distanceToSegment(LatLng p, LatLng a, LatLng b) {
    double l2 = _distSq(a, b);
    if (l2 == 0) return _distSq(p, a);
    double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) +
                (p.longitude - a.longitude) * (b.longitude - a.longitude)) / l2;
    t = t.clamp(0, 1);
    return Math.sqrt(_distSq(p, LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude)
    )));
  }

  double _distSq(LatLng v, LatLng w) {
    return (v.latitude - w.latitude) * (v.latitude - w.latitude) +
           (v.longitude - w.longitude) * (v.longitude - w.longitude);
  }

  Future<void> _fetchDirections() async {
    if (_lat == null || _lng == null || _destinationLat == null || _destinationLng == null) {
      debugPrint("DIRECTIONS SKIP: Missing coordinates. User: $_lat,$_lng Dest: $_destinationLat,$_destinationLng");
      return;
    }
    
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text("Fetching real road path..."), duration: Duration(seconds: 1)),
        );
      }

      final userPos = LatLng(_lat!, _lng!);
      final destPos = LatLng(_destinationLat!, _destinationLng!);
      
      _isPathUnsafe = _checkPathProximity(userPos, destPos);
      _saferWaypoint = _isPathUnsafe ? _calculateSaferWaypoint(userPos, destPos) : null;

      final coords = await MapRoutingService.getRoutePoints(
        origin: userPos,
        destination: destPos,
        mode: _travelMode,
        waypoints: _saferWaypoint != null ? [_saferWaypoint!] : null,
      );

      if (coords.isNotEmpty) {
        debugPrint("DIRECTIONS SUCCESS: Decoded ${coords.length} road points.");
        if (mounted) {
          setState(() {
            _routePoints = coords;
          });
          _updateMapState();
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text("Road path loaded!"), backgroundColor: Colors.blue, duration: Duration(seconds: 1)),
          );

          // Sync the road path to TravelSession so trusted contacts can see it on their map
          final prefs = await SharedPreferences.getInstance();
          final travelSessionId = prefs.getString('active_travel_session_id');
          if (travelSessionId != null) {
            ApiService.updateTravelRoutePoints(
              travelSessionId,
              coords.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
            ).catchError((e) {
              debugPrint('Route sync error: $e');
              return <String, dynamic>{'success': false};
            });
          }
        }
      } else {
        debugPrint("DIRECTIONS: No results for mode $_travelMode");
        if (mounted) {
          if (_travelMode == 'bicycling') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Preferred path unavailable in this area. Falling back to walking."),
                backgroundColor: Colors.orange,
              ),
            );
            setState(() {
              _travelMode = 'walking';
            });
            _fetchDirections(); // Retry with walking
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No road path found for this destination."), backgroundColor: Colors.orange),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching directions: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("Network Error fetching route: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  LatLng _calculateSaferWaypoint(LatLng start, LatLng end) {
    // Find the incident most interfering with the path
    Map<String, dynamic>? badIncident;
    double minSegDist = double.infinity;

    for (var incident in _incidents) {
      final loc = incident['location']?['coordinates'];
      if (loc != null && loc.length >= 2) {
        final incidentPos = LatLng(loc[1].toDouble(), loc[0].toDouble());
        double dist = _distanceToSegment(incidentPos, start, end);
        if (dist < minSegDist) {
          minSegDist = dist;
          badIncident = incident;
        }
      }
    }

    if (badIncident == null) return LatLng((start.latitude + end.latitude) / 2, (start.longitude + end.longitude) / 2);

    final incLoc = badIncident['location']['coordinates'];
    final LatLng incPos = LatLng(incLoc[1].toDouble(), incLoc[0].toDouble());

    // Midpoint of current path
    double midLat = (start.latitude + end.latitude) / 2;
    double midLng = (start.longitude + end.longitude) / 2;

    // Vector from incident to midpoint
    double dy = midLat - incPos.latitude;
    double dx = midLng - incPos.longitude;
    double len = Math.sqrt(dx * dx + dy * dy);
    
    // Push away from incident by ~1km (0.01 degrees roughly)
    double pushDist = 0.01;
    if (len > 0) {
      return LatLng(midLat + (dy / len) * pushDist, midLng + (dx / len) * pushDist);
    } else {
      // If incident is exactly on midpoint, push perpendicular to path
      double vX = end.latitude - start.latitude;
      double vY = end.longitude - start.longitude;
      return LatLng(midLat - vY * 0.1, midLng + vX * 0.1);
    }
  }

  void _triggerManualSOS() async {
    // 1. Ensure we have location
    if (_lat == null || _lng == null) {
      await _detectLocation();
      if (_lat == null || _lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cannot trigger SOS without location access.")),
        );
        return;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Call Backend API
    final result = await ApiService.triggerSOS(_currentAddress, _lat!, _lng!);
    
    if (!mounted) return;
    Navigator.pop(context); // Pop loading

    Map<String, dynamic> alertData;
    if (result['success']) {
      alertData = result['data'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? "SOS Triggered Successfully"),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Offline or error - generate a local dummy ID as fallback
      final String localAlertId = "local_sos_${DateTime.now().millisecondsSinceEpoch}";
      alertData = {
        '_id': localAlertId,
        'type': 'Emergency',
        'status': 'active',
        'isLocalOnly': true, // Add flag to indicate it didn't hit backend
      };
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Triggered SOS locally. Error syncing with server: ${result['message']}"),
          backgroundColor: Colors.orange,
        ),
      );
    }

    // 2. Navigate to Active SOS Screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ActiveSOSScreen(
          initialAlert: alertData,
        ),
      ),
    );
  }

  void _toggleGuarding() async {
    if (_isGuarding) {
      // STOPPING LOGIC: Show confirmation dialog first
      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Stop Guarding?", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Text("Are you sure you want to stop guarding mode? This will deactivate your safety tracking."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel", style: GoogleFonts.inter(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text("Stop", style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        _stopGuardingLocally();
        _incidentPollTimer?.cancel();
      }
    } else {
      // STARTING LOGIC
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );


      // Offline Start Guarding Delay
      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      Navigator.pop(context);

      final service = FlutterBackgroundService();
      await initializeBackgroundService();
      service.invoke("setAsForeground");

      // LOG START TO BACKEND
      final prefs = await SharedPreferences.getInstance();
      String sessionId = 'local_offline_session';
      try {
        // 1. Register/Sync Profile first (links device to user and syncs safety questions)
        final List<Map<String, String>> questions = [];
        for (int i = 0; i < 5; i++) {
          final q = prefs.getString('guarding_q_$i');
          final a = prefs.getString('guarding_a_$i');
          if (q != null && a != null) {
            questions.add({'question': q, 'answer': a});
          }
        }
        
        final userName = prefs.getString('user_name') ?? "User";
        await GuardingApiService.registerProfile(userName, questions);

        // 2. Start Guarding Session
        final startResult = await GuardingApiService.startGuarding(_lat, _lng);
        if (startResult['success']) {
          sessionId = startResult['session_id'];
          // 3. ALSO START TRAVEL SESSION FOR DASHBOARD
          final travelResult = await ApiService.startTravelSession(
            _currentDestinationInput.isNotEmpty ? _currentDestinationInput : "Traveling",
            _lat ?? 0.0,
            _lng ?? 0.0,
            routePoints: _routePoints.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
          );
          if (travelResult['success']) {
            await prefs.setString('active_travel_session_id', travelResult['data']['_id']);
            if (travelResult['data']['shareToken'] != null) {
              await prefs.setString('active_travel_share_token', travelResult['data']['shareToken']);
            }
          }
        }
      } catch (e) {
        debugPrint("Error logging start: $e");
      }

      await prefs.setString('active_guarding_session', sessionId);

      if (_currentDestinationInput.isNotEmpty) {
        await prefs.setString(
        'active_destination_name',
        _currentDestinationInput,
        );
        if (_destinationLat != null && _destinationLng != null) {
        await prefs.setDouble('active_destination_lat', _destinationLat!);
        await prefs.setDouble('active_destination_lng', _destinationLng!);
        }
      } else {
        await prefs.remove('active_destination_name');
        await prefs.remove('active_destination_lat');
        await prefs.remove('active_destination_lng');
      }

      setState(() {
        _isGuarding = true;
        _hasEnteredTracking = true; // Ensure they are in the tracking UI once activated
        _secondsElapsed = 0;
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _secondsElapsed++;
            // Trigger safety check every 5 minutes (300 seconds)
            if (_secondsElapsed > 0 && _secondsElapsed % 300 == 0) {
              _triggerSafetyCheck();
            }
          });
        });
        _pulseController.repeat();
      });

      _startLocationStream();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
        content: Text('Guarding Mode Activated (Offline)'),
        backgroundColor: Colors.green,
        ),
      );
    }
  }


  void _triggerSafetyCheck() {
    if (_isCheckingSafety) return; // Already showing

    setState(() {
      _isCheckingSafety = true;
    });

    // Notify backend that we are checking safety (mutual exclusion)
    SharedPreferences.getInstance().then((prefs) {
      String? travelSessionId = prefs.getString('active_travel_session_id');
      if (travelSessionId != null) {
        ApiService.updateTravelSessionStatus(travelSessionId, 'checking');
      }
    });

    // Start 60s countdown for escalation
    _safetyTimer = Timer(const Duration(seconds: 60), () {
      _handleSafetyFailure();
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF3B82F6)),
            const SizedBox(width: 10),
            Text("Safety Check", style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "It's been 5 minutes. Are you safe? Please confirm to prevent alerts.",
          style: GoogleFonts.inter(color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              _safetyTimer?.cancel();
              
              // Verify on backend
              final prefs = await SharedPreferences.getInstance();
              String? travelSessionId = prefs.getString('active_travel_session_id');
              if (travelSessionId != null) {
                await ApiService.verifyTravelCheckIn(travelSessionId);
              }

              setState(() {
                _isCheckingSafety = false;
                _safetyCheckCount = 0; // Reset on success
              });
              if (mounted) Navigator.pop(context);
            },
            child: Text(
              "I'M SAFE",
              style: GoogleFonts.inter(
                color: const Color(0xFF22C55E),
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSafetyFailure() async {
    _safetyCheckCount++;
    
    // Auto-close the dialog if still up
    if (_isCheckingSafety) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {
        _isCheckingSafety = false;
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_safetyCheckCount == 1 
          ? "Alerting Trusted Contacts..." 
          : "CRITICAL: Alerting Volunteers..."),
        backgroundColor: Colors.redAccent,
      ),
    );

    if (_safetyCheckCount == 1) {
      // Stage 1: Notify trusted contacts about the missed check-in
      await ApiService.alertTrustedContacts(_lat ?? 0.0, _lng ?? 0.0, "Safety Check Missed");
      
      // Update travel session status on dashboard
      final prefs = await SharedPreferences.getInstance();
      final travelSessionId = prefs.getString('active_travel_session_id');
      if (travelSessionId != null) {
        await ApiService.updateTravelSessionStatus(travelSessionId, 'missed-checkin');
      }
      
      // Schedule next safety check in 5 min for 2nd chance
      _triggerSafetyCheck();
    } else {
      // Stage 2: 2 consecutive misses → trigger SOS automatically
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("CRITICAL: Activating SOS after 2 missed check-ins!"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      _triggerManualSOS();
    }
  }

  void _stopGuardingLocally() async {
    final service = FlutterBackgroundService();
    service.invoke("stopService");

    _positionStream?.cancel();

    final prefs = await SharedPreferences.getInstance();
    String? sessionId = prefs.getString('active_guarding_session');

    // LOG STOP TO BACKEND
    if (sessionId != null && sessionId != 'local_offline_session') {
      try {
        await GuardingApiService.stopGuarding(sessionId, _lat, _lng);
      } catch (e) {
        debugPrint("Error logging stop: $e");
      }
    }

    // STOP TRAVEL SESSION
    String? travelSessionId = prefs.getString('active_travel_session_id');
    if (travelSessionId != null) {
      try {
        await ApiService.stopTravelSession(travelSessionId);
        await prefs.remove('active_travel_session_id');
      } catch (e) {
        debugPrint("Error stopping travel session: $e");
      }
    }

    await prefs.remove('active_destination_name');
    await prefs.remove('active_destination_lat');
    await prefs.remove('active_destination_lng');
    await prefs.remove('active_guarding_session'); 

    setState(() {
      _isGuarding = false;
      _hasEnteredTracking = false; // Go back to intro screen when stopped
      _timer?.cancel();
      _safetyTimer?.cancel();
      _isCheckingSafety = false;
      _safetyCheckCount = 0;
      _pulseController.stop();
      _pulseController.reset();
      _destinationLat = null;
      _destinationLng = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Guarding Mode Deactivated'),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final c = Math.cos;
    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p)) / 2;
    return 12742 * Math.asin(Math.sqrt(a)) * 1000; // Distance in meters
  }

  /// Listens to device location and pushes updates to the backend every 15 seconds.
  void _startLocationStream() {
    Duration _minPushInterval = const Duration(seconds: 15);
    DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

    LocationService().locationStream.listen((Position? position) async {
      if (!mounted || position == null) return;

      // Update local state only — do NOT call _updateMapState() here.
      // The route path is set by _fetchDirections() and should not be
      // overwritten on every GPS tick (which would show a partial/straight line).
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });

      // Throttle: push to backend at most every 15 seconds
      final now = DateTime.now();
      if (now.difference(_lastPush) < _minPushInterval) return;
      _lastPush = now;

      // Push live location to TravelSession so trusted contacts see it
      final prefs = await SharedPreferences.getInstance();
      final travelSessionId = prefs.getString('active_travel_session_id');
      if (travelSessionId != null) {
        ApiService.updateTravelLocation(
          travelSessionId,
          position.latitude,
          position.longitude,
        ).catchError((e) {
          debugPrint('Location push error: $e');
          return <String, dynamic>{'success': false};
        });
      }
    });
  }

  void _shareLocation() async {
    final prefs = await SharedPreferences.getInstance();
    String? sessionId = prefs.getString('active_guarding_session');

    if (sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please start a Guarding Session first to share your location.",
          ),
        ),
      );
      return;
    }

    String? shareToken = prefs.getString('active_travel_share_token');
    if (shareToken == null) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tracking link not available. Try restarting session.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;
    Navigator.pop(context); // close loading

    // Use the backend base URL (removing /api suffix) to point to the track.html
    String serverBase = ApiService.baseUrl.replaceAll('/api', '');
    String url = "$serverBase/track.html?token=$shareToken";
    
    Share.share(
      "🛡️ Track my live location for safety here: $url\n\nI'm guarded by Safeguard Kerala.",
      subject: "Live Location Tracking"
    );
  }

  void _triggerFakeEvent(String type) {
    if (type == 'Simulated Call') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FakeCallScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Incoming $type... (Simulator)"),
          backgroundColor: Colors.purple,
        ),
      );
    }
  }


  String get formattedTime {
    final minutes = (_secondsElapsed ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsElapsed % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F2FA), Color(0xFFDFEEF7), Color(0xFFE2F0EA)],
          ),
        ),
        child: SafeArea(
          child: !_hasEnteredTracking ? _buildIntroScreen() : _buildTrackingUI(),
        ),
      ),
    );
  }

  Widget _buildIntroScreen() {
    return Column(
      children: [
        // Top Header
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guarding Mode',
                    style: GoogleFonts.inter(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    _currentAddress,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Always show Voice SOS Status as a permanent safety layer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF0EA5E9)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded, size: 12, color: Color(0xFF0EA5E9)),
                        const SizedBox(width: 4),
                        Text(
                          "Voice SOS: Always-On (\"$_sosTriggerWord\")",
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0369A1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isGuarding && _backgroundHeardWords.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        "Heard: \"$_backgroundHeardWords\"",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),

        const Spacer(),
        // Centered Icon
        const SizedBox(
          height: 200,
          child: Center(
            child: Icon(
              Icons.location_on,
              size: 80,
              color: Color(0xFF1E50FF),
            ),
          ),
        ),
        const Spacer(),

        // Bottom "Start" button
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: GestureDetector(
            onTap: () {
              if (!_isGuarding) {
                _toggleGuarding();
              } else {
                setState(() {
                  _hasEnteredTracking = true;
                });
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFF1E293B),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Start Guarding",
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingUI() {
    return Stack(
      children: [
        // 1. Full Screen Map
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80), // Space for floating header
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      children: [
                        if (_lat != null && _lng != null)
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(_lat!, _lng!),
                              zoom: 15,
                            ),
                            onMapCreated: (controller) {
                              _mapController = controller;
                              _updateMapState();
                            },
                            markers: _markers,
                            polylines: _polylines,
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            compassEnabled: false,
                          )
                        else
                          Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                        
                        // Safer Path Warning Overlay
                        if (_isPathUnsafe)
                          Positioned(
                            top: 16,
                            left: 16,
                            right: 16,
                            child: _buildPathWarningOverlay(),
                          ),
                          
                        // My Location Button
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: FloatingActionButton.small(
                            heroTag: 'my_location_btn',
                            onPressed: _updateMapState,
                            backgroundColor: Colors.white,
                            child: const Icon(Icons.my_location, color: Color(0xFF1E293B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Bottom Spacing for Status/Actions
              const SizedBox(height: 250),
            ],
          ),
        ),

        // 2. Floating Header Overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFE8F2FA).withOpacity(0.9),
                  const Color(0xFFE8F2FA).withOpacity(0.0),
                ],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Guarding Mode',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        _currentAddress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                _buildActiveBadge(),
              ],
            ),
          ),
        ),

        // 3. Floating Status and Actions at the Bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mini Status Cards Row
                Row(
                  children: [
                    Expanded(child: _buildMiniStatusCard(Icons.access_time, "Timer", formattedTime)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDestination,
                        child: _buildMiniStatusCard(Icons.location_on_outlined, "Target", _currentDestinationInput.isNotEmpty ? _currentDestinationInput : "Pick Dest"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildTransportModeSelector(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: _buildMiniActionBtn(Icons.share_outlined, _shareLocation)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildMiniActionBtn(Icons.phone_forwarded_outlined, () => _triggerFakeEvent('Simulated Call'))),
                          const SizedBox(width: 8),
                          Expanded(child: _buildMiniActionBtn(Icons.security, _isCheckingSafety ? () {} : null, color: const Color(0xFF22C55E))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildStopBtn(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatusCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: const Color(0xFF3B82F6)),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniActionBtn(IconData icon, VoidCallback? onTap, {Color color = const Color(0xFF3B82F6)}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildStopBtn() {
    return GestureDetector(
      onTap: _toggleGuarding,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          "Stop Guarding",
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: const Color(0xFFB91C1C),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveBadge() {
     return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF4ADE80).withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4ADE80), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield, color: Color(0xFF166534), size: 14),
          const SizedBox(width: 4),
          Text(
            "Active",
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF166534)),
          ),
        ],
      ),
    );
  }

  Widget _buildPathWarningOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("High Incident Area", style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                Text("Safer detour suggested", style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDestination() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(
          frequentDestinations: _frequentDestinations,
        ),
      ),
    );
    if (result != null && result is Map) {
      setState(() {
        _currentDestinationInput = result['address']?.toString() ?? "Destination";
        _destinationController.text = _currentDestinationInput;
        _destinationLat = (result['lat'] as num?)?.toDouble();
        _destinationLng = (result['lng'] as num?)?.toDouble();
        _routePoints.clear(); 
      });
      _fetchDirections();
      _updateMapState();
    }
  }


  // Removed _buildSuggestionItem as it is no longer used
  Widget _buildTransportModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTransportModeItem('walking', Icons.directions_walk),
          _buildTransportModeItem('two_wheeler', Icons.motorcycle),
          _buildTransportModeItem('driving', Icons.directions_car),
        ],
      ),
    );
  }

  Widget _buildTransportModeItem(String mode, IconData icon) {
    bool isSelected = _travelMode == mode;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _travelMode = mode;
            _routePoints.clear();
          });
          _fetchDirections();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? const Color(0xFF1E50FF) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}
