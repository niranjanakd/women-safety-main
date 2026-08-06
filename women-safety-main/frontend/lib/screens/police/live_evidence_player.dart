import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import 'dart:async';

class LiveEvidencePlayer extends StatefulWidget {
  final String alertId;

  const LiveEvidencePlayer({Key? key, required this.alertId}) : super(key: key);

  @override
  _LiveEvidencePlayerState createState() => _LiveEvidencePlayerState();
}

class _LiveEvidencePlayerState extends State<LiveEvidencePlayer> {
  List<Map<String, dynamic>> _playlist = [];
  int _currentIndex = -1;
  VideoPlayerController? _controller;
  bool _isLoadingPlaylist = true;
  bool _isPlayingSegment = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchEvidence();
    _startPolling();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchEvidence(isPolling: true);
    });
  }

  Future<void> _fetchEvidence({bool isPolling = false}) async {
    final result = await ApiService.getAlertDetails(widget.alertId);
    if (!mounted) return;

    if (result['success']) {
      final data = result['data'];
      final evidenceList = List<Map<String, dynamic>>.from(data['evidence'] ?? []);

      // Check if HLS is available
      final hlsStream = evidenceList.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e != null && e['fileType'] == 'hls_stream',
        orElse: () => null,
      );

      if (hlsStream != null) {
        if (_controller == null) {
          _pollingTimer?.cancel(); // HLS natively polls the m3u8 playlist
          setState(() {
            _playlist = [hlsStream];
            _isLoadingPlaylist = false;
            _currentIndex = 0;
          });
          _initializeAndPlay(hlsStream, isHls: true);
        }
        return;
      }

      if (evidenceList.length > _playlist.length) {
        setState(() {
          _playlist = evidenceList;
          _isLoadingPlaylist = false;
        });

        if (!_isPlayingSegment && _currentIndex >= 0 && _currentIndex < _playlist.length - 1) {
          _playNextSegment();
        } else if (_currentIndex == -1 && _playlist.isNotEmpty) {
          _currentIndex = 0;
          _initializeAndPlay(_playlist[_currentIndex]);
        }
      } else if (evidenceList.isEmpty && _isLoadingPlaylist) {
        setState(() {
          _isLoadingPlaylist = false;
        });
      }
    } else if (!isPolling) {
      setState(() => _isLoadingPlaylist = false);
    }
  }

  Future<void> _initializeAndPlay(Map<String, dynamic> evidence, {bool isHls = false}) async {
    final baseUrlHost = ApiService.baseUrl.replaceAll('/api', '');
    final fullUrl = '$baseUrlHost${evidence['fileUrl']}';
    
    debugPrint("Playing evidence: $fullUrl");
    
    final oldController = _controller;
    
    final newController = VideoPlayerController.networkUrl(
      Uri.parse(fullUrl),
      formatHint: isHls ? VideoFormat.hls : null,
    );
    
    setState(() {
      _isPlayingSegment = true;
    });

    try {
      await newController.initialize();
      if (mounted) {
        setState(() {
          _controller = newController;
        });
        
        _controller!.play();
        
        if (!isHls) {
          _controller!.addListener(_videoListener);
        }
        
        oldController?.dispose();
      } else {
        newController.dispose();
      }
    } catch (e) {
      debugPrint("Error playing evidence: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Video Playback Error: $e"),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      if (!isHls) _playNextSegment();
    }
  }
  
  void _videoListener() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    if (_controller!.value.position >= _controller!.value.duration && _controller!.value.duration > Duration.zero) {
      // Finished playing current segment
      _controller!.removeListener(_videoListener);
      _playNextSegment();
    }
  }

  void _playNextSegment() {
    if (!mounted) return;
    
    if (_currentIndex + 1 < _playlist.length) {
      _currentIndex++;
      _initializeAndPlay(_playlist[_currentIndex]);
    } else {
      // Reached the end of available segments, wait for polling to find more
      setState(() {
        _isPlayingSegment = false;
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Live Evidence Feed', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _buildPlayerArea(),
            ),
          ),
          _buildInfoPanel(),
        ],
      ),
    );
  }

  Widget _buildPlayerArea() {
    if (_isLoadingPlaylist) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.redAccent),
          SizedBox(height: 16),
          Text("Connecting to Secure Feed...", style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    if (_playlist.isEmpty) {
      return const Text("No evidence uploaded yet. Waiting for live feed...", style: TextStyle(color: Colors.white54));
    }

    if (_controller != null && _controller!.value.isInitialized) {
      return AspectRatio(
        aspectRatio: _controller!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_controller!.value.isPlaying) {
                    _controller!.pause();
                  } else {
                    _controller!.play();
                  }
                });
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller!),
                  if (!_controller!.value.isPlaying)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                ],
              ),
            ),
             if (_playlist[_currentIndex]['fileType'] == 'audio')
              Container(
                color: Colors.grey.shade900,
                child: const Center(
                   child: Icon(Icons.mic, color: Colors.white54, size: 80),
                ),
              ),
            VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              colors: const VideoProgressColors(playedColor: Colors.red, backgroundColor: Colors.white24),
            ),
          ],
        ),
      );
    }

    if (!_isPlayingSegment && _currentIndex == _playlist.length - 1) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.redAccent),
          SizedBox(height: 16),
          Text("Waiting for victim app to stream next segment...", style: TextStyle(color: Colors.white70)),
        ],
      );
    }

    return const CircularProgressIndicator(color: Colors.white);
  }

  Widget _buildInfoPanel() {
    if (_playlist.isEmpty) return const SizedBox.shrink();

    final isLive = !_isPlayingSegment && _currentIndex == _playlist.length - 1;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12, height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_playlist.isNotEmpty && _playlist[_currentIndex]['fileType'] == 'hls_stream' ? 'LIVE STREAM' : (isLive ? 'LIVE' : 'PLAYING BACKLOG'), style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              if (_playlist.isNotEmpty && _playlist[_currentIndex]['fileType'] != 'hls_stream')
                Text(
                  'Segment ${_currentIndex + 1} / ${_playlist.length}',
                  style: GoogleFonts.inter(color: Colors.white54),
                )
            ],
          ),
          const SizedBox(height: 16),
          if (_controller != null && _controller!.value.isInitialized)
            ValueListenableBuilder(
              valueListenable: _controller!,
              builder: (context, VideoPlayerValue value, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(value.position), style: const TextStyle(color: Colors.white70)),
                    Text(_formatDuration(value.duration), style: const TextStyle(color: Colors.white70)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
