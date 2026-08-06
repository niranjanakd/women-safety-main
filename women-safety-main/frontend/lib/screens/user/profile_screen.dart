import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/role_selection_page.dart';
import '../../services/api_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../../services/background_guarding_service.dart';
import '../shared/map_picker_screen.dart';
import '../../services/location_service.dart';
import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'package:perfect_volume_control/perfect_volume_control.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String _name = 'Loading...';
  String _email = 'Loading...';
  String _phone = 'Loading...';
  String _currentAddress = 'Not provided';
  String? _profilePhoto;
  String _sosTriggerWord = 'red';
  List<dynamic> _trustedContacts = [];
  List<dynamic> _destinations = [];
  final ImagePicker _picker = ImagePicker();
  String? _gender;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _setupLocationListener();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  void _setupLocationListener() {
    _locationSubscription = LocationService().locationStream.listen((position) {
      _onLocationUpdate(position.latitude, position.longitude);
    });
  }

  Future<void> _onLocationUpdate(double lat, double lng) async {
    if (kIsWeb) return;
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        if (mounted) {
          setState(() {
            _currentAddress = '${place.name}, ${place.subLocality}, ${place.locality}';
          });
        }
      }
    } catch (e) {
      debugPrint("Address lookup error: $e");
    }
  }

  Future<void> _fetchProfile() async {
    try {
      final profileResult = await ApiService.getProfile();
      
      if (mounted && profileResult['success']) {
        final profile = profileResult['data'];
        setState(() {
          _name = profile['name'] ?? 'Unknown';
          _email = profile['email'] ?? 'No email available';
          _phone = (profile['phone'] ?? '').toString();
          _sosTriggerWord = profile['sosTriggerWord'] ?? 'help';
          _profilePhoto = profile['profilePhoto'];
          _gender = profile['gender']?.toString().toLowerCase();
          _trustedContacts = profile['trustedContacts'] ?? [];
          _destinations = profile['destinations'] ?? [];
          _isLoading = false;
        });
        
        // SYNC TRIGGER WORD AND GENDER TO LOCAL CACHE
        final p = await SharedPreferences.getInstance();
        await p.setString('active_sos_trigger_word', _sosTriggerWord);
        final genderStr = _gender ?? 'female';
        await p.setString('user_gender', genderStr);
        
        // RE-INITIALIZE BACKGROUND SERVICE TO RE-FETCH PROFILE AND TRIGGER WORD
        initializeBackgroundService();
        FlutterBackgroundService().invoke("setAsForeground");
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      }
    }
  }

  void _showEditProfileDialog() {
    final nameController = TextEditingController(text: _name);
    final emailController = TextEditingController(text: _email);
    final phoneController = TextEditingController(text: _phone);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name')),
            TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone Number'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              final phone = phoneController.text.trim();
              
              if (name.isEmpty) return;

              Navigator.pop(context);
              setState(() => _isLoading = true);
              final result = await ApiService.updateProfile({
                'name': name,
                'email': email,
                'phone': phone,
              });
              
              if (result['success']) {
                _fetchProfile();
              } else {
                setState(() => _isLoading = false);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      setState(() => _isLoading = true);
      try {
        final bytes = await image.readAsBytes();
        final result = await ApiService.uploadProfilePhoto(bytes, image.name);
        if (result['success']) {
          _fetchProfile();
        } else {
          setState(() => _isLoading = false);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    }
  }

  void _showAddContactDialog({Map<String, dynamic>? contact}) {
    final nameController = TextEditingController(text: contact?['name']);
    final phoneController = TextEditingController(text: contact?['phone']);
    final relationController =
        TextEditingController(text: contact?['relation'] ?? 'General');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          contact == null ? 'Add Trusted Contact' : 'Edit Trusted Contact',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g., Mom',
              ),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '9988776655',
              ),
              keyboardType: TextInputType.phone,
            ),
            TextField(
              controller: relationController,
              decoration: const InputDecoration(
                labelText: 'Relation',
                hintText: 'e.g., Mother, Friend',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final relation = relationController.text.trim();
              if (name.isEmpty || phone.isEmpty) return;

              Navigator.pop(context);
              setState(() => _isLoading = true);

              final result = contact == null
                  ? await ApiService.addTrustedContact(name, phone, relation)
                  : await ApiService.updateTrustedContact(
                    contact['_id'],
                    name,
                    phone,
                    relation,
                  );

              if (result['success']) {
                _fetchProfile();
              } else {
                setState(() => _isLoading = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'])),
                  );
                }
              }
            },
            child: Text(contact == null ? 'Add Contact' : 'Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showAddDestinationDialog() {
    final nameController = TextEditingController();
    String? pickedAddress;
    double? pickedLat;
    double? pickedLng;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Add Frequent Place', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Destination Nickname', hintText: 'e.g., Office/Home')),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const MapPickerScreen()));
                    if (result != null && result is Map) {
                      setDialogState(() {
                        pickedAddress = result['address'];
                        pickedLat = result['lat'];
                        pickedLng = result['lng'];
                      });
                    }
                  },
                  icon: const Icon(Icons.map),
                  label: Text(pickedAddress ?? 'Select Location on Map'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty || pickedLat == null) return;

                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  final result = await ApiService.addDestination({
                    'destinationName': name,
                    'placeName': pickedAddress ?? 'Unknown Location',
                    'latitude': pickedLat!,
                    'longitude': pickedLng!,
                  });
                  if (result['success']) {
                    _fetchProfile();
                  } else {
                    setState(() => _isLoading = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
                  }
                },
                child: const Text('Save Place'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showChangeTriggerWordDialog() {
    final triggerWordController = TextEditingController(text: _sosTriggerWord);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Safety Keyword', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a word that is easy to shout in an emergency.',
              style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: triggerWordController,
              decoration: const InputDecoration(
                labelText: 'Trigger Word',
                hintText: 'e.g., rescue, emergency',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              'Default is set to "red". Choose a short, clear word.',
              style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: const Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Cancel')
          ),
          ElevatedButton(
            onPressed: () async {
              final newWord = triggerWordController.text.toLowerCase().trim();
              if (newWord.isEmpty) return;

              Navigator.pop(context);
              
              setState(() => _isLoading = true);
              final result = await ApiService.updateProfile({
                'sosTriggerWord': newWord,
              });

              if (result['success']) {
                final p = await SharedPreferences.getInstance();
                await p.setString('active_sos_trigger_word', newWord);
                _fetchProfile();
              } else {
                setState(() => _isLoading = false);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'])));
              }
            },
            child: const Text('Save Keyword'),
          ),
        ],
      ),
    );
  }

  void _showTestButtonDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ButtonTestDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFC),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildPersonalInfoCard(),
                const SizedBox(height: 24),
                const SizedBox(height: 24),
                _buildCircleOfTrustCard(),
                const SizedBox(height: 24),
                _buildDestinationsCard(),
                const SizedBox(height: 24),
                _buildSecuritySettingsCard(),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: const Color(0xFF7C3AED),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16.0, top: 8, bottom: 8),
          child: OutlinedButton(
            onPressed: () async {
              await ApiService.logout();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const RoleSelectionPage()), (route) => false);
            },
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text('Logout', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
        title: Text('Profile & Settings', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4338CA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFFF1F5F9),
                backgroundImage: _profilePhoto != null ? NetworkImage(_profilePhoto!) : null,
                child: _profilePhoto == null ? const Icon(Icons.person, size: 60, color: Color(0xFF94A3B8)) : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_name, style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
              const SizedBox(width: 8),
              IconButton(onPressed: _showEditProfileDialog, icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF7C3AED))),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(20)),
            child: Text(
              'GENDER: ${(_gender ?? "female").toUpperCase()}', 
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF7C3AED))
            ),
          ),
          const SizedBox(height: 32),
          _buildInfoRow(Icons.email_outlined, 'Email', _email),
          const Divider(height: 32),
          _buildInfoRow(Icons.phone_outlined, 'Phone', _phone),
          const Divider(height: 32),
          _buildInfoRow(Icons.location_on_outlined, 'Current Location', _currentAddress),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, size: 20, color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
              Text(value, style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF1E293B), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCircleOfTrustCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trusted Contacts', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _showAddContactDialog, icon: const Icon(Icons.add_circle, color: Color(0xFF7C3AED), size: 28)),
            ],
          ),
          const SizedBox(height: 16),
          if (_trustedContacts.isEmpty)
             const Text('No trusted contacts added yet.')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _trustedContacts.length,
              itemBuilder: (context, index) {
                final contact = _trustedContacts[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: const Color(0xFFF5F3FF), child: Text(contact['name'][0], style: const TextStyle(color: Color(0xFF7C3AED)))),
                  title: Text(contact['name'], style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  subtitle: Text(contact['phone']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF7C3AED)),
                        onPressed: () => _showAddContactDialog(contact: contact),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          setState(() => _isLoading = true);
                          await ApiService.removeTrustedContact(contact['_id']);
                          _fetchProfile();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDestinationsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Frequent Places', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _showAddDestinationDialog, icon: const Icon(Icons.add_circle, color: Color(0xFF7C3AED), size: 28)),
            ],
          ),
          const SizedBox(height: 16),
          if (_destinations.isEmpty)
            const Text('No saved destinations yet.')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _destinations.length,
              itemBuilder: (context, index) {
                final dest = _destinations[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on, color: Color(0xFF7C3AED)),
                  title: Text(dest['destinationName'], style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  subtitle: Text(dest['placeName'], maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                       setState(() => _isLoading = true);
                       await ApiService.removeDestination(dest['_id']);
                       _fetchProfile();
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSecuritySettingsCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Security Settings', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildSettingsRow(
            Icons.mic_none, 
            'Voice Trigger Word',
            'Trigger: \"$_sosTriggerWord\"',
            onTap: _showChangeTriggerWordDialog,
          ),
          const Divider(height: 32),
          _buildSettingsRow(
            Icons.fingerprint, 
            'Physical Button Trigger',
            'Press Volume Up 3x within 2s',
            onTap: _showTestButtonDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: const Color(0xFF64748B), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B))),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

class _ButtonTestDialog extends StatefulWidget {
  @override
  State<_ButtonTestDialog> createState() => _ButtonTestDialogState();
}

class _ButtonTestDialogState extends State<_ButtonTestDialog> {
  final List<DateTime> _presses = [];
  StreamSubscription? _subscription;
  String _status = "Waiting for first press...";
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startListening() {
    _subscription = PerfectVolumeControl.stream.listen((volume) {
      if (_success) return;
      
      final now = DateTime.now();
      setState(() {
        _presses.add(now);
        if (_presses.length > 3) _presses.removeAt(0);

        if (_presses.length == 1) {
          _status = "1/3 detected. Quick, 2 more!";
        } else if (_presses.length == 2) {
          _status = "2/3 detected. One more!";
        } else if (_presses.length == 3) {
          final diff = _presses.last.difference(_presses.first).inMilliseconds;
          if (diff <= 2000) {
            _status = "✅ SUCCESS! SOS Trigger Pattern Verified.";
            _success = true;
          } else {
            _status = "Too slow! Press 3 times within 2 seconds.";
            _presses.clear();
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Practice SOS Trigger', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rapidly press the VOLUME UP button 3 times within 2 seconds to test the trigger.',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _success ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _success ? Icons.check_circle : Icons.touch_app,
              size: 64,
              color: _success ? const Color(0xFF059669) : const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _status,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _success ? const Color(0xFF059669) : const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),
          if (!_success)
            LinearProgressIndicator(
              value: _presses.length / 3,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C3AED)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_success ? 'Done' : 'Cancel'),
        ),
        if (_success)
          TextButton(
            onPressed: () {
              setState(() {
                _success = false;
                _presses.clear();
                _status = "Waiting for first press...";
              });
            },
            child: const Text('Test Again'),
          ),
      ],
    );
  }
}
