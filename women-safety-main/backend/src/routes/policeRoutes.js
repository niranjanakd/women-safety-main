import express from 'express';
import {
  getPoliceActiveAlerts,
  flagFakeAlert,
  getPolicePendingVolunteers,
  verifyPoliceVolunteer,
  getPoliceAnalytics,
  getPoliceOnlineResponders,
  getPoliceActiveGuardingSessions,
  getPoliceReports,
  updateReportStatus
} from '../controllers/policeController.js';
import { protect } from '../middleware/authMiddleware.js';
import { authorizeRoles } from '../middleware/roleMiddleware.js';

const router = express.Router();

// All police routes require authentication and 'authority' role
router.use(protect);
router.use(authorizeRoles('authority'));

// Alerts Management
router.get('/alerts/active', getPoliceActiveAlerts);
router.put('/alerts/:alertId/flag-fake', flagFakeAlert);

// Volunteer Management
router.get('/volunteers/pending', getPolicePendingVolunteers);
router.put('/volunteers/:userId/verify', verifyPoliceVolunteer);
router.get('/volunteers/online', getPoliceOnlineResponders);

// Dashboard Analytics
router.get('/analytics/dashboard', getPoliceAnalytics);

// Guarding Monitoring
router.get('/guarding/active', getPoliceActiveGuardingSessions);

// Incident Reports
router.get('/reports', getPoliceReports);
router.put('/reports/:id/status', updateReportStatus);

export default router;
