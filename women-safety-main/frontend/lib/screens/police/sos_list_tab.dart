import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'sos_detail_screen.dart';
import '../../services/api_service.dart';
import 'dart:async';
import 'dart:convert';

class SosListTab extends StatefulWidget {
  const SosListTab({super.key});

  @override
  State<SosListTab> createState() => _SosListTabState();
}

class _SosListTabState extends State<SosListTab> {
  List<Map<String, dynamic>> _sosRequests = [];
  bool _isLoading = true;
  String _error = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
    _startPolling();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchAlerts(isBackground: true);
    });
  }

  Future<void> _fetchAlerts({bool isBackground = false}) async {
    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }
    
    final res = await ApiService.getPoliceActiveAlerts();
    debugPrint('SOS Alerts Response: ${jsonEncode(res)}');
    if (res['success']) {
      setState(() {
        final List<dynamic> data = res['data'];
        _sosRequests = data.map((item) {
          final user = item['user'] ?? {};
          final location = item['location'] ?? {};
          final coords = location['coordinates'] ?? {};
          final volunteers = item['notifiedVolunteers'] as List<dynamic>? ?? [];
          final joinedVol = volunteers.firstWhere((v) => v['joinedAt'] != null, orElse: () => null);
          
          return {
            'id': item['_id'],
            'rawItem': item,
            'name': user['name'] ?? 'Unknown Victim',
            'phone': user['phone'] ?? 'No Phone',
            'priority': item['priority'] ?? 'High',
            'status': item['status'] == 'active' ? 'Pending' : (item['status'] == 'in-progress' ? 'Accepted' : (item['status'] == 'done' ? 'Completed' : 'Resolved')),
            'time': _formatTime(item['createdAt']),
            'location': location['address'] ?? 'Unknown Location',
            'coords': (coords is List && coords.length >= 2) 
                ? '${coords[1]}° N, ${coords[0]}° E' 
                : '${coords['lat'] ?? 0.0}° N, ${coords['lng'] ?? 0.0}° E',
            'victimPhone': user['phone'] ?? '',
            'volunteer': joinedVol != null ? joinedVol['name'] : 'Unassigned',
            'volunteerPhone': (joinedVol != null && joinedVol['user'] != null) ? (joinedVol['user']['phone'] ?? '') : '',
          };
        }).toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = res['message'];
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return 'Just now';
    final date = DateTime.tryParse(dateStr);
    if (date == null) return 'Just now';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    return '${diff.inHours} hours ago';
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.red;
      case 'Accepted':
        return const Color(0xFF2563EB); // Blue
      case 'Completed':
      case 'Resolved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF2563EB),
        title: Text(
          'Active SOS Alerts',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () {
              // Filter logic placeholder
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2563EB)))
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _fetchAlerts,
                        child: const Text('Retry'),
                      )
                    ],
                  ),
                )
              : _sosRequests.isEmpty
                  ? const Center(
                      child: Text('No active SOS alerts',
                          style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _fetchAlerts,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sosRequests.length,
                        itemBuilder: (context, index) {
                          final sos = _sosRequests[index];
                          return _buildSosCard(sos);
                        },
                      ),
                    ),
    );
  }

  Widget _buildSosCard(Map<String, dynamic> sos) {
    final priorityColor = _getPriorityColor(sos['priority']);
    final statusColor = _getStatusColor(sos['status']);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SosDetailScreen(sosData: sos),
          ),
        );
        if (result == true) {
          _fetchAlerts();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: priorityColor.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: priorityColor.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: priorityColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.emergency, color: priorityColor, size: 28),
                  ),
                  const SizedBox(width: 16),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              sos['name'],
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                sos['status'],
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: priorityColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${sos['priority']} Priority',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              sos['time'],
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                sos['location'],
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: const Color(0xFF475569),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Footer Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        'Vol: ${sos['volunteer']}',
                        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                  Text(
                    'Tap to view details',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
