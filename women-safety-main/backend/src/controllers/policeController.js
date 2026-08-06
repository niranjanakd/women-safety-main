import Alert from '../models/Alert.js';
import User from '../models/User.js';
import GuardingSession from '../models/guarding/GuardingSession.js';
import LocationUpdate from '../models/guarding/LocationUpdate.js';
import Incident from '../models/Incident.js';

// @desc    Get all incident reports (Police only)
// @route   GET /api/police/reports
export const getPoliceReports = async (req, res) => {
  try {
    const reports = await Incident.find({ type: { $ne: 'SOS Alert' } })
      .populate('userId', 'name phone profilePhoto userId')
      .sort({ createdAt: -1 });

    res.json({
      success: true,
      data: reports
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update incident report status (Police only)
// @route   PUT /api/police/reports/:id/status
export const updateReportStatus = async (req, res) => {
  try {
    const { status } = req.body;
    const report = await Incident.findById(req.params.id);

    if (!report) {
      return res.status(404).json({ success: false, message: 'Report not found' });
    }

    report.status = status;
    await report.save();

    res.json({
      success: true,
      message: `Report marked as ${status}`,
      data: report
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get all active and in-progress alerts (Police only)
// @route   GET /api/police/alerts/active
export const getPoliceActiveAlerts = async (req, res) => {
  try {
    console.log('--- Fetching Active SOS Alerts ---');
    const alerts = await Alert.find({
      status: { $in: ['active', 'in-progress'] }
    })
    .populate('user', 'name phone profilePhoto')
    .populate('notifiedVolunteers.user', 'name phone')
    .sort({ createdAt: -1 });

    console.log(`Active alerts found: ${alerts.length}`);
    if (alerts.length > 0) {
      alerts.forEach(a => console.log(`Alert: ID=${a._id}, Status=${a.status}, User=${a.user?.name || 'Unknown'}`));
    }
    
    res.json({
      success: true,
      data: alerts
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Flag an alert as fake (Police only)
// @route   PUT /api/police/alerts/:alertId/flag-fake
export const flagFakeAlert = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.alertId);
    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    alert.status = 'resolved'; // Or a new status 'fake' if added to enum
    await alert.save();

    res.json({
      success: true,
      message: 'Alert flagged as fake and closed',
      data: alert
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get pending volunteer applications (Police only)
// @route   GET /api/police/volunteers/pending
export const getPolicePendingVolunteers = async (req, res) => {
  try {
    const volunteers = await User.find({
      role: 'volunteer',
      isApproved: false
    }).select('name phone email address aadhaarNumber createdAt userId');

    res.json({
      success: true,
      data: volunteers
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Verify (Approve/Reject) volunteer (Police only)
// @route   PUT /api/police/volunteers/:userId/verify
export const verifyPoliceVolunteer = async (req, res) => {
  try {
    const { approve } = req.body;
    
    // Check by MongoDB _id first, fallback to string userId
    let userForUpdate;
    if (req.params.userId.length === 24) {
      userForUpdate = await User.findById(req.params.userId);
    }
    if (!userForUpdate) {
      userForUpdate = await User.findOne({ userId: req.params.userId });
    }

    if (!userForUpdate) {
      return res.status(404).json({ success: false, message: 'Volunteer not found' });
    }

    if (approve) {
      userForUpdate.isApproved = true;
      await userForUpdate.save();
    } else {
      // If rejected, we might want to delete or mark as rejected
      await User.deleteOne({ _id: userForUpdate._id });
    }

    res.json({
      success: true,
      message: approve ? 'Volunteer approved successfully' : 'Volunteer application rejected and removed'
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get dashboard analytics (Police only)
// @route   GET /api/police/analytics/dashboard
export const getPoliceAnalytics = async (req, res) => {
  try {
    const activeAlertsCount = await Alert.countDocuments({ status: { $in: ['active', 'active'] } }); // 'active' is pending
    const inProgressCount = await Alert.countDocuments({ status: 'in-progress' });
    const resolvedCount = await Alert.countDocuments({ status: 'done' });
    const pendingVolunteersCount = await User.countDocuments({ role: 'volunteer', isApproved: false });
    const totalReportsCount = await Incident.countDocuments({ type: { $ne: 'SOS Alert' } });
    const pendingReportsCount = await Incident.countDocuments({ status: 'pending', type: { $ne: 'SOS Alert' } });

    // Actual Aggregations
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const weeklyStats = await Alert.aggregate([
      { $match: { createdAt: { $gte: sevenDaysAgo } } },
      { $group: { _id: null, total: { $sum: 1 }, resolved: { $sum: { $cond: [{ $eq: ['$status', 'done'] }, 1, 0] } } } }
    ]);

    const monthlyStats = await Alert.aggregate([
      { $match: { createdAt: { $gte: thirtyDaysAgo } } },
      { $group: { _id: null, total: { $sum: 1 }, resolved: { $sum: { $cond: [{ $eq: ['$status', 'done'] }, 1, 0] } } } }
    ]);

    const peakIncidentTimes = await Alert.aggregate([
      {
        $project: {
          hour: { $hour: '$createdAt' }
        }
      },
      { $group: { _id: '$hour', count: { $sum: 1 } } },
      { $sort: { _id: 1 } }
    ]);

    // Simple Avg Resolution Time (minutes)
    const resolvedAlerts = await Alert.find({ status: 'done', resolvedAt: { $exists: true } });
    let totalResponseTime = 0;
    if (resolvedAlerts.length > 0) {
      resolvedAlerts.forEach(alert => {
        totalResponseTime += (new Date(alert.resolvedAt) - new Date(alert.createdAt)) / (1000 * 60);
      });
    }
    const avgResponseTime = resolvedAlerts.length > 0 ? totalResponseTime / resolvedAlerts.length : 0;

    res.json({
      success: true,
      data: {
        totalSOS: activeAlertsCount + inProgressCount + resolvedCount,
        resolvedSOS: resolvedCount,
        pendingSOS: activeAlertsCount,
        inProgressSOS: inProgressCount,
        weeklyOverview: weeklyStats[0] || { total: 0, resolved: 0 },
        monthlyOverview: monthlyStats[0] || { total: 0, resolved: 0 },
        peakIncidentTimes: peakIncidentTimes.length > 0 ? peakIncidentTimes : [
          { _id: new Date().getHours(), count: 0 }
        ],
        pendingVolunteers: pendingVolunteersCount,
        totalReports: totalReportsCount,
        pendingReports: pendingReportsCount,
        totalResponders: await User.countDocuments({ role: 'volunteer', isApproved: true }) + await User.countDocuments({ role: 'authority' }),
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
// @desc    Get all online volunteers (Police only)
// @route   GET /api/police/volunteers/online
export const getPoliceOnlineResponders = async (req, res) => {
  try {
    const onlineVolunteers = await User.find({
      role: 'volunteer',
      isApproved: true,
      isOnline: true,
      'currentLocation.coordinates': { $exists: true, $ne: [] }
    }).select('name phone currentLocation userId');

    res.json({
      success: true,
      data: onlineVolunteers
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get all active guarding sessions (Police only)
// @route   GET /api/police/guarding/active
export const getPoliceActiveGuardingSessions = async (req, res) => {
  try {
    const activeSessions = await GuardingSession.find({ status: 'ACTIVE' });
    const sessionIds = activeSessions.map(s => s.session_id);

    // Get latest location for each active session
    const results = await Promise.all(activeSessions.map(async (session) => {
      const latestLocation = await LocationUpdate.findOne({ session_id: session.session_id })
        .sort({ timestamp: -1 })
        .populate('userId', 'name phone profilePhoto');
      
      if (latestLocation) {
        return {
          session_id: session.session_id,
          userId: latestLocation.userId,
          latitude: latestLocation.latitude,
          longitude: latestLocation.longitude,
          timestamp: latestLocation.timestamp
        };
      }
      return null;
    }));

    res.json({
       success: true,
       data: results.filter(r => r !== null)
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
