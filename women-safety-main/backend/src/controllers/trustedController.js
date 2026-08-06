import TrustedContact from '../models/TrustedContact.js';
import TravelSession from '../models/TravelSession.js';
import CheckInRequest from '../models/CheckInRequest.js';
import User from '../models/User.js';
import mongoose from 'mongoose';
import crypto from 'crypto';

// @desc    Get all active sessions where the logged-in user is a trusted contact
// @route   GET /api/trusted/active-sessions
// @access  Private
export const getActiveSessions = async (req, res) => {
  try {
    const loggedInUserId = req.user._id;

    // 1. Find who has added me as a trusted contact
    const trustedLinks = await TrustedContact.find({ trustedUserId: loggedInUserId });
    const monitoredUserIds = trustedLinks.map(link => link.ownerUserId);

    if (monitoredUserIds.length === 0) {
      return res.json({ success: true, data: [] });
    }

    // 2. Find active Travel Sessions
    const travelSessions = await TravelSession.find({
      userId: { $in: monitoredUserIds },
      status: 'active'
    }).populate('userId', 'name phone');

    // 3. Find active Guarding Sessions
    const GuardingSession = (await import('../models/guarding/GuardingSession.js')).default;
    const LocationUpdate = (await import('../models/guarding/LocationUpdate.js')).default;
    
    const guardingSessions = await GuardingSession.find({
      userId: { $in: monitoredUserIds },
      status: 'ACTIVE'
    }).populate('userId', 'name phone');

    // 4. Map Guarding Sessions to TravelSession format
    const mappedGuarding = await Promise.all(guardingSessions.map(async (gs) => {
      // Get latest location for this session
      const latestLoc = await LocationUpdate.findOne({ session_id: gs.session_id })
        .sort({ timestamp: -1 });

      return {
        _id: gs.session_id, // Use session_id as the unique key
        userId: gs.userId,
        startTime: gs.start_time,
        status: 'active',
        lastLocationUpdate: latestLoc ? latestLoc.timestamp : gs.start_time,
        destination: {
          address: 'Guardian Mode Tracking',
          coordinates: { lat: 0, lng: 0 }
        },
        currentLocation: {
          type: 'Point',
          coordinates: latestLoc ? [latestLoc.longitude, latestLoc.latitude] : [0, 0]
        },
        isGuardingMode: true // Flag for frontend
      };
    }));

    // 5. Combine and return
    const combined = [...travelSessions, ...mappedGuarding];
    
    // Sort by latest update first
    const finalSessions = combined.sort((a, b) => {
      const dateA = new Date(a.lastLocationUpdate || a.startTime);
      const dateB = new Date(b.lastLocationUpdate || b.startTime);
      return dateB - dateA;
    });

    res.json({ success: true, data: finalSessions });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get live location of a session (Security: Only trusted contacts)
// @route   GET /api/session/live-location/:sessionId
// @access  Private
export const getLiveLocation = async (req, res) => {
  try {
    const { sessionId } = req.params;
    let session;
    let isGuarding = false;

    // 1. Try finding in TravelSession
    if (mongoose.Types.ObjectId.isValid(sessionId)) {
      session = await TravelSession.findById(sessionId);
    }

    // 2. Try finding in GuardingSession (session_id is UUID string)
    if (!session) {
      const GuardingSession = (await import('../models/guarding/GuardingSession.js')).default;
      session = await GuardingSession.findOne({ session_id: sessionId });
      if (session) isGuarding = true;
    }

    if (!session) {
      return res.status(404).json({ success: false, message: 'Session not found' });
    }

    const userId = isGuarding ? session.userId : session.userId;

    // Security Check: Is req.user a trusted contact for session owner?
    const isTrusted = await TrustedContact.findOne({
      ownerUserId: userId,
      trustedUserId: req.user._id
    });

    if (!isTrusted && userId.toString() !== req.user._id.toString()) {
      return res.status(403).json({ success: false, message: 'Not authorized' });
    }

    // Get traveled path history (from LocationUpdate collection)
    const LocationUpdate = (await import('../models/guarding/LocationUpdate.js')).default;
    const history = await LocationUpdate.find({ 
      session_id: sessionId // For both types, we use the sessionId passed in
    }) 
      .sort({ timestamp: -1 })
      .limit(50)
      .select('latitude longitude timestamp -_id');

    if (history.length === 0 && isGuarding) {
      return res.status(404).json({ success: false, message: 'No location data available yet' });
    }

    const latest = history[0] || { 
      latitude: session.currentLocation.coordinates[1], 
      longitude: session.currentLocation.coordinates[0], 
      timestamp: session.lastLocationUpdate 
    };

    res.json({
      success: true,
      data: {
        latitude: latest.latitude,
        longitude: latest.longitude,
        timestamp: latest.timestamp,
        path: history.reverse(),
        destination: session.destination,
        routePoints: session.routePoints || []
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get phone number of the session owner (Security: Only trusted contacts)
// @route   GET /api/user/contact/:sessionId
// @access  Private
export const getUserContact = async (req, res) => {
  try {
    const { sessionId } = req.params;
    let session;

    if (mongoose.Types.ObjectId.isValid(sessionId)) {
      session = await TravelSession.findById(sessionId).populate('userId', 'phone');
    }

    if (!session) {
      const GuardingSession = (await import('../models/guarding/GuardingSession.js')).default;
      session = await GuardingSession.findOne({ session_id: sessionId }).populate('userId', 'phone');
    }

    if (!session) {
      return res.status(404).json({ success: false, message: 'Session not found' });
    }

    const isTrusted = await TrustedContact.findOne({
      ownerUserId: session.userId._id,
      trustedUserId: req.user._id
    });

    if (!isTrusted) {
      return res.status(403).json({ success: false, message: 'Not authorized' });
    }

    res.json({
      success: true,
      data: { phoneNumber: session.userId.phone }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Request a check-in from the user
// @route   POST /api/session/checkin-request
// @access  Private
export const sendCheckInRequest = async (req, res) => {
  try {
    const { sessionId } = req.body;
    const session = await TravelSession.findById(sessionId);

    if (!session || (session.status !== 'active' && session.status !== 'checking')) {
      return res.status(400).json({ success: false, message: 'Active or checking session required' });
    }

    if (session.status === 'checking') {
      return res.status(400).json({ success: false, message: 'A safety check is already in progress' });
    }

    // Check if there's already a pending request for this session
    const existingRequest = await CheckInRequest.findOne({ sessionId, status: 'pending' });
    if (existingRequest) {
      return res.status(400).json({ success: false, message: 'A check-in request is already pending for this session' });
    }

    // Store the request
    const checkIn = await CheckInRequest.create({
      sessionId,
      trustedContactId: req.user._id,
      status: 'pending',
      type: req.body.type || 'manual'
    });

    // Mock Notification logic
    console.log(`🔔 [${checkIn.type.toUpperCase()}] Check-in request sent to user ${session.userId} for session ${sessionId}`);

    // Logic for timeout (3 minutes)
    setTimeout(async () => {
      try {
        const currentReq = await CheckInRequest.findById(checkIn._id);
        if (currentReq && currentReq.status === 'pending') {
          currentReq.status = 'missed';
          await currentReq.save();
          
          // Update session status
          const missedSession = await TravelSession.findByIdAndUpdate(
            sessionId, 
            { status: 'missed-checkin' }, 
            { new: true }
          );
          
          // Notify all trusted contacts about the miss
          if (missedSession) {
            const trustedLinks = await TrustedContact.find({ 
              ownerUserId: missedSession.userId 
            }).populate('trustedUserId', 'name phone');
            
            console.log(`⚠️ [MISSED CHECK-IN] Session: ${sessionId} | User: ${missedSession.userId}`);
            trustedLinks.forEach(link => {
              console.log(`  📱 Notifying: ${link.trustedUserId?.name} (${link.trustedUserId?.phone}) — "User missed a check-in. Please verify they are safe."`);
            });
          }
        }
      } catch (e) {
        console.error('Check-in timeout handler error:', e.message);
      }
    }, 3 * 60 * 1000); // 3 minutes

    res.status(201).json({ success: true, data: checkIn });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update location (called by User's device)
// @route   POST /api/session/update-location
// @access  Private
export const updateLocation = async (req, res) => {
  try {
    const { sessionId, latitude, longitude } = req.body;

    const session = await TravelSession.findOneAndUpdate(
      { _id: sessionId, userId: req.user._id },
      { 
        'currentLocation.coordinates': [longitude, latitude],
        lastLocationUpdate: new Date()
      },
      { returnDocument: 'after' }
    );

    if (!session) {
      return res.status(404).json({ success: false, message: 'Active session not found for this user' });
    }

    res.json({ success: true, data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update route points for a session (called after directions are fetched)
// @route   POST /api/trusted-dashboard/session/update-route
// @access  Private
export const updateRoutePoints = async (req, res) => {
  try {
    const { sessionId, routePoints } = req.body;
    const session = await TravelSession.findOneAndUpdate(
      { _id: sessionId, userId: req.user._id },
      { routePoints: routePoints || [] },
      { returnDocument: 'after' }
    );
    if (!session) {
      return res.status(404).json({ success: false, message: 'Active session not found for this user' });
    }
    res.json({ success: true, data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Start a travel session
// @route   POST /api/trusted-dashboard/session/start
// @access  Private
export const startSession = async (req, res) => {
  try {
    const { destinationAddress, lat, lng } = req.body;
    const userId = req.user._id;

    // End any existing active sessions
    await TravelSession.updateMany({ userId, status: 'active' }, { status: 'completed', endTime: new Date() });

    const session = await TravelSession.create({
      userId,
      destination: {
        address: destinationAddress,
        coordinates: { lat, lng }
      },
      currentLocation: {
        type: 'Point',
        coordinates: [lng || 0, lat || 0]
      },
      routePoints: req.body.routePoints || [],
      shareToken: crypto.randomUUID(),
      status: 'active'
    });

    res.status(201).json({ success: true, data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Stop a travel session
// @route   POST /api/trusted-dashboard/session/stop/:sessionId
// @access  Private
export const stopSession = async (req, res) => {
  try {
    const { sessionId } = req.params;
    const session = await TravelSession.findOneAndUpdate(
      { _id: sessionId, userId: req.user._id },
      { status: 'completed', endTime: new Date() },
      { returnDocument: 'after' }
    );

    if (!session) {
      return res.status(404).json({ success: false, message: 'Active session not found' });
    }

    res.json({ success: true, data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Update session status (e.g., to missed-checkin)
// @route   POST /api/trusted-dashboard/session/status
// @access  Private
export const updateSessionStatus = async (req, res) => {
  try {
    const { sessionId, status } = req.body;
    
    // Only allow specific statuses for safety
    if (!['active', 'completed', 'missed-checkin', 'checking'].includes(status)) {
      return res.status(400).json({ success: false, message: 'Invalid status' });
    }

    const session = await TravelSession.findOneAndUpdate(
      { _id: sessionId, userId: req.user._id },
      { status },
      { returnDocument: 'after' }
    );

    if (!session) {
      return res.status(404).json({ success: false, message: 'Session not found' });
    }

    res.json({ success: true, data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Verify/Confirm a check-in (clears flags and resets status)
// @route   POST /api/trusted-dashboard/session/verify-checkin
// @access  Private
export const verifyCheckIn = async (req, res) => {
  try {
    const { sessionId } = req.body;
    const userId = req.user._id;

    // 1. Mark all pending check-in requests as 'confirmed'
    await CheckInRequest.updateMany(
      { sessionId, status: 'pending' },
      { status: 'confirmed', confirmedAt: new Date() }
    );

    // 2. Reset session status to 'active'
    const session = await TravelSession.findOneAndUpdate(
      { _id: sessionId, userId },
      { status: 'active', lastUpdate: new Date() },
      { returnDocument: 'after' }
    );

    if (!session) {
      return res.status(404).json({ success: false, message: 'Active session not found' });
    }

    res.json({ success: true, message: 'Check-in verified successfully', data: session });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get public live location for anonymous tracking
// @route   GET /api/trusted-dashboard/public/track/:shareToken
// @access  Public
export const getPublicLiveLocation = async (req, res) => {
  try {
    const { shareToken } = req.params;

    const session = await TravelSession.findOne({ shareToken, status: 'active' });

    if (!session) {
      return res.status(404).json({ success: false, message: 'Active shared session not found' });
    }

    // Get current location (latest from history or session)
    const LocationUpdate = (await import('../models/guarding/LocationUpdate.js')).default;
    const latest = await LocationUpdate.findOne({ 
      session_id: session._id.toString() 
    }).sort({ timestamp: -1 });

    res.json({
      success: true,
      data: {
        latitude: latest ? latest.latitude : session.currentLocation.coordinates[1],
        longitude: latest ? latest.longitude : session.currentLocation.coordinates[0],
        timestamp: latest ? latest.timestamp : session.lastLocationUpdate,
        destination: session.destination,
        routePoints: session.routePoints || []
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
