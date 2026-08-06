import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import '../auth/role_selection_page.dart';
import '../../services/location_service.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class VolunteerProfileScreen extends StatefulWidget {
  const VolunteerProfileScreen({super.key});

  @override
  State<VolunteerProfileScreen> createState() => _VolunteerProfileScreenState();
}

class _VolunteerProfileScreenState extends State<VolunteerProfileScreen> {
  bool _isLoading = true;
  bool _isUpdating = false;
  String _name = 'Not set';
  String _email = 'Not set';
  String _phone = 'Not set';
  String _location = 'Not set';
  String? _profilePhoto;
  bool _hasPendingUpdate = false;

  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _setupLocationListener();
  }

  void _setupLocationListener() {
    _locationSubscription?.cancel();
    _locationSubscription = LocationService().locationStream.listen((position) {
      _updateAddressFromCoords(position);
    });
    
    // Use current position if already available
    if (LocationService().currentPosition != null) {
      _updateAddressFromCoords(LocationService().currentPosition!);
    }
  }

  Future<void> _updateAddressFromCoords(Position position) async {
    if (!mounted) return;
    try {
      if (!kIsWeb) {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          setState(() {
            _location = "${place.name}, ${place.subLocality}, ${place.locality}";
          });
        }
      } else {
        setState(() {
          _location = "Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}";
        });
      }
    } catch (e) {
      debugPrint("Profile address error: $e");
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final result = await ApiService.getProfile();
    if (mounted && result['success']) {
      final data = result['data'];
      setState(() {
        _name = data['name'] ?? 'Not set';
        _email = data['email'] ?? 'Not set';
        _phone = data['phone'] ?? 'Not set';
        _location = data['address'] ?? 'Not set';
        _profilePhoto = data['profilePhoto'];
        _hasPendingUpdate = data['pendingUpdate'] != null;
        _isLoading = false;
      });
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA)));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              if (_hasPendingUpdate) _buildPendingNotice(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildPersonalInfoCard(),
                ),
              ),
            ],
          ),
          if (_isUpdating)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA))),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF9333EA),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volunteer Profile',
                style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              ElevatedButton(
                onPressed: () async {
                  await ApiService.logout();
                  if (!mounted) return;
                   Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const RoleSelectionPage()),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your volunteer information & settings',
            style: GoogleFonts.inter(fontSize: 16, color: Colors.white.withOpacity(0.9)),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
        ],
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline, color: Color(0xFF9333EA), size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Personal Information',
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B)),
                  ),
                ],
              ),
              if (!_hasPendingUpdate)
                GestureDetector(
                  onTap: _showEditDialog,
                  child: const Icon(Icons.edit_outlined, color: Color(0xFF9333EA), size: 24),
                ),
            ],
          ),
          const SizedBox(height: 32),
          _buildAvatar(),
          const SizedBox(height: 40),
          _buildInfoField('Full Name', _name),
          const SizedBox(height: 24),
          _buildInfoField('Email', _email),
          const SizedBox(height: 24),
          _buildInfoField('Phone Number', _phone),
          const SizedBox(height: 24),
          _buildInfoField('Location', _location),
        ],
      ),
    );
  }

  Widget _buildPendingNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Profile changes are pending authority approval.',
              style: GoogleFonts.inter(color: const Color(0xFF92400E), fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF9333EA).withOpacity(0.2), width: 4),
              image: DecorationImage(
                image: _profilePhoto != null 
                  ? NetworkImage('${ApiService.baseUrl.replaceAll('/api', '')}$_profilePhoto')
                  : NetworkImage("https://ui-avatars.com/api/?name=${Uri.encodeComponent(_name)}&background=9333EA&color=fff"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Color(0xFF9333EA), shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog() {
    _phoneController.text = _phone == 'Not set' ? '' : _phone;
    _addressController.text = _location == 'Not set' ? '' : _location;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number', icon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Location / Address', icon: Icon(Icons.location_on)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performUpdate();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9333EA), foregroundColor: Colors.white),
            child: const Text('Update Profile'),
          ),
        ],
      ),
    );
  }

  Future<void> _performUpdate() async {
    setState(() => _isUpdating = true);
    
    // Send OTP first
    final otpResult = await ApiService.sendProfileUpdateOtp();
    
    setState(() => _isUpdating = false);

    if (otpResult['success']) {
      _showOtpDialog();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(otpResult['message'] ?? 'Failed to send OTP'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showOtpDialog() async {
    final otpController = TextEditingController();
    bool isVerifying = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text('Verify Update', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Please enter the 6-digit OTP sent to your phone.', style: GoogleFonts.inter(color: Colors.black54)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: '000000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: isVerifying ? null : () async {
                    if (otpController.text.trim().length != 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 6-digit OTP')));
                      return;
                    }
                    setStateDialog(() => isVerifying = true);
                    
                    final data = {
                      'phone': _phoneController.text.trim(),
                      'address': _addressController.text.trim(),
                    };
                    
                    final result = await ApiService.updateProfile(data, otp: otpController.text.trim());
                    
                    setStateDialog(() => isVerifying = false);

                    if (result['success']) {
                      Navigator.pop(context); // Close dialog
                      if (mounted) {
                        final isPending = result['data']?['isPending'] ?? false;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isPending ? 'Profile update submitted for approval!' : 'Profile updated successfully!')),
                        );
                        _fetchProfile();
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'OTP verification failed', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9333EA)),
                  child: isVerifying 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                    : const Text('Verify & Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  Widget _buildInfoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
      ],
    );
  }
}
