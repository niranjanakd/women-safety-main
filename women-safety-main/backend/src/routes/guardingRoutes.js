import express from 'express';
import {
  registerProfile,
  startGuarding,
  stopGuarding,
  updateLocation,
  triggerEmergency,
  createShareLink,
  getSharedLocation,
  triggerFakeCall,
  triggerFakeVideo
} from '../controllers/guardingController.js';

const router = express.Router();

// Profile Management
router.post('/profile/register', registerProfile);

// Guarding Session
router.post('/guard/start', startGuarding);
router.post('/guard/stop', stopGuarding);

// Location Tracking
router.post('/location/update', updateLocation);

// Emergency Alert
router.post('/alert/emergency', triggerEmergency);

// Share Location
router.post('/share/create', createShareLink);
router.get('/share/:token', getSharedLocation);

// Fake Events
router.post('/event/fake-call', triggerFakeCall);
router.post('/event/fake-video', triggerFakeVideo);

export default router;
