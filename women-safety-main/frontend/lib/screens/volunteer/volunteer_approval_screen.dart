import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api_service.dart';

class VolunteerApprovalScreen extends StatefulWidget {
  const VolunteerApprovalScreen({super.key});

  @override
  State<VolunteerApprovalScreen> createState() =>
      _VolunteerApprovalScreenState();
}

class _VolunteerApprovalScreenState extends State<VolunteerApprovalScreen> {
  bool _isLoadingAccounts = true;
  bool _isLoadingUpdates = true;
  List<dynamic> _unapprovedAccounts = [];
  List<dynamic> _pendingUpdates = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    _fetchUnapprovedAccounts();
    _fetchPendingUpdates();
  }

  Future<void> _fetchUnapprovedAccounts() async {
    setState(() => _isLoadingAccounts = true);
    final result = await ApiService.getPolicePendingVolunteers();
    if (mounted) {
      setState(() {
        _unapprovedAccounts = result['success'] ? result['data'] : [];
        _isLoadingAccounts = false;
      });
    }
  }

  Future<void> _fetchPendingUpdates() async {
    setState(() => _isLoadingUpdates = true);
    final result = await ApiService.getPendingProfileUpdates();
    if (mounted) {
      setState(() {
        _pendingUpdates = result['success'] ? result['data'] : [];
        _isLoadingUpdates = false;
      });
    }
  }

  Future<void> _handleAccountAction(String userId, bool approve) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      ),
    );

    final result = await ApiService.verifyPoliceVolunteer(userId, approve);

    if (!mounted) return;
    Navigator.pop(context);

    if (result['success']) {
      setState(() {
        _unapprovedAccounts.removeWhere(
          (u) => (u['_id'] ?? u['userId']) == userId,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Account approved' : 'Application rejected'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Action failed')),
      );
    }
  }

  Future<void> _handleUpdateAction(String userId, bool approve) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      ),
    );

    final result = approve
        ? await ApiService.approveProfileUpdate(userId)
        : await ApiService.rejectProfileUpdate(userId);

    if (!mounted) return;
    Navigator.pop(context);

    if (result['success']) {
      setState(() {
        _pendingUpdates.removeWhere((u) => (u['_id'] ?? u['userId']) == userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Update approved' : 'Update rejected'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Action failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF2563EB),
          title: Text(
            'Volunteer Approvals',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'New Accounts'),
              Tab(text: 'Profile Updates'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(children: [_buildAccountTab(), _buildUpdateTab()]),
      ),
    );
  }

  Widget _buildAccountTab() {
    if (_isLoadingAccounts) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      );
    }
    if (_unapprovedAccounts.isEmpty) {
      return _buildEmptyState('No new account registrations');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _unapprovedAccounts.length,
      itemBuilder: (context, index) =>
          _buildAccountCard(_unapprovedAccounts[index]),
    );
  }

  Widget _buildUpdateTab() {
    if (_isLoadingUpdates) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2563EB)),
      );
    }
    if (_pendingUpdates.isEmpty) {
      return _buildEmptyState('No pending profile updates');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingUpdates.length,
      itemBuilder: (context, index) => _buildUpdateCard(_pendingUpdates[index]),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_turned_in_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(dynamic user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                      child: const Icon(
                        Icons.person,
                        color: Color(0xFF2563EB),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] ?? 'Unknown',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Requested recently',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.phone, user['phone'] ?? 'No phone'),
                _buildInfoRow(
                  Icons.location_on,
                  user['address'] ?? user['permanentAddress'] ?? "No address",
                ),
                _buildInfoRow(
                  Icons.badge,
                  'Aadhaar: ${user['aadhaarNumber'] ?? "Not provided"}',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleAccountAction(
                      user['_id'] ?? user['userId'],
                      false,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleAccountAction(
                      user['_id'] ?? user['userId'],
                      true,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateCard(dynamic update) {
    final pending = update['pendingUpdate'];
    if (pending == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                      child: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        update['name'] ?? 'System Update',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                _buildChangeRow('Name', update['name'], pending['name']),
                _buildChangeRow('Phone', update['phone'], pending['phone']),
                _buildChangeRow(
                  'Address',
                  update['address'],
                  pending['address'],
                ),
                _buildChangeRow(
                  'Permanent',
                  update['permanentAddress'],
                  pending['permanentAddress'],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleUpdateAction(
                      update['_id'] ?? update['userId'],
                      false,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleUpdateAction(
                      update['_id'] ?? update['userId'],
                      true,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeRow(String label, dynamic current, dynamic proposed) {
    if (proposed == null || proposed == current) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  current ?? 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                    color: Colors.red.shade400,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  proposed ?? 'N/A',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
