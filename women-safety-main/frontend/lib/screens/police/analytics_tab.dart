import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/api_service.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    final res = await ApiService.getPoliceAnalytics();
    if (res['success']) {
      setState(() {
        _data = res['data'];
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = res['message'];
        _isLoading = false;
      });
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
          'Analytics Dashboard',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2563EB)),
            )
          : _error.isNotEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _fetchAnalytics,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchAnalytics,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Overview',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Metrics Grid
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _buildStatCard(
                          'Total SOS',
                          '${_data?['totalSOS'] ?? 0}',
                          Icons.campaign,
                          Colors.purple,
                        ),
                        _buildStatCard(
                          'Resolved',
                          '${_data?['resolvedSOS'] ?? 0}',
                          Icons.check_circle,
                          Colors.green,
                        ),
                        _buildStatCard(
                          'Pending',
                          '${_data?['pendingSOS'] ?? 0}',
                          Icons.pending_actions,
                          Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    const SizedBox(height: 32),
                    Text(
                      'Weekly Overview (Last 7 Days)',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Total SOS',
                            '${_data?['weeklyOverview']?['total'] ?? 0}',
                            Icons.history,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Resolved',
                            '${_data?['weeklyOverview']?['resolved'] ?? 0}',
                            Icons.task_alt,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),
                    Text(
                      'Monthly Overview (Last 30 Days)',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            'Total SOS',
                            '${_data?['monthlyOverview']?['total'] ?? 0}',
                            Icons.calendar_month,
                            Colors.indigo,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard(
                            'Resolved',
                            '${_data?['monthlyOverview']?['resolved'] ?? 0}',
                            Icons.done_all,
                            Colors.teal,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    Text(
                      'Peak Incident Times',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: _buildTimeChart(),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }


  List<Widget> _buildTimeChart() {
    final times = _data?['peakIncidentTimes'] as List<dynamic>? ?? [];
    if (times.isEmpty) {
      return [
        const Center(
          child: Text(
            "No time distribution available",
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ];
    }

    int maxCount = 0;
    for (var t in times) {
      if ((t['count'] as int) > maxCount) maxCount = t['count'] as int;
    }

    return times.map((t) {
      final hour = t['_id'] as int? ?? 0;
      final count = t['count'] as int? ?? 0;
      final percent = maxCount > 0 ? (count / maxCount) : 0.0;

      // format hour to AM/PM string
      String label = "";
      if (hour == 0) {
        label = "12AM";
      } else if (hour < 12)
        label = "${hour}AM";
      else if (hour == 12)
        label = "12PM";
      else
        label = "${hour - 12}PM";

      return _buildVerticalBar(
        label,
        percent,
        color: percent > 0.8 ? Colors.red : const Color(0xFF2563EB),
      );
    }).toList();
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildVerticalBar(
    String label,
    double fillPercent, {
    Color color = const Color(0xFF2563EB),
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            width: 30,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              heightFactor: fillPercent,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
