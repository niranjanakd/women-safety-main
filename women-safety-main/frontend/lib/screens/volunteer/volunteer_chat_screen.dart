import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import './volunteer_sos_tracking_screen.dart';

class VolunteerChatScreen extends StatefulWidget {
  final Map<String, dynamic> alert;
  const VolunteerChatScreen({super.key, required this.alert});

  @override
  State<VolunteerChatScreen> createState() => _VolunteerChatScreenState();
}

class _VolunteerChatScreenState extends State<VolunteerChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _currentUser;
  Timer? _refreshTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _startPolling();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final result = await ApiService.getProfile();
    if (mounted && result['success']) {
      setState(() => _currentUser = result['data']);
    }
  }

  void _startPolling() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    final result = await ApiService.getSOSMessages(widget.alert['_id']);
    if (mounted && result['success']) {
      final List<Map<String, dynamic>> newMessages = List<Map<String, dynamic>>.from(result['data']);
      if (newMessages.length != _messages.length) {
        setState(() {
          _messages.clear();
          _messages.addAll(newMessages);
          _isLoading = false;
        });
        _scrollToBottom();
      } else {
        setState(() => _isLoading = false);
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

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    _chatController.clear();
    final result = await ApiService.sendSOSMessage(widget.alert['_id'], text);
    if (result['success']) {
      _fetchMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dynamic user = widget.alert['user'];
    final String victimName = (user is Map) ? (user['name'] ?? 'Victim') : 'Victim';
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF1E293B), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFF1F5F9),
              child: Text(victimName[0], style: const TextStyle(color: Color(0xFF9333EA))),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  victimName,
                  style: GoogleFonts.inter(
                    color: const Color(0xFF1E293B),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'SOS Active Session',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF22C55E),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk_outlined, color: Color(0xFF2563EB)),
            onPressed: () {
              final phone = widget.alert['user']?['phone'];
              if (phone != null) launchUrl(Uri.parse('tel:$phone'));
            },
          ),
          IconButton(
            icon: const Icon(Icons.location_on_outlined, color: Color(0xFFEAB308)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VolunteerSosTrackingScreen(alert: widget.alert),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildInfoBanner(),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA)))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final String senderId = msg['sender']?.toString() ?? '';
                    final bool isMe = _currentUser != null && senderId == _currentUser!['_id'].toString();
                    return _buildChatBubble(msg, isMe);
                  },
                ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0xFFFEF2F2),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Coordinate with victim. Provide reassurance.',
              style: GoogleFonts.inter(
                color: const Color(0xFF991B1B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(Map<String, dynamic> msg, bool isMe) {
    final String role = msg['senderRole'] ?? 'user';
    final String content = msg['content'] ?? '';
    final String name = msg['senderName'] ?? 'Unknown';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                '$name (${role.toUpperCase()})',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF9333EA) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Text(
              content,
              style: GoogleFonts.inter(
                color: isMe ? Colors.white : const Color(0xFF1E293B),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 10,
        top: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(25),
              ),
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: 'Type message...',
                  hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              height: 48,
              width: 48,
              decoration: const BoxDecoration(
                color: Color(0xFF9333EA),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
