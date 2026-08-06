import express from 'express';
import { getSOSMessages, sendSOSMessage } from '../controllers/chatController.js';
import { protect } from '../middleware/authMiddleware.js';

const router = express.Router();

router.use(protect); // All chat routes are protected

router.route('/:alertId')
  .get(getSOSMessages)
  .post(sendSOSMessage);

export default router;
