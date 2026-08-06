import express from 'express';
import { 
  triggerSOS, 
  resolveSOS, 
  getActiveAlert,
  alertTrustedContacts,
  alertVolunteers,
  uploadEvidence,
  joinAlert,
  getNearbyAlerts,
  updateAlertStatus,
  getAlertDetails,
  getAlertVictimLocation,
  getVolunteerStats
} from '../controllers/alertController.js';
import { protect } from '../middleware/authMiddleware.js';
import upload from '../middleware/uploadMiddleware.js';

const router = express.Router();

router.use(protect);

router.post('/trigger', triggerSOS);
router.post('/resolve/:id', resolveSOS);
router.get('/active', getActiveAlert);
router.get('/nearby', getNearbyAlerts);
router.get('/volunteer/stats', getVolunteerStats);
router.get('/:id', getAlertDetails);
router.get('/:id/victim-location', getAlertVictimLocation);
router.post('/safety-check/trusted', alertTrustedContacts);
router.post('/safety-check/volunteers', alertVolunteers);
router.post('/evidence/:id', upload('sos').single('evidence'), uploadEvidence);
router.post('/join/:id', joinAlert);
router.put('/status/:id', updateAlertStatus);

export default router;
