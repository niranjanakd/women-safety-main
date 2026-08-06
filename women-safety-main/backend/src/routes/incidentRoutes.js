import express from 'express';
import { 
  createIncident, 
  getIncidents, 
  getMyIncidents,
  getMapIncidents
} from '../controllers/incidentController.js';
import { protect } from '../middleware/authMiddleware.js';
import { authorizeRoles } from '../middleware/roleMiddleware.js';
import upload from '../middleware/uploadMiddleware.js';

const router = express.Router();

router.use(protect);

router.post('/', upload('incidents').array('proofs', 5), createIncident);
router.get('/', authorizeRoles('authority', 'volunteer'), getIncidents);
router.get('/map', getMapIncidents);
router.get('/my', getMyIncidents);

export default router;
