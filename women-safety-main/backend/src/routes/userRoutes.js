import express from 'express';
import { 
  getUserProfile, 
  updateUserProfile, 
  changePassword, 

  addTrustedContact, 
  removeTrustedContact,
  updateTrustedContact,
  uploadProfilePhoto,
  toggleOnlineStatus,
  getPendingProfileUpdates,
  approveProfileUpdate,
  rejectProfileUpdate,
  getUnapprovedVolunteers,
  approveVolunteerAccount,
  rejectVolunteerAccount,
  sendProfileUpdateOtp
} from '../controllers/userController.js';
import { protect } from '../middleware/authMiddleware.js';
import { authorizeRoles } from '../middleware/roleMiddleware.js';
import upload from '../middleware/uploadMiddleware.js';

const router = express.Router();

// Require auth for all user routes
router.use(protect);

router.get('/profile', getUserProfile);
router.put('/update-profile', updateUserProfile);
router.post('/send-profile-update-otp', sendProfileUpdateOtp);
router.put('/change-password', changePassword);
router.post('/profile/photo', upload('profiles').single('image'), uploadProfilePhoto);
router.put('/status', toggleOnlineStatus);

// Trusted Contacts Management
router.post('/trusted-contacts', addTrustedContact);
router.put('/trusted-contacts/:contactId', updateTrustedContact);
router.delete('/trusted-contacts/:contactId', removeTrustedContact);

// Example of an Admin/Authority only route
router.get('/admin-data', authorizeRoles('authority', 'volunteer'), (req, res) => {
  res.json({ message: "Admin area accessed" })
});

// Volunteer Profile Approval (Authority Only)
router.get('/pending-updates', authorizeRoles('authority'), getPendingProfileUpdates);
router.post('/approve-update/:userId', authorizeRoles('authority'), approveProfileUpdate);
router.post('/reject-update/:userId', authorizeRoles('authority'), rejectProfileUpdate);

// New Volunteer Account Approval (Authority Only)
router.get('/unapproved-volunteers', authorizeRoles('authority'), getUnapprovedVolunteers);
router.post('/approve-volunteer/:userId', authorizeRoles('authority'), approveVolunteerAccount);
router.delete('/reject-volunteer/:userId', authorizeRoles('authority'), rejectVolunteerAccount);

export default router;
