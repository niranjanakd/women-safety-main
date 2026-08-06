import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class GuardingApiService {
  // Use same logic as main ApiService for baseUrl
  static String get baseUrl {
    // Live Render Backend
    return 'https://safetipin-backend.onrender.com/api/guarding';
  }

  // --- Device ID Management ---
  
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('guarding_device_id');
    
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString('guarding_device_id', deviceId);
    }
    return deviceId;
  }

  // --- API Methods ---

  // 1. Register Profile
  static Future<Map<String, dynamic>> registerProfile(String name, List<Map<String, String>> questions) async {
    final url = '$baseUrl/profile/register';
    final deviceId = await getOrCreateDeviceId();

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': deviceId,
          'name': name,
          'questions': questions
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {'success': true, 'message': data['message']};
      }
      
      try {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Error ${response.statusCode}'};
      } catch (_) {
        return {'success': false, 'message': 'Server error (${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // 2. Start Guarding Session
  static Future<Map<String, dynamic>> startGuarding(double? lat, double? lng) async {
    final url = '$baseUrl/guard/start';
    final deviceId = await getOrCreateDeviceId();

    try {
      final body = {'device_id': deviceId};
      if (lat != null && lng != null) {
        body['start_latitude'] = lat.toString(); 
        body['start_longitude'] = lng.toString();
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_guarding_session', data['session_id']);
        return {'success': true, 'session_id': data['session_id']};
      }

      try {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Error ${response.statusCode}'};
      } catch (_) {
        return {'success': false, 'message': 'Server error (${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // 3. Stop Guarding Session
  static Future<Map<String, dynamic>> stopGuarding(String sessionId, double? lat, double? lng) async {
    final url = '$baseUrl/guard/stop';

    try {
      final body = {'session_id': sessionId};
      if (lat != null && lng != null) {
        body['latitude'] = lat.toString();
        body['longitude'] = lng.toString();
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': data['message'] ?? 'Failed to stop guarding'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // 4. Update Location
  static Future<Map<String, dynamic>> updateLocation(String sessionId, double lat, double lng) async {
    final url = '$baseUrl/location/update';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'latitude': lat,
          'longitude': lng,
          'timestamp': DateTime.now().toIso8601String()
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }

      try {
        final data = jsonDecode(response.body);
        return {'success': false, 'message': data['message'] ?? 'Error ${response.statusCode}'};
      } catch (_) {
        return {'success': false, 'message': 'Server error (${response.statusCode})'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // 4. Trigger Emergency
  static Future<Map<String, dynamic>> triggerEmergency(String sessionId, double? lat, double? lng) async {
    final url = '$baseUrl/alert/emergency';

    try {
      final body = {'session_id': sessionId, 'timestamp': DateTime.now().toIso8601String()};
      if (lat != null && lng != null) {
        body['latitude'] = lat.toString();
        body['longitude'] = lng.toString();
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'alert_id': data['alert_id']};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // 5. Request Safe Verification
  static Future<Map<String, dynamic>> requestSafeVerification(String sessionId) async {
    final url = '$baseUrl/safe/request';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'challenge_id': data['challenge_id'], 'question': data['question']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // 6. Verify Safe Challenge
  static Future<Map<String, dynamic>> verifySafeChallenge(String challengeId, String answer) async {
    final url = '$baseUrl/safe/verify';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'challenge_id': challengeId, 'answer': answer}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        // Clear local session if successful
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('active_guarding_session');
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // 7. Create Share Link
  static Future<Map<String, dynamic>> createShareLink(String sessionId) async {
    final url = '$baseUrl/share/create';

    try {
       final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return {'success': true, 'token': data['token']};
      return {'success': false, 'message': data['message']};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }
}
