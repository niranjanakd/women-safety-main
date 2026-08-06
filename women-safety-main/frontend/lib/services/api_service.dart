import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

class ApiService {
  static String get baseUrl {
    // Live Render Backend
    return 'https://safetipin-backend.onrender.com/api';
  }

  // Helper to get token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // --- AUTH APIs ---

  // Register (Direct)
  static Future<Map<String, dynamic>> register({
    required Map<String, dynamic> userData,
    String? otp,
  }) async {
    final url = '$baseUrl/auth/register';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userData': userData,
              if (otp != null) 'otp': otp,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (data['token'] != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', data['token']);
          await prefs.setString('user_id', data['_id']);
          await prefs.setString('user_role', data['role']);
          await prefs.setString('user_name', data['name']);
          if (data['gender'] != null) {
            await prefs.setString('user_gender', data['gender']);
          }
        }
        return {
          'success': true,
          'data': data,
          'isPendingApproval': data['isPendingApproval'] ?? false,
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Registration failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // Send OTP
  static Future<Map<String, dynamic>> sendOtp({
    required String phone,
    Map<String, dynamic>? userData,
  }) async {
    final url = '$baseUrl/auth/send-otp';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              if (userData != null) 'userData': userData,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': 'OTP sent successfully'};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to send OTP',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // Phase 2: Verify OTP
  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    // Password is sent to verify identity during login, or as an extra layer if required
    String? password,
  }) async {
    final url = '$baseUrl/auth/verify-otp';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'otpCode': otp,
              if (password != null) 'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('user_id', data['_id']);
        await prefs.setString('user_role', data['role']);
        await prefs.setString('user_name', data['name']);
        if (data['gender'] != null) {
          await prefs.setString('user_gender', data['gender']);
        }
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Verification failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // Password Login with OTP 2FA
  static Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
    String? otp,
  }) async {
    final url = '$baseUrl/auth/login';
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone, 
              'password': password,
              if (otp != null) 'otp': otp,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200 && data['requiresOtp'] == true) {
        return {'success': true, 'requiresOtp': true, 'message': data['message']};
      }

      if (response.statusCode == 200) {
        // ... (saves prefs)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['token']);
        await prefs.setString('user_id', data['_id']);
        await prefs.setString('user_role', data['role']);
        await prefs.setString('user_name', data['name']);
        if (data['gender'] != null) {
          await prefs.setString('user_gender', data['gender']);
        }
        return {'success': true, 'data': data};
      }

      if (response.statusCode == 403 && data['isPendingApproval'] == true) {
        return {
          'success': true,
          'isPendingApproval': true,
          'message': data['message'],
        };
      }

      return {'success': false, 'message': data['message'] ?? 'Login failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // Logout
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_role');

    // Stop Safety Service on logout
    final service = FlutterBackgroundService();
    var isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke("stopService");
    }
  }

  // Get Profile
  static Future<Map<String, dynamic>> getProfile() async {
    final url = '$baseUrl/user/profile';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to load profile',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // --- PROFILE & SETTINGS APIs ---

  // Update Profile

  // Send OTP for Profile Update
  static Future<Map<String, dynamic>> sendProfileUpdateOtp() async {
    final url = '$baseUrl/user/send-profile-update-otp';
    final token = await getToken();
    if (token == null) return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      }
      return {'success': false, 'message': data['message'] ?? 'Failed to send OTP'};
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> data, {
    String? otp,
  }) async {
    final url = '$baseUrl/user/update-profile';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final Map<String, dynamic> bodyData = Map<String, dynamic>.from(data);
      if (otp != null) bodyData['otp'] = otp;

      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(bodyData),
          )
          .timeout(const Duration(seconds: 15));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message': result['message'] ?? 'Failed to update profile',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Upload Profile Photo
  static Future<Map<String, dynamic>> uploadProfilePhoto(
    Uint8List bytes,
    String fileName,
  ) async {
    final url = '$baseUrl/user/profile/photo';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      print('--- Starting Photo Upload ---');
      print('URL: $url');
      print('Bytes size: ${bytes.length}');
      print('File name: $fileName');

      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';

      var multipartFile = http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: fileName,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      print('Sending request...');
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 20),
      );
      print('Response received: ${streamedResponse.statusCode}');

      var response = await http.Response.fromStream(streamedResponse);
      print('Body: ${response.body}');

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message':
            result['message'] ?? 'Upload failed (${response.statusCode})',
      };
    } catch (e) {
      print('Upload Error: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Add Trusted Contact
  static Future<Map<String, dynamic>> addTrustedContact(
    String name,
    String phone,
    String relation,
  ) async {
    final url = '$baseUrl/user/trusted-contacts';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'relation': relation,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message':
            result['message'] ??
            'Failed to add contact (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Update Trusted Contact
  static Future<Map<String, dynamic>> updateTrustedContact(
    String contactId,
    String name,
    String phone,
    String relation,
  ) async {
    final url = '$baseUrl/user/trusted-contacts/$contactId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'relation': relation,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message':
            result['message'] ??
            'Failed to update contact (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Remove Trusted Contact
  static Future<Map<String, dynamic>> removeTrustedContact(
    String contactId,
  ) async {
    final url = '$baseUrl/user/trusted-contacts/$contactId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .delete(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message':
            result['message'] ??
            'Failed to delete contact (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Destinations
  static Future<Map<String, dynamic>> getDestinations() async {
    final url = '$baseUrl/destinations';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final resultData = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': resultData};
      return {
        'success': false,
        'message': resultData['message'] ?? 'Failed to load destinations',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Add Destination
  static Future<Map<String, dynamic>> addDestination(
    Map<String, dynamic> data,
  ) async {
    final url = '$baseUrl/destinations';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 15));

      final resultData = jsonDecode(response.body);
      if (response.statusCode == 201)
        return {'success': true, 'data': resultData};
      return {
        'success': false,
        'message': resultData['message'] ?? 'Failed to add destination',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Remove Destination
  static Future<Map<String, dynamic>> removeDestination(
    String destinationId,
  ) async {
    final url = '$baseUrl/destinations/$destinationId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .delete(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final resultData = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': resultData};
      return {
        'success': false,
        'message': resultData['message'] ?? 'Failed to remove destination',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Report Incident with Proof (Multi-file upload)
  static Future<Map<String, dynamic>> reportIncidentWithProof({
    required String type,
    required String description,
    required String severity,
    required String address,
    required double lat,
    required double lng,
    required List<Map<String, dynamic>>
    files, // List of { 'bytes': Uint8List, 'name': String, 'type': 'image'|'video' }
  }) async {
    final url = '$baseUrl/incidents';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';

      // Add fields
      request.fields['type'] = type;
      request.fields['description'] = description;
      request.fields['severity'] = severity;
      request.fields['address'] = address;
      request.fields['lat'] = lat.toString();
      request.fields['lng'] = lng.toString();

      // Add files
      for (var file in files) {
        var multipartFile = http.MultipartFile.fromBytes(
          'proofs',
          file['bytes'],
          filename: file['name'],
          contentType: MediaType(file['type'], file['name'].split('.').last),
        );
        request.files.add(multipartFile);
      }

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      var response = await http.Response.fromStream(streamedResponse);
      final result = jsonDecode(response.body);

      if (response.statusCode == 201) return {'success': true, 'data': result};
      return {
        'success': false,
        'message': result['message'] ?? 'Failed to submit report',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Incidents for Map
  static Future<Map<String, dynamic>> getMapIncidents() async {
    final url = '$baseUrl/incidents/map';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200)
        return {'success': true, 'data': jsonDecode(response.body)};
      return {'success': false, 'message': 'Failed to load map incidents'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get Nearby Incidents (5km Radius default)
  static Future<Map<String, dynamic>> getNearbyIncidents(
    double lat,
    double lng, {
    double radius = 5000,
    int? hours,
  }) async {
    String url = '$baseUrl/incidents?lat=$lat&lng=$lng&radius=$radius';
    if (hours != null) {
      url += '&hours=$hours';
    }
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to load nearby incidents',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update Guarding Location (Periodic)
  static Future<Map<String, dynamic>> updateGuardingLocation(
    String sessionId,
    double lat,
    double lng,
  ) async {
    final url = '$baseUrl/guarding/location/update';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'session_id': sessionId,
              'latitude': lat,
              'longitude': lng,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) return {'success': true};
      return {'success': false, 'message': 'Failed to update location'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // --- SOS ALERT APIs ---

  // Trigger SOS Alert
  static Future<Map<String, dynamic>> triggerSOS(
    String address,
    double lat,
    double lng,
  ) async {
    final url = '$baseUrl/alerts/trigger';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'address': address, 'lat': lat, 'lng': lng}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'data': data['data'] ?? data,
          'message':
              data['message'] ??
              (response.statusCode == 201 ? 'SOS Triggered' : 'SOS Updated'),
        };
      }
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to trigger SOS',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Alert Trusted Contacts (Safety Check Failure)
  static Future<Map<String, dynamic>> alertTrustedContacts(
    double lat,
    double lng,
    String address,
  ) async {
    final url = '$baseUrl/alerts/safety-check/trusted';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'lat': lat, 'lng': lng, 'address': address}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Failed to notify trusted contacts'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Alert Volunteers (Safety Check Failure - Stage 2)
  static Future<Map<String, dynamic>> alertVolunteers(
    double lat,
    double lng,
    String address,
  ) async {
    final url = '$baseUrl/alerts/safety-check/volunteers';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'lat': lat, 'lng': lng, 'address': address}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Failed to notify volunteers'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Resolve SOS Alert
  static Future<Map<String, dynamic>> resolveSOS(String alertId) async {
    final url = '$baseUrl/alerts/resolve/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to resolve SOS',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update Alert Status (General)
  static Future<Map<String, dynamic>> updateAlertStatus(
    String alertId,
    String status,
  ) async {
    final url = '$baseUrl/alerts/status/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update alert status',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get Nearby Incidents (For Volunteers)
  static Future<Map<String, dynamic>> getNearbySOSAlerts(
    double lat,
    double lng, {
    int radius = 5000,
  }) async {
    final url = '$baseUrl/alerts/nearby?lat=$lat&lng=$lng&radius=$radius';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch nearby incidents',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update Volunteer Online/Offline Status
  static Future<Map<String, dynamic>> updateVolunteerStatus(
    bool isOnline,
  ) async {
    final url = '$baseUrl/user/status';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'isOnline': isOnline}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return {'success': true, 'data': data};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update status',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get SOS Alert Details
  static Future<Map<String, dynamic>> getAlertDetails(String alertId) async {
    final url = '$baseUrl/alerts/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch alert details',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error reaching $url: $e'};
    }
  }

  // Get Volunteer Stats
  static Future<Map<String, dynamic>> getVolunteerStats() async {
    final url = '$baseUrl/alerts/volunteer/stats';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch stats',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // --- AUTHORITY APPROVAL APIs ---

  // Get Pending Profile Updates (Authority Only)
  static Future<Map<String, dynamic>> getPendingProfileUpdates() async {
    final url = '$baseUrl/user/pending-updates';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        return {'success': true, 'data': resData['data']};
      }
      return {'success': false, 'message': 'Failed to load pending updates'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Approve Profile Update
  static Future<Map<String, dynamic>> approveProfileUpdate(
    String userId,
  ) async {
    final url = '$baseUrl/user/approve-update/$userId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Approval failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Reject Profile Update
  static Future<Map<String, dynamic>> rejectProfileUpdate(String userId) async {
    final url = '$baseUrl/user/reject-update/$userId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Rejection failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get Unapproved Volunteer Accounts (Authority Only)
  static Future<Map<String, dynamic>> getUnapprovedVolunteers() async {
    final url = '$baseUrl/user/unapproved-volunteers';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        return {'success': true, 'data': resData['data']};
      }
      return {
        'success': false,
        'message': 'Failed to load unapproved volunteers',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Approve Volunteer Account
  static Future<Map<String, dynamic>> approveVolunteerAccount(
    String userId,
  ) async {
    final url = '$baseUrl/user/approve-volunteer/$userId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Account approval failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Reject Volunteer Account Application
  static Future<Map<String, dynamic>> rejectVolunteerAccount(
    String userId,
  ) async {
    final url = '$baseUrl/user/reject-volunteer/$userId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .delete(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) return {'success': true};
      return {'success': false, 'message': 'Account rejection failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get Active SOS Alert
  static Future<Map<String, dynamic>> getActiveAlert() async {
    final url = '$baseUrl/alerts/active';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to check active SOS',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Join Active SOS Alert (For Volunteers)
  static Future<Map<String, dynamic>> joinAlert(String alertId) async {
    final url = '$baseUrl/alerts/join/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to join rescue team',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  static Future<Map<String, dynamic>> uploadAlertEvidence(
    String alertId,
    {String? filePath, Uint8List? bytes, String? fileName, required String type}
  ) async {
    final url = '$baseUrl/alerts/evidence/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';

      http.MultipartFile multipartFile;
      if (filePath != null) {
        final resolvedName = fileName ?? filePath.split('/').last;
        multipartFile = await http.MultipartFile.fromPath(
          'evidence',
          filePath,
          filename: resolvedName,
          contentType: MediaType(
            type == 'video' ? 'video' : 'audio',
            resolvedName.split('.').last,
          ),
        );
      } else if (bytes != null && fileName != null) {
        multipartFile = http.MultipartFile.fromBytes(
          'evidence',
          bytes,
          filename: fileName,
          contentType: MediaType(
            type == 'video' ? 'video' : 'audio',
            fileName.split('.').last,
          ),
        );
      } else {
        return {'success': false, 'message': 'Invalid arguments'};
      }

      request.files.add(multipartFile);

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 60),
      );
      var response = await http.Response.fromStream(streamedResponse);
      final result = jsonDecode(response.body);

      if (response.statusCode == 200) return {'success': true, 'data': result};
      return {
        'success': false,
        'message': result['message'] ?? 'Evidence upload failed',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get SOS Messages
  static Future<Map<String, dynamic>> getSOSMessages(String alertId) async {
    final url = '$baseUrl/chat/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to load messages',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Send SOS Message
  static Future<Map<String, dynamic>> sendSOSMessage(
    String alertId,
    String content,
  ) async {
    final url = '$baseUrl/chat/$alertId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'content': content}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to send message',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // --- Trusted Contact Dashboard APIs ---

  // Get sessions where user is a trusted contact
  static Future<Map<String, dynamic>> getMonitoredSessions() async {
    final url = '$baseUrl/trusted-dashboard/trusted/active-sessions';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to load sessions',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get live location of a monitored session
  static Future<Map<String, dynamic>> getSessionLiveLocation(
    String sessionId,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/live-location/$sessionId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to load location',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Get contact info of session owner
  static Future<Map<String, dynamic>> getSessionContactInfo(
    String sessionId,
  ) async {
    final url = '$baseUrl/trusted-dashboard/user/contact/$sessionId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to load contact info',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Send check-in request
  static Future<Map<String, dynamic>> sendCheckInRequest(
    String sessionId, {
    String type = 'manual',
  }) async {
    final url = '$baseUrl/trusted-dashboard/session/checkin-request';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'sessionId': sessionId, 'type': type}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to send request',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update travel location (for session owner)
  static Future<Map<String, dynamic>> updateTravelLocation(
    String sessionId,
    double latitude,
    double longitude,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/update-location';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'sessionId': sessionId,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update location',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update route points on an active travel session (so trusted contacts see the road path)
  static Future<Map<String, dynamic>> updateTravelRoutePoints(
    String sessionId,
    List<dynamic> routePoints,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/update-route';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};
    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'sessionId': sessionId,
              'routePoints': routePoints,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {'success': false, 'message': data['message'] ?? 'Failed'};
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Start a travel session
  static Future<Map<String, dynamic>> startTravelSession(
    String address,
    double lat,
    double lng, {
    List<dynamic>? routePoints,
  }) async {
    final url = '$baseUrl/trusted-dashboard/session/start';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'destinationAddress': address,
              'lat': lat,
              'lng': lng,
              'routePoints': routePoints, // List of {lat, lng}
            }),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to start session',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Stop a travel session
  static Future<Map<String, dynamic>> stopTravelSession(
    String sessionId,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/stop/$sessionId';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to stop session',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Update travel session status
  static Future<Map<String, dynamic>> updateTravelSessionStatus(
    String sessionId,
    String status,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/status';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'sessionId': sessionId, 'status': status}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to update status',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // Verify/Confirm a check-in
  static Future<Map<String, dynamic>> verifyTravelCheckIn(
    String sessionId,
  ) async {
    final url = '$baseUrl/trusted-dashboard/session/verify-checkin';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'sessionId': sessionId}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to verify check-in',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error'};
    }
  }

  // --- POLICE API ---

  // Get All Active & In-Progress Alerts (Police only)
  static Future<Map<String, dynamic>> getPoliceActiveAlerts() async {
    final url = '$baseUrl/police/alerts/active';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data['data']};
      }

      // Handle non-200 responses (might be JSON or HTML)
      try {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error ${response.statusCode}',
        };
      } catch (_) {
        return {
          'success': false,
          'message':
              'Server error (${response.statusCode}). Please try again later.',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get Victim's Live Location (Real-time update)
  static Future<Map<String, dynamic>> getAlertVictimLocation(
    String alertId,
  ) async {
    final url = '$baseUrl/alerts/$alertId/victim-location';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch location',
      };
    } catch (e) {
      return {'success': false, 'message': 'Location sync error'};
    }
  }

  // Flag an Alert as Fake/Misuse (Police only)
  static Future<Map<String, dynamic>> flagFakeAlert(String alertId) async {
    final url = '$baseUrl/police/alerts/$alertId/flag-fake';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to flag alert',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Pending Volunteer Applications (Police only)
  static Future<Map<String, dynamic>> getPolicePendingVolunteers() async {
    final url = '$baseUrl/police/volunteers/pending';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to fetch pending volunteers',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Verify (Approve/Reject) Volunteer (Police only)
  static Future<Map<String, dynamic>> verifyPoliceVolunteer(
    String userId,
    bool approve,
  ) async {
    final url = '$baseUrl/police/volunteers/$userId/verify';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'approve': approve}),
          )
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200)
        return {'success': true, 'data': data['data']};
      return {
        'success': false,
        'message': data['message'] ?? 'Failed to verify volunteer',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // Get Dashboard Analytics (Police only)
  static Future<Map<String, dynamic>> getPoliceAnalytics() async {
    final url = '$baseUrl/police/analytics/dashboard';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data['data']};
      }

      try {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error ${response.statusCode}',
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Server error (${response.statusCode})',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get All Online Volunteers (Police only)
  static Future<Map<String, dynamic>> getPoliceOnlineVolunteers() async {
    final url = '$baseUrl/police/volunteers/online';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data['data']};
      }

      try {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error ${response.statusCode}',
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Server error (${response.statusCode})',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Get All Incident Reports (Police only)
  static Future<Map<String, dynamic>> getPoliceReports() async {
    final url = '$baseUrl/police/reports';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data['data']};
      }

      try {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error ${response.statusCode}',
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Server error (${response.statusCode})',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  // Update Incident Report Status (Police only)
  static Future<Map<String, dynamic>> updatePoliceReportStatus(
    String reportId,
    String status,
  ) async {
    final url = '$baseUrl/police/reports/$reportId/status';
    final token = await getToken();
    if (token == null)
      return {'success': false, 'message': 'Not authenticated'};

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'status': status}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {'success': true, 'data': data['data']};
      }

      try {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': data['message'] ?? 'Error ${response.statusCode}',
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Server error (${response.statusCode})',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }
}
