import express from 'express';
import {
  getActiveSessions,
  getLiveLocation,
  getUserContact,
  sendCheckInRequest,
  updateLocation,
  updateRoutePoints,
  startSession,
  stopSession,
  updateSessionStatus,
  verifyCheckIn,
  getPublicLiveLocation
} from '../controllers/trustedController.js';
import { protect } from '../middleware/authMiddleware.js';

const router = express.Router();

router.get('/public/track/:shareToken', getPublicLiveLocation);

router.use(protect); // All dashboard routes are protected

router.get('/trusted/active-sessions', getActiveSessions);
router.get('/session/live-location/:sessionId', getLiveLocation);
router.get('/user/contact/:sessionId', getUserContact);
router.post('/session/checkin-request', sendCheckInRequest);
router.post('/session/update-location', updateLocation);
router.post('/session/update-route', updateRoutePoints);
router.post('/session/start', startSession);
router.post('/session/stop/:sessionId', stopSession);
router.post('/session/status', updateSessionStatus);
router.post('/session/verify-checkin', verifyCheckIn);

export default router;
