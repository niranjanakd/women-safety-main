import express from 'express';
import { getResources, createResource } from '../controllers/resourceController.js';

const router = express.Router();

router.route('/').get(getResources).post(createResource);

export default router;
