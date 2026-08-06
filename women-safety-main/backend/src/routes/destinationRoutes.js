import express from 'express';
import {
  getDestinations,
  addDestination,
  deleteDestination,
} from '../controllers/destinationController.js';
import { protect } from '../middleware/authMiddleware.js';

const router = express.Router();

router.route('/')
  .get(protect, getDestinations)
  .post(protect, addDestination);

router.route('/:id')
  .delete(protect, deleteDestination);

export default router;
