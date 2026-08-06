import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapRoutingService {
  static const String _apiKey = "AIzaSyCq5qIO6qWhwCaAbN6PdtgAGnHMX7VAEbQ";
  static const String _package = "com.safeguard.kerala.safeguard_kerala";
  static const String _cert = "DAC7F87887EB162A9947B071EE44C9B853D4037B";

  /// Fetches road-path coordinates between origin and destination.
  /// Returns an empty list if no route is found or an error occurs.
  static Future<List<LatLng>> getRoutePoints({
    required LatLng origin,
    required LatLng destination,
    String mode = 'walking',
    List<LatLng>? waypoints,
  }) async {
    try {
      String waypointsStr = "";
      if (waypoints != null && waypoints.isNotEmpty) {
        final wpStrings = waypoints.map((w) => "via:${w.latitude},${w.longitude}").join('|');
        waypointsStr = "&waypoints=$wpStrings";
      }

      String url = "https://maps.googleapis.com/maps/api/directions/json"
          "?origin=${origin.latitude},${origin.longitude}"
          "&destination=${destination.latitude},${destination.longitude}"
          "$waypointsStr"
          "&mode=$mode"
          "&key=$_apiKey";
      
      debugPrint("MAP_ROUTING_SERVICE: Requesting $url");

      final response = await http.get(
        Uri.parse(url),
        headers: {
          "X-Android-Package": _package,
          "X-Android-Cert": _cert,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];
        
        if (status == 'OK') {
          final routes = data['routes'];
          if (routes is List && routes.isNotEmpty) {
            final firstRoute = routes[0];
            final legs = firstRoute['legs'] as List?;
            
            if (legs != null && legs.isNotEmpty) {
              List<LatLng> allPoints = [];
              final steps = legs[0]['steps'] as List?;
              
              if (steps != null) {
                for (var step in steps) {
                  final poly = step['polyline']?['points'];
                  if (poly != null) {
                    allPoints.addAll(_decodePolyline(poly.toString()));
                  }
                }
              }
              
              if (allPoints.isNotEmpty) {
                 // Also add exact origin and destination for perfect anchoring
                 if (allPoints.first != origin) allPoints.insert(0, origin);
                 if (allPoints.last != destination) allPoints.add(destination);
                 return allPoints;
              }
            }
            
            // Fallback to overview if steps fail
            if (firstRoute.containsKey('overview_polyline')) {
              final polyline = firstRoute['overview_polyline'];
              if (polyline is Map && polyline.containsKey('points')) {
                return _decodePolyline(polyline['points'].toString());
              }
            }
          }
          throw Exception("No valid route data found in OK response");
        } else {
          final errorMsg = data['error_message'] ?? 'Check API key or restrictions';
          debugPrint("MAP_ROUTING_SERVICE ERROR: $status - $errorMsg");
          debugPrint("RAW RESPONSE: ${response.body}");
          throw Exception("Route Error: $status ($errorMsg)");
        }
      } else {
        debugPrint("MAP_ROUTING_SERVICE HTTP ERROR: ${response.statusCode}");
        debugPrint("RAW RESPONSE: ${response.body}");
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("MAP_ROUTING_SERVICE EXCEPTION: $e");
      rethrow; // Re-throw to be caught by the calling widget's catch block
    }
  }

  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble()));
    }
    return poly;
  }
}
