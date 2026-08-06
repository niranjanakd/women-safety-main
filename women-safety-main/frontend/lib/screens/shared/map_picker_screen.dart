import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';

class MapPickerScreen extends StatefulWidget {
  final List<dynamic>? frequentDestinations;
  const MapPickerScreen({super.key, this.frequentDestinations});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedLocation = const LatLng(10.0104, 76.3637); // Default to Kochi
  String _currentAddress = "Select a location on the map";
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();
      _selectedLocation = LatLng(position.latitude, position.longitude);
      
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(_selectedLocation, 15),
        );
      }
    } catch (e) {
      debugPrint('Error getting position: $e');
    }

    if (mounted) setState(() => _isLoading = false);
    _getAddressFromLatLng(_selectedLocation);
  }

  Future<void> _getAddressFromLatLng(LatLng position) async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _currentAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
        });
      }
      return;
    }

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        if (mounted) {
          setState(() {
            _currentAddress = "${place.name}, ${place.locality}, ${place.administrativeArea}";
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
      if (mounted) {
        setState(() {
          _currentAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
        });
      }
    }
  }

  Future<void> _searchAndNavigate() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus(); // Dismiss keyboard
    setState(() => _isSearching = true);

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newLatLng = LatLng(loc.latitude, loc.longitude);
        setState(() {
          _selectedLocation = newLatLng;
        });
        if (_mapController != null) {
           _mapController!.animateCamera(CameraUpdate.newLatLngZoom(newLatLng, 15));
        }
        await _getAddressFromLatLng(newLatLng);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No mapping found for this location.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed. Location might not exist or network issue.')));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Location', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _selectedLocation, zoom: 15),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onTap: (position) {
              setState(() => _selectedLocation = position);
              _getAddressFromLatLng(position);
            },
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _selectedLocation,
              ),
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          
          if (_isLoading || _isSearching)
            const Center(child: CircularProgressIndicator()),

          // Search Bar Overlay
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: "Search for a destination...",
                        border: InputBorder.none,
                        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                      ),
                      onSubmitted: (_) => _searchAndNavigate(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF7C3AED)),
                    onPressed: _searchAndNavigate,
                  ),
                ],
              ),
            ),
          ),

          // Search Suggestions (Frequent Destinations)
          if (_searchController.text.isNotEmpty || (widget.frequentDestinations != null && widget.frequentDestinations!.isNotEmpty))
            Positioned(
              top: 80,
              left: 20,
              right: 20,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: (widget.frequentDestinations ?? []).where((d) => 
                      _searchController.text.isEmpty || 
                      d['name'].toString().toLowerCase().contains(_searchController.text.toLowerCase())
                    ).length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final filteredList = (widget.frequentDestinations ?? []).where((d) => 
                        _searchController.text.isEmpty || 
                        d['name'].toString().toLowerCase().contains(_searchController.text.toLowerCase())
                      ).toList();
                      final destination = filteredList[index];
                      
                      return ListTile(
                        leading: const Icon(Icons.history, color: Color(0xFF94A3B8)),
                        title: Text(destination['name']?.toString() ?? destination['destinationName']?.toString() ?? "Saved Place", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        subtitle: Text(destination['address']?.toString() ?? "No address available", maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          // Robust coordinate extraction
                          double? lat, lng;
                          if (destination['latitude'] != null && destination['longitude'] != null) {
                            lat = (destination['latitude'] as num).toDouble();
                            lng = (destination['longitude'] as num).toDouble();
                          } else if (destination['location'] != null && 
                                     destination['location']['coordinates'] is List && 
                                     (destination['location']['coordinates'] as List).length >= 2) {
                            final coords = destination['location']['coordinates'] as List;
                            lng = (coords[0] as num).toDouble();
                            lat = (coords[1] as num).toDouble();
                          }

                          if (lat != null && lng != null) {
                            Navigator.pop(context, {
                              'address': destination['address']?.toString() ?? destination['name']?.toString() ?? "Selected Location",
                              'lat': lat,
                              'lng': lng,
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Error: Invalid coordinates for this saved place."))
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton(
                  onPressed: _determinePosition,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.my_location, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentAddress,
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, {
                              'address': _currentAddress,
                              'lat': _selectedLocation.latitude,
                              'lng': _selectedLocation.longitude,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Confirm Location', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
