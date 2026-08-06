import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../services/api_service.dart';

class LiveEvidencePlayerWebRTC extends StatefulWidget {
  final String alertId;

  const LiveEvidencePlayerWebRTC({Key? key, required this.alertId}) : super(key: key);

  @override
  _LiveEvidencePlayerWebRTCState createState() => _LiveEvidencePlayerWebRTCState();
}

class _LiveEvidencePlayerWebRTCState extends State<LiveEvidencePlayerWebRTC> {
  io.Socket? _socket;
  RTCPeerConnection? _peerConnection;
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _connectWebRTC();
  }

  Future<void> _initRenderer() async {
    await _remoteRenderer.initialize();
  }

  void _connectWebRTC() async {
    final baseUrl = ApiService.baseUrl.replaceAll('/api', '');
    _socket = io.io(baseUrl, io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());

    _socket!.connect();

    _socket!.onConnect((_) {
      debugPrint('[WebRTC Police] Connected to signaling server');
      _socket!.emit('join-room', widget.alertId);
    });

    // Create Peer Connection
    final configuration = {
      'iceServers': [
        {'url': 'stun:stun.l.google.com:19302'},
      ]
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _socket!.emit('ice-candidate', {
        'roomId': widget.alertId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }
      });
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('[WebRTC Police] Stream received!');
      _remoteRenderer.srcObject = stream;
      setState(() => _isConnected = true);
    };

    _socket!.on('offer', (data) async {
      debugPrint('[WebRTC Police] Received offer from victim');
      var offer = RTCSessionDescription(data['sdp'], data['type']);
      await _peerConnection?.setRemoteDescription(offer);

      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _socket!.emit('answer', {
        'roomId': widget.alertId,
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        }
      });
    });

    _socket!.on('ice-candidate', (data) async {
      debugPrint('[WebRTC Police] Received ICE candidate');
      var candidate = RTCIceCandidate(
        data['candidate'],
        data['sdpMid'],
        data['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    });
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _peerConnection?.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  bool _isPlaying = true;
  bool _isMuted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Live Evidence', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _isConnected
            ? _buildYouTubeStylePlayer()
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 16),
                  Text("Waiting for victim live stream...", style: TextStyle(color: Colors.white70)),
                ],
              ),
      ),
    );
  }

  Widget _buildYouTubeStylePlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // The actual video feed
          RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
          
          // YouTube-style Gradient Overlay for bottom controls
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.6, 1.0],
              ),
            ),
          ),

          // LIVE Badge (Top Left)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.circle, color: Colors.white, size: 10),
                  const SizedBox(width: 4),
                  Text('LIVE', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ),

          // Playback Controls (Bottom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPlaying = !_isPlaying;
                      // WebRTC doesn't have a native 'pause' for remote streams that buffers, 
                      // but we can disable the audio/video tracks to simulate pausing
                      _remoteRenderer.srcObject?.getTracks().forEach((track) {
                        track.enabled = _isPlaying;
                      });
                    });
                  },
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isMuted = !_isMuted;
                      _remoteRenderer.srcObject?.getAudioTracks().forEach((track) {
                        track.enabled = !_isMuted;
                      });
                    });
                  },
                  child: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const Spacer(),
                Text(
                  'Real-Time Feed',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.fullscreen, color: Colors.white, size: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
