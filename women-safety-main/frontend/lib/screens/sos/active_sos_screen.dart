import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../services/api_service.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

class ActiveSOSScreen extends StatefulWidget {
  final Map<String, dynamic>? initialAlert;
  const ActiveSOSScreen({super.key, this.initialAlert});

  @override
  State<ActiveSOSScreen> createState() => _ActiveSOSScreenState();
}

class _ActiveSOSScreenState extends State<ActiveSOSScreen> {
  final List<Map<String, dynamic>> _chatMessages = [];
  final _chatController = TextEditingController();
  Map<String, dynamic>? _activeAlert;
  Map<String, dynamic>? _currentUser;
  bool _isLoading = true;
  bool _isInitializing = true; // For the connection overlay
  Timer? _chatTimer;
  final ScrollController _scrollController = ScrollController();

  // Camera recording state
  CameraController? _cameraController;
  bool _isRecording = false;
  Timer? _recordingTimer;
  bool _videoRecordingEnabled = true;

  @override
  void initState() {
    super.initState();
    _activeAlert = widget.initialAlert;
    _fetchCurrentUser();
    _fetchLatestAlert();
    _initializeCameraAndStartRecording();
    
    // Safety timeout for initializing overlay if network is extremely slow
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isInitializing) {
        setState(() => _isInitializing = false);
      }
    });
  }

  Future<void> _fetchCurrentUser() async {
    final result = await ApiService.getProfile();
    if (mounted && result['success']) {
      setState(() {
        _currentUser = result['data'];
      });
    }
  }

  Future<void> _initializeCameraAndStartRecording() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("No cameras found.");
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: true,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      await _startRecording();
    } catch (e) {
      debugPrint("Camera Initialization Error: $e");
      if (mounted) {
        setState(() => _videoRecordingEnabled = false);
      }
    }
  }

  Future<void> _startRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_videoRecordingEnabled)
      return;

    try {
      await _cameraController!.startVideoRecording();
      if (mounted) setState(() => _isRecording = true);

      _recordingTimer = Timer(const Duration(seconds: 5), () async {
        if (_isRecording) {
          await _stopAndUploadRecording();
          _startRecording();
        }
      });
    } catch (e) {
      debugPrint("Recording Start Error (Likely Emulator): $e");
      if (mounted) {
        setState(() {
          _isRecording = false;
          _videoRecordingEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Video recording disabled (Emulator/Hardare limitation). SOS Chat & audio still active.",
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _stopAndUploadRecording() async {
    if (!_isRecording || _cameraController == null) return;

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      _recordingTimer?.cancel();

      if (_activeAlert != null) {
        final alertId = _activeAlert!['_id'].toString();
        
        if (alertId.startsWith('local_sos')) {
           File(videoFile.path).delete().catchError((_) => File(''));
           return;
        }

        final fileName = path.basename(videoFile.path);

        try {
          final result = await ApiService.uploadAlertEvidence(
            alertId,
            filePath: videoFile.path,
            fileName: fileName,
            type: 'video',
          );
          
          if (result['success']) {
            debugPrint("Evidence uploaded: $fileName");
          } else {
            debugPrint("Evidence upload failed: ${result['message']}");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Upload Failed: ${result['message']}"),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 8),
                ),
              );
            }
          }
        } catch (error) {
          debugPrint("Network/Upload Catch Error: $error");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Network Error: $error"),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 8),
              ),
            );
          }
        }

        File(videoFile.path).delete().catchError((e) {
          debugPrint("Error deleting temp file: $e");
          return File(videoFile.path);
        });
      }
    } catch (e) {
      debugPrint("Recording Stop/Upload Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Camera/Memory Error: $e"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _fetchLatestAlert() async {
    if (_activeAlert != null) {
      if (mounted) setState(() => _isLoading = false);
      _startSOSPolling();
      
      // If we already have alert, just wait a bit for the ceremony
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isInitializing = false);
      });
    }

    if (_activeAlert == null || (_activeAlert!['isLocalOnly'] == true)) {
      final result = await ApiService.getActiveAlert();
      if (result['success'] && result['data'] != null) {
        if (mounted) {
          setState(() {
            _activeAlert = result['data'];
            _isLoading = false;
          });
          // Show overlay for at least 2 seconds for feedback
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _isInitializing = false);
          });
        }
        _startSOSPolling();
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          // If fetch fails, show main screen (offline mode) after 1s
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) setState(() => _isInitializing = false);
          });
        }
      }
    }
  }

  bool _isAutoPopping = false;

  void _startSOSPolling() {
    _chatTimer?.cancel();
    _chatTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _fetchSOSUpdate();
    });
    _fetchSOSUpdate();
  }

  Future<void> _fetchSOSUpdate() async {
    if (_activeAlert == null || _isAutoPopping) return;

    final alertId = _activeAlert!['_id'].toString();

    // 1. Polling for Status (New)
    try {
      final alertResult = await ApiService.getAlertDetails(alertId);
      if (alertResult['success']) {
        final alertData = alertResult['data'];
        final status = alertData['status']?.toString().toLowerCase();

        if (status == 'resolved' || status == 'done') {
          _isAutoPopping = true;
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Emergency Resolved by Authority/Volunteer. Glad you're safe!"),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 4),
              ),
            );
            Navigator.pop(context);
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("Status polling error: $e");
    }

    // 2. Polling for Messages (Existing)
    final result = await ApiService.getSOSMessages(alertId);
    if (result['success']) {
      if (mounted) {
        final List<Map<String, dynamic>> newMessages =
            List<Map<String, dynamic>>.from(result['data']);

        if (newMessages.length != _chatMessages.length) {
          setState(() {
            _chatMessages.clear();
            _chatMessages.addAll(newMessages);
          });
          _scrollToBottom();
        }
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _resolveSOS() async {
    if (_activeAlert == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, // Minimal for simple loader
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.green),
            const SizedBox(height: 16),
            Text(
              "Ending Emergency Session...",
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    // Stop recording first if resolving
    await _stopAndUploadRecording();

    final result = await ApiService.resolveSOS(_activeAlert!['_id']);

    if (!mounted) return;
    Navigator.pop(context); // Pop loading

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("SOS Resolved. Glad you are safe!")),
      );
      Navigator.pop(context); // Pop screen
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error resolving SOS: ${result['message']}")),
      );
    }
  }

  Future<void> _handleManualExit() async {
    // Show a small feedback indicating we are cleaning up
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.redAccent),
              const SizedBox(height: 24),
              Text(
                "Saving secure data...",
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Finalizing logs and stopping recording",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    // Ensure recording is stopped
    await _stopAndUploadRecording();

    if (mounted) {
      Navigator.pop(context); // Pop loading
      Navigator.pop(context); // Pop SOS screen
    }
  }

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    if (_activeAlert == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Waiting for emergency session...")),
      );
      return;
    }

    final alertId = _activeAlert!['_id'].toString();
    if (alertId.startsWith('local_sos_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Connecting to server...")),
      );
      _fetchLatestAlert();
      return;
    }

    final content = text;
    _chatController.clear();

    try {
      final result = await ApiService.sendSOSMessage(alertId, content);
      if (result['success']) {
        _fetchSOSUpdate();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Error: ${result['message']}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Check connection.")),
        );
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _chatTimer?.cancel();
    
    // We try to clean up but don't await here as dispose is sync.
    // The handleManualExit ensures we await before actually popping in controlled scenarios.
    _stopAndUploadRecording().catchError((e) => debugPrint("Dispose recording stop error: $e"));
    
    try {
      _cameraController?.dispose();
    } catch (e) {
      debugPrint("Camera disposal error in widget dispose: $e");
    }
    
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Content
          Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildStatusCard(
                                      'Recording',
                                      _isRecording ? 'Active' : 'Initializing...',
                                      _isRecording ? Colors.red : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildStatusCard(
                                      'Location',
                                      'Sharing Live',
                                      Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              _buildCall112Button(),
                              const SizedBox(height: 16),
                              _buildSilentWitnessBanner(),
                              const SizedBox(height: 16),
                              _buildVolunteerChat(),
                              const SizedBox(height: 16),
                              _buildContactsNotified(),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
          
          // Initializing Overlay
          if (_isInitializing) _buildInitializingOverlay(),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          const Icon(Icons.error, color: Colors.red, size: 28),
          const SizedBox(width: 8),
          Text(
            'Emergency Mode',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _resolveSOS,
          child: Text(
            "I'm Safe",
            style: GoogleFonts.inter(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: _handleManualExit,
        ),
      ],
    );
  }

  Widget _buildStatusCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCall112Button() {
    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone, color: Colors.white, size: 40),
              const SizedBox(width: 20),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
                  ),
                  Text(
                    '112',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSilentWitnessBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: Colors.purple, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Silent Witness Recording',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: Colors.purple, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }

  Widget _buildVolunteerChat() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.forum_outlined, color: Colors.purpleAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'SOS Live Chat',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ACTIVE',
                      style: GoogleFonts.inter(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: _chatMessages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isLoading || _isInitializing)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.purpleAccent,
                              ),
                            ),
                          Text(
                            _isInitializing
                                ? "Initializing secure chat channel..."
                                : 'Secure encrypted channel. SOS team notified.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    shrinkWrap: true,
                    itemCount: _chatMessages.length,
                    itemBuilder: (context, index) {
                      final msg = _chatMessages[index];
                      final String role = msg['senderRole'] ?? 'user';
                      final String name = msg['senderName'] ?? 'Unknown';
                      final String content = msg['content'] ?? '';
                      final String senderId = msg['sender']?.toString() ?? '';
                      final bool isMe = _currentUser != null && senderId == _currentUser!['_id'].toString();

                      Color bubbleColor = isMe ? const Color(0xFFDB2777) : (role == 'authority' ? const Color(0xFF2563EB) : (role == 'user' ? Colors.grey.shade800 : const Color(0xFF9333EA)));
                      Alignment alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Align(
                          alignment: alignment,
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                                  child: Text(
                                    '$name (${role.toUpperCase()})',
                                    style: GoogleFonts.inter(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(isMe ? 18 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 18),
                                  ),
                                ),
                                child: Text(
                                  content,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(25)),
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type message...',
                      hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: const BoxDecoration(color: Color(0xFFDB2777), shape: BoxShape.circle),
                  child: const Center(child: Icon(Icons.send_rounded, color: Colors.white, size: 22)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactsNotified() {
    final contacts = _activeAlert?['notifiedContacts'] as List? ?? [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline, color: Colors.blueAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Contacts Notified',
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (contacts.isEmpty)
            Text('Notifying emergency contacts...', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: contacts.map((c) => Chip(
                backgroundColor: Colors.blueAccent.withOpacity(0.1),
                label: Text(c['name'] ?? 'Contact', style: GoogleFonts.inter(color: Colors.blueAccent, fontSize: 12)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildInitializingOverlay() {
    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: _isInitializing ? 1.0 : 0.0,
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 70,
                height: 70,
                child: CircularProgressIndicator(color: Colors.redAccent, strokeWidth: 5),
              ),
              const SizedBox(height: 40),
              Text(
                'SOS ACTIVATED',
                style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                'Connecting to Secure Emergency Services...',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                    const SizedBox(width: 12),
                    Text('SYNCING DATA', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
