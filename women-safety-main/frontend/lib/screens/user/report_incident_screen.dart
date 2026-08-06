import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import 'dart:async';

class ReportIncidentScreen extends StatefulWidget {
  const ReportIncidentScreen({super.key});

  @override
  State<ReportIncidentScreen> createState() => _ReportIncidentScreenState();
}

class _ReportIncidentScreenState extends State<ReportIncidentScreen> {
  String _selectedSeverity = 'Medium';
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedType = 'Harassment';

  final ImagePicker _picker = ImagePicker();
  final List<Map<String, dynamic>> _pickedFiles = [];
  bool _isDetectingLocation = false;
  double? _lat;
  double? _lng;
  StreamSubscription? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _setupLocationListener();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _setupLocationListener() {
    // Initial sync
    final pos = LocationService().currentPosition;
    if (pos != null) {
      _onLocationUpdate(pos);
    }

    _locationSubscription = LocationService().locationStream.listen((pos) {
      _onLocationUpdate(pos);
    });
  }

  void _onLocationUpdate(Position pos) {
    if (!mounted) return;
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
    });

    // Only auto-populate if currently empty or detecting
    if (_locationController.text.isEmpty || _isDetectingLocation) {
      _updateAddressFromCoords(pos.latitude, pos.longitude);
    }
  }

  Future<void> _updateAddressFromCoords(double lat, double lng) async {
    setState(() => _isDetectingLocation = true);
    try {
      if (kIsWeb) {
        setState(() {
          _locationController.text =
              "Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}";
        });
      } else {
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          setState(() {
            _locationController.text =
                "${place.name ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}";
          });
        }
      }
    } catch (e) {
      debugPrint("Address update error: $e");
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  Future<void> _detectLocation() async {
    // Manually trigger a refresh from LocationService if needed
    final pos = LocationService().currentPosition;
    if (pos != null) {
      _onLocationUpdate(pos);
    } else {
      LocationService().startTracking();
    }
  }

  Future<void> _pickEvidence(bool isVideo) async {
    try {
      final XFile? file = isVideo
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 70,
            );

      if (file != null) {
        final Uint8List bytes = await file.readAsBytes();
        setState(() {
          _pickedFiles.add({
            'bytes': bytes,
            'name': file.name,
            'path': file.path,
            'type': isVideo ? 'video' : 'image',
          });
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
    }
  }

  void _submitReport() async {
    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the incident')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ApiService.reportIncidentWithProof(
        type: _selectedType,
        description: _descriptionController.text,
        severity: _selectedSeverity,
        address: _locationController.text,
        lat: _lat ?? 0.0,
        lng: _lng ?? 0.0,
        files: _pickedFiles,
      );

      Navigator.pop(context); // Pop loading

      if (result['success']) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: ${result['message']}')));
      }
    } catch (e) {
      Navigator.pop(context); // Pop loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Report Submitted'),
          ],
        ),
        content: const Text(
          'Your incident report and proof have been securely stored in our database. Stay safe.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetForm();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _resetForm() {
    setState(() {
      _selectedSeverity = 'Medium';
      _descriptionController.clear();
      _selectedType = 'Harassment';
      _pickedFiles.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            backgroundColor: const Color(0xFFF97316),
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
              title: Text(
                'Report Incident',
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF97316), Color(0xFFEF4444)],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Incident Type'),
                  _buildDropdown([
                    'Harassment',
                    'Physical Assault',
                    'Theft',
                    'Suspicious Activity',
                    'Other',
                  ]),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Location'),
                  _buildLocationField(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Severity Level'),
                  _buildSeveritySelector(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Description'),
                  _buildDescriptionField(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Evidence (Proof)'),
                  _buildEvidenceGrid(),
                  const SizedBox(height: 12),
                  _buildAttachmentButtons(),
                  const SizedBox(height: 40),
                  _buildSubmitButton(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _buildDropdown(List<String> items) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedType,
          items: items.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, style: GoogleFonts.inter()),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedType = val);
          },
        ),
      ),
    );
  }

  Widget _buildLocationField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _locationController,
        decoration: InputDecoration(
          hintText: _isDetectingLocation ? 'Detecting...' : 'Enter location',
          hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B)),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.my_location,
              color: _isDetectingLocation
                  ? Colors.orange
                  : const Color(0xFF2563EB),
            ),
            onPressed: _detectLocation,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildSeveritySelector() {
    return Row(
      children: ['Low', 'Medium', 'High'].map((severity) {
        bool isSelected = _selectedSeverity == severity;
        Color color = severity == 'Low'
            ? const Color(0xFFEAB308)
            : (severity == 'Medium'
                  ? const Color(0xFFF97316)
                  : const Color(0xFFEF4444));
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedSeverity = severity),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : const Color(0xFFE2E8F0),
                ),
              ),
              child: Center(
                child: Text(
                  severity,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDescriptionField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _descriptionController,
        maxLines: 4,
        decoration: InputDecoration(
          hintText: 'Describe what happened...',
          hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildEvidenceGrid() {
    if (_pickedFiles.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 100,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pickedFiles.length,
        itemBuilder: (context, index) {
          final file = _pickedFiles[index];
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey[200],
              image: file['type'] == 'image'
                  ? DecorationImage(
                      image: MemoryImage(file['bytes']),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Stack(
              children: [
                if (file['type'] == 'video')
                  const Center(child: Icon(Icons.videocam, color: Colors.blue)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pickedFiles.removeAt(index)),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttachmentButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildIconButton(
            Icons.camera_alt_outlined,
            'Add Photo',
            () => _pickEvidence(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildIconButton(
            Icons.videocam_outlined,
            'Add Video',
            () => _pickEvidence(true),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF64748B)),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _submitReport,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF4444),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: Text(
          'Submit Report',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
