import User from '../models/User.js';
import Destination from '../models/Destination.js';
import bcrypt from 'bcryptjs';
import Otp from '../models/Otp.js';
import { sendSMS } from '../utils/mail.js';

// @desc    Get user profile
// @route   GET /api/user/profile
// @access  Private
export const getUserProfile = async (req, res) => {
  try {
    const user = await User.findUserByMongoId(req.user._id);

    if (user) {
      // Fetch destinations separately as they are not stored in the user model
      const destinations = await Destination.find({ user: user._id });

      res.json({
        _id: user.id,
        userId: user.userId,
        name: user.name,
        email: user.email,
        phone: user.phone,
        address: user.address,
        permanentAddress: user.permanentAddress,
        profilePhoto: user.profilePhoto,
        role: user.role,
        guardianModeEnabled: user.guardianModeEnabled,
        trustedContacts: user.trustedContacts,
        currentLocation: user.currentLocation,
        sosTriggerWord: user.sosTriggerWord,
        destinations: destinations // Added this
      });
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Update user profile
// @route   PUT /api/user/update-profile
// @access  Private
export const updateUserProfile = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);

    if (user) {
      // Logic change: Volunteers' changes go to pendingUpdate
      if (user.role === 'volunteer') {
        const { otp } = req.body;
        if (!otp) {
            return res.status(400).json({ message: 'OTP is required to update profile' });
        }
        
        const formattedPhone = user.phone;
        const otpRecord = await Otp.findOne({ phone: formattedPhone, otp });
        if (!otpRecord) {
            return res.status(400).json({ message: 'Invalid or expired OTP' });
        }
        await Otp.deleteOne({ _id: otpRecord._id });

        user.pendingUpdate = {
          name: req.body.name || user.name,
          phone: req.body.phone || user.phone,
          address: req.body.address || user.address,
          permanentAddress: req.body.permanentAddress || user.permanentAddress,
          submittedAt: new Date(),
        };
        await user.save();
        return res.json({
          message: 'Profile update submitted and pending authority approval',
          isPending: true
        });
      }

      // Standard user logic (unchanged)
      user.name = req.body.name || user.name;
      user.email = req.body.email || user.email;
      user.phone = req.body.phone || user.phone;
      user.address = req.body.address || user.address;
      user.permanentAddress = req.body.permanentAddress || user.permanentAddress;
      user.guardianModeEnabled = req.body.guardianModeEnabled !== undefined ? req.body.guardianModeEnabled : user.guardianModeEnabled;
      user.sosTriggerWord = req.body.sosTriggerWord || user.sosTriggerWord;
      
      if (req.body.currentLocation) {
        user.currentLocation = req.body.currentLocation;
      }

      const updatedUser = await user.save();

      res.json({
        _id: updatedUser._id,
        userId: updatedUser.userId,
        name: updatedUser.name,
        email: updatedUser.email,
        phone: updatedUser.phone,
        address: updatedUser.address,
        permanentAddress: updatedUser.permanentAddress,
        profilePhoto: updatedUser.profilePhoto,
        role: updatedUser.role,
      });
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Send OTP for profile update
// @route   POST /api/user/send-profile-update-otp
// @access  Private
export const sendProfileUpdateOtp = async (req, res) => {
    try {
        const user = await User.findById(req.user._id);
        if (!user) return res.status(404).json({ message: 'User not found' });
        
        const otpValue = Math.floor(100000 + Math.random() * 900000).toString();
        const formattedPhone = user.phone;
        
        await Otp.findOneAndUpdate(
            { phone: formattedPhone },
            { otp: otpValue, createdAt: new Date() },
            { upsert: true }
        );
        
        await sendSMS({ to: formattedPhone, message: `Your profile update OTP is ${otpValue}. Valid for 5 minutes.`, otp: otpValue });
        
        res.status(200).json({ success: true, message: 'OTP sent to your registered phone number' });
    } catch (error) {
        res.status(500).json({ message: error.message });
    }
};

// @desc    Change user password
// @route   PUT /api/user/change-password
// @access  Private
export const changePassword = async (req, res) => {
  try {
    const { oldPassword, newPassword } = req.body;
    
    // Explicitly grab user with password
    const user = await User.findById(req.user._id);

    if (user && (await bcrypt.compare(oldPassword, user.passwordHash))) {
      const salt = await bcrypt.genSalt(10);
      user.passwordHash = await bcrypt.hash(newPassword, salt);
      
      await user.save();
      res.json({ message: 'Password updated successfully' });
    } else {
      res.status(401).json({ message: 'Invalid old password' });
    }
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Add a trusted emergency contact
// @route   POST /api/user/trusted-contacts
// @access  Private
export const addTrustedContact = async (req, res) => {
  try {
     const { name, phone, relation } = req.body;
     
     if(!name || !phone || !relation) {
        return res.status(400).json({ message: "Missing required contact fields" });
     }

     console.log(`➕ ADDING CONTACT: User ${req.user.name} adding ${name} (${phone})`);
     const updatedUser = await User.addTrustedContact(req.user.userId, { name, phone, relation });
     
     // --- ADDED SYNC LOGIC ---
     // 1. Find if this phone exists in our database (Normalize for various formats)
     const phoneVariants = [phone];
     if (phone.startsWith('+91')) phoneVariants.push(phone.replace('+91', ''));
     else if (phone.length === 10) phoneVariants.push(`+91${phone}`);

     const matchedUser = await User.findOne({ phone: { $in: phoneVariants } });
     if (matchedUser) {
        // 2. Create the bidirectional link in TrustedContact collection for dashboard tracking
        const TrustedContact = (await import('../models/TrustedContact.js')).default;
        await TrustedContact.findOneAndUpdate(
          { ownerUserId: req.user._id, trustedUserId: matchedUser._id },
          { relationship: relation },
          { upsert: true }
        );
        console.log(`🔗 TrustedContact link created: User ${req.user.name} trusts ${matchedUser.name}`);
     }

     res.status(200).json(updatedUser.trustedContacts);

  } catch (error) {
     res.status(500).json({ message: error.message });
  }
};

// @desc    Remove a trusted emergency contact
// @route   DELETE /api/user/trusted-contacts/:contactId
// @access  Private
export const removeTrustedContact = async (req, res) => {
  try {
     const user = await User.findUserById(req.user.userId);
     const contactToRemove = user.trustedContacts.id(req.params.contactId);
     
     if (contactToRemove) {
        // Find if this contact's phone was linked in TrustedContact collection
        const phone = contactToRemove.phone;
        const phoneVariants = [phone];
        if (phone.startsWith('+91')) phoneVariants.push(phone.replace('+91', ''));
        else if (phone.length === 10) phoneVariants.push(`+91${phone}`);

        const matchedUser = await User.findOne({ phone: { $in: phoneVariants } });
        if (matchedUser) {
           const TrustedContact = (await import('../models/TrustedContact.js')).default;
           await TrustedContact.findOneAndDelete({ 
             ownerUserId: req.user._id, 
             trustedUserId: matchedUser._id 
           });
           console.log(`🗑️ TrustedContact link removed: User ${req.user.name} untrusts ${matchedUser.name}`);
        }
     }

     console.log(`🗑️ REMOVING CONTACT: User ${req.user.name} removing contact ${req.params.contactId}`);
     const updatedUser = await User.removeTrustedContact(req.user.userId, req.params.contactId);
     res.status(200).json(updatedUser.trustedContacts);
  } catch (error) {
     res.status(500).json({ message: error.message });
  }
};

// @desc    Upload profile photo
// @route   POST /api/user/profile/photo
// @access  Private
// ...
export const uploadProfilePhoto = async (req, res) => {
  try {
    const user = await User.findUserByMongoId(req.user._id);

    if (user) {
      if (req.file) {
        // Construct URL using req.file.path redirected through the /uploads static route
        // Normalize slashes for Windows compatibility
        const normalizedPath = req.file.path.replace(/\\/g, '/');
        user.profilePhoto = `/${normalizedPath}`;
        
        await user.save();
        res.json({ message: 'Profile photo updated', profilePhoto: user.profilePhoto });
      } else {
        res.status(400).json({ message: 'No image file provided' });
      }
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Update a trusted emergency contact
// @route   PUT /api/user/trusted-contacts/:contactId
// @access  Private
export const updateTrustedContact = async (req, res) => {
  try {
     const { name, phone, relation } = req.body;
     const contactId = req.params.contactId;

     if(!name && !phone && !relation) {
        return res.status(400).json({ message: "No update fields provided" });
     }

     console.log(`✏️ UPDATING CONTACT: User ${req.user.name} updating contact ${contactId} to ${name} (${phone})`);
     const updatedUser = await User.updateTrustedContact(req.user.userId, contactId, { name, phone, relation });
     
     if (!updatedUser) {
        return res.status(404).json({ message: "User or Contact not found" });
     }

     res.status(200).json(updatedUser.trustedContacts);
  } catch (error) {
     res.status(500).json({ message: error.message });
  }
};

// @desc    Toggle volunteer online status
// @route   PUT /api/user/status
// @access  Private
export const toggleOnlineStatus = async (req, res) => {
  try {
    const { isOnline } = req.body;
    
    // Only allow volunteers to change online status (authorities/users could too but mainly for volunteers)
    if (req.user.role !== 'volunteer') {
      return res.status(403).json({ message: 'Only volunteers can toggle online status' });
    }

    const user = await User.findById(req.user._id);

    if (user) {
      user.isOnline = isOnline;
      await user.save();
      
      console.log(`📡 Volunteer ${user.name} is now ${isOnline ? 'ONLINE' : 'OFFLINE'}`);

      res.json({
        success: true,
        message: `Status updated to ${isOnline ? 'Online' : 'Offline'}`,
        isOnline: user.isOnline
      });
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Get all pending profile updates
// @route   GET /api/user/pending-updates
// @access  Private (Authority only)
export const getPendingProfileUpdates = async (req, res) => {
  try {
    const users = await User.find({ 'pendingUpdate.submittedAt': { $exists: true } })
      .select('name email phone address pendingUpdate profilePhoto userId');
    res.json({ success: true, data: users });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Approve a profile update
// @route   POST /api/user/approve-update/:userId
// @access  Private (Authority only)
export const approveProfileUpdate = async (req, res) => {
  try {
    const { userId: idParam } = req.params;
    let user;
    if (idParam.length === 24) {
      user = await User.findById(idParam);
    }
    if (!user) {
      user = await User.findOne({ userId: idParam });
    }
    if (!user) {
      user = await User.findOne({ phone: idParam });
    }

    if (!user || !user.pendingUpdate) {
      return res.status(404).json({ message: 'Pending update not found' });
    }

    // Apply pending changes
    user.name = user.pendingUpdate.name || user.name;
    user.phone = user.pendingUpdate.phone || user.phone;
    user.address = user.pendingUpdate.address || user.address;
    user.permanentAddress = user.pendingUpdate.permanentAddress || user.permanentAddress;
    if (user.pendingUpdate.profilePhoto) {
      user.profilePhoto = user.pendingUpdate.profilePhoto;
    }

    // Clear pending update
    user.pendingUpdate = undefined;
    await user.save();

    res.json({ success: true, message: 'Update approved and applied' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Reject a profile update
// @route   POST /api/user/reject-update/:userId
// @access  Private (Authority only)
export const rejectProfileUpdate = async (req, res) => {
  try {
    const { userId: idParam } = req.params;
    let user;
    if (idParam.length === 24) {
      user = await User.findById(idParam);
    }
    if (!user) {
      user = await User.findOne({ userId: idParam });
    }
    if (!user) {
      user = await User.findOne({ phone: idParam });
    }

    if (!user || !user.pendingUpdate) {
      return res.status(404).json({ message: 'Pending update not found' });
    }

    // Clear pending update without applying
    user.pendingUpdate = undefined;
    await user.save();

    res.json({ success: true, message: 'Update rejected' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Get all unapproved volunteer accounts
// @route   GET /api/user/unapproved-volunteers
// @access  Private (Authority only)
export const getUnapprovedVolunteers = async (req, res) => {
  try {
    const users = await User.find({ role: 'volunteer', isApproved: false })
      .select('name email phone permanentAddress currentAddressString aadhaarNumber createdAt userId');
    res.json({ success: true, data: users });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Approve a volunteer account
// @route   POST /api/user/approve-volunteer/:userId
// @access  Private (Authority only)
export const approveVolunteerAccount = async (req, res) => {
  try {
    const { userId: idParam } = req.params;
    let user;
    if (idParam.length === 24) {
      user = await User.findById(idParam);
    }
    if (!user) {
      user = await User.findOne({ userId: idParam, role: 'volunteer' });
    }

    if (!user) {
      return res.status(404).json({ message: 'Volunteer account not found' });
    }

    user.isApproved = true;
    await user.save();

    res.json({ success: true, message: 'Volunteer account approved' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Reject a volunteer account (Delete the application)
// @route   DELETE /api/user/reject-volunteer/:userId
// @access  Private (Authority only)
export const rejectVolunteerAccount = async (req, res) => {
  try {
    const { userId: idParam } = req.params;
    let user;
    if (idParam.length === 24) {
      user = await User.findById(idParam);
    }
    if (!user) {
      user = await User.findOne({ userId: idParam, role: 'volunteer' });
    }

    if (!user) {
      return res.status(404).json({ message: 'Volunteer account not found' });
    }

    if (user.isApproved) {
      return res.status(400).json({ message: 'Cannot reject an already approved account' });
    }

    await User.deleteOne({ userId: req.params.userId });
    res.json({ success: true, message: 'Volunteer account application rejected and removed' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
