import express from 'express';
import { sendOtp, verifyOtp, login, register } from '../controllers/authController.js';

const router = express.Router();

// Routes
router.post('/register', register);
router.post('/login', login);
router.post('/send-otp', sendOtp);
router.post('/verify-otp', verifyOtp);

export default router;
