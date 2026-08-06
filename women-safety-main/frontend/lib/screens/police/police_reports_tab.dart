import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';

class PoliceReportsTab extends StatefulWidget {
  const PoliceReportsTab({super.key});

  @override
  State<PoliceReportsTab> createState() => _PoliceReportsTabState();
}

class _PoliceReportsTabState extends State<PoliceReportsTab> {
  List<dynamic> _reports = [];
  bool _isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchReports(isBackground: true);
    });
  }

  Future<void> _fetchReports({bool isBackground = false}) async {
    if (!isBackground) setState(() => _isLoading = true);
    final result = await ApiService.getPoliceReports();
    if (result['success']) {
      if (mounted) {
        setState(() {
          _reports = result['data'];
          _isLoading = false;
        });
      }
    } else {
      if (!isBackground) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Failed to load reports')),
          );
        }
      }
    }
  }

  Future<void> _updateReportStatus(String reportId, String currentStatus) async {
    final newStatus = currentStatus.toLowerCase() == 'resolved' ? 'pending' : 'resolved';
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final result = await ApiService.updatePoliceReportStatus(reportId, newStatus);
    
    // Close loading
    if (context.mounted) Navigator.pop(context);

    if (result['success']) {
      if (context.mounted) Navigator.pop(context); // Close the detail dialog
      _fetchReports(); // Refresh the list
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report marked as $newStatus')),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to update status')),
        );
      }
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showReportDetails(Map<String, dynamic> report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Details', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Type', report['type']),
              _buildDetailRow('Severity', report['severity']),
              _buildDetailRow('Status', report['status']),
              _buildDetailRow('Reported By', report['userId']?['name'] ?? 'Unknown User'),
              _buildDetailRow('User ID', report['userId']?['userId'] ?? 'Unknown ID'),
              _buildDetailRow('Phone', report['userId']?['phone'] ?? 'N/A'),
              const SizedBox(height: 12),
              Text('Description:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(report['description'] ?? 'No description provided.', style: GoogleFonts.inter(fontSize: 14)),
              const SizedBox(height: 12),
              Text('Location:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Text(report['location']['address'] ?? 'Unknown address', style: GoogleFonts.inter(fontSize: 14)),
              if (report['proofs'] != null && (report['proofs'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Proof Supplied (${report['proofs'].length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF2563EB))),
                const SizedBox(height: 8),
                ... (report['proofs'] as List).map((proof) {
                  final String filePath = proof['path'] ?? '';
                  final String fileType = proof['type'] ?? 'image';
                  final String fileName = filePath.split('/').last;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: ListTile(
                      dense: true,
                      tileColor: Colors.grey[100],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      leading: Icon(
                        fileType == 'video' ? Icons.videocam : Icons.image,
                        color: const Color(0xFF2563EB),
                      ),
                      title: Text(
                        fileName,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                      onTap: () async {
                        final String baseUrl = ApiService.baseUrl.replaceAll('/api', '');
                        final String fullUrl = '$baseUrl/$filePath'.replaceAll('//', '/').replaceFirst('http:/', 'http://').replaceFirst('https:/', 'https://');
                        
                        final Uri uri = Uri.parse(fullUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not open file')),
                            );
                          }
                        }
                      },
                    ),
                  );
                }),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => _updateReportStatus(report['_id'], report['status']),
            style: ElevatedButton.styleFrom(
              backgroundColor: report['status'] == 'resolved' ? Colors.grey : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(report['status'] == 'resolved' ? 'Mark Pending' : 'Mark Resolved'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.grey[700])),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No Incident Reports', style: GoogleFonts.inter(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('There are currently no reports submitted by users.', style: GoogleFonts.inter(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReports,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchReports,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reports.length,
        itemBuilder: (context, index) {
          final report = _reports[index];
          final reportedAt = DateTime.parse(report['createdAt']).toLocal();
          final formattedDate = DateFormat('MMM d, yyyy • h:mm a').format(reportedAt);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _showReportDetails(report),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            report['type'] ?? 'Incident Report',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: report['status'] == 'resolved' 
                                ? Colors.green.withOpacity(0.1) 
                                : _getSeverityColor(report['severity']).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            report['status'] == 'resolved' 
                                ? 'RESOLVED' 
                                : (report['severity'] ?? 'UNKNOWN').toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: report['status'] == 'resolved' 
                                  ? Colors.green 
                                  : _getSeverityColor(report['severity']),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      report['description'] ?? 'No description',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(color: Colors.grey[800], fontSize: 14),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            report['location']['address'] ?? 'Unknown location',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(formattedDate, style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                        Row(
                          children: [
                            if (report['proofs'] != null && (report['proofs'] as List).isNotEmpty) ...[
                              Icon(Icons.attachment, size: 14, color: Colors.blue[600]),
                              const SizedBox(width: 4),
                              Text('${report['proofs'].length} Attached', style: GoogleFonts.inter(color: Colors.blue[600], fontSize: 12, fontWeight: FontWeight.bold)),
                            ] else ...[
                              Text('No Attachments', style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 12)),
                            ]
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
