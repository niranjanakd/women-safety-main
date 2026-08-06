import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';
import 'dart:async';

class PoliceChatScreen extends StatefulWidget {
  final String alertId;
  const PoliceChatScreen({super.key, required this.alertId});

  @override
  State<PoliceChatScreen> createState() => _PoliceChatScreenState();
}

class _PoliceChatScreenState extends State<PoliceChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  Map<String, dynamic>? _currentUser;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fetchMessages();
    _startAutoRefresh();
  }

  Future<void> _fetchProfile() async {
    final result = await ApiService.getProfile();
    if (mounted && result['success']) {
      setState(() => _currentUser = result['data']);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchMessages(isBackground: true);
    });
  }

  Future<void> _fetchMessages({bool isBackground = false}) async {
    if (!isBackground && mounted) {
      setState(() => _isLoading = true);
    }
    
    final res = await ApiService.getSOSMessages(widget.alertId);
    if (res['success'] && mounted) {
      final List<dynamic> data = res['data'];
      setState(() {
        _messages = data.map((m) => {
          'id': m['_id'],
          'senderId': m['sender'],
          'senderName': m['senderName'],
          'senderRole': m['senderRole'],
          'text': m['content'],
          'time': _formatTime(m['createdAt']),
          'color': _getSenderColor(m['senderRole']),
        }).toList();
        _isLoading = false;
      });
      if (!isBackground) _scrollToBottom();
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return '';
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _getSenderColor(String? role) {
    switch (role) {
      case 'user': return Colors.pink;
      case 'volunteer': return Colors.orange;
      case 'authority': return const Color(0xFF2563EB);
      default: return Colors.grey;
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

  final List<String> _quickReplies = [
    "Help is on the way",
    "Stay calm",
    "Share surroundings",
    "Police dispatched",
  ];

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final content = text.trim();
    _msgController.clear();

    final res = await ApiService.sendSOSMessage(widget.alertId, content);
    if (res['success']) {
      _fetchMessages(isBackground: true);
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to send message'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Emergency Group Chat',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'User • Volunteer • Police',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(msg);
                },
              ),
            ),
            _buildQuickReplies(),
            _buildMessageInput(),
          ],
        ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final bool isMe = _currentUser != null && msg['senderId'].toString() == _currentUser!['_id'].toString();
    final String senderLabel = '${msg['senderRole'].toString().toUpperCase()}/${msg['senderName']}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5),
          ],
          border: isMe ? null : Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                senderLabel,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: msg['color'],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              msg['text'],
              style: GoogleFonts.inter(
                color: isMe ? Colors.white : const Color(0xFF1E293B),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                msg['time'],
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickReplies() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _quickReplies.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              backgroundColor: const Color(0xFFE2E8F0),
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF1E293B),
              ),
              label: Text(_quickReplies[index]),
              onPressed: () => _sendMessage(_quickReplies[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.call, color: Color(0xFF2563EB)),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _msgController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: _sendMessage,
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF2563EB),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () => _sendMessage(_msgController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
