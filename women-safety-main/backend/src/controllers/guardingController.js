import { v4 as uuidv4 } from 'uuid';
import GuardingProfile from '../models/guarding/GuardingProfile.js';
import GuardingSession from '../models/guarding/GuardingSession.js';
import LocationUpdate from '../models/guarding/LocationUpdate.js';
import GuardingAlert from '../models/guarding/GuardingAlert.js';
import ShareLink from '../models/guarding/ShareLink.js';

// @desc    Register or update guarding profile
// @route   POST /api/guarding/profile/register
// @access  Public
export const registerProfile = async (req, res) => {
  try {
    const { device_id, name } = req.body;

    if (!device_id) {
      return res.status(400).json({ message: 'device_id is required.' });
    }

    let profile = await GuardingProfile.findOneAndUpdate(
      { device_id },
      { name },
      { upsert: true, new: true }
    );

    res.status(201).json({ 
      message: 'Guarding profile synchronized.',
      profile 
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};


// @desc    Start a guarding session
// @route   POST /api/guarding/guard/start
// @access  Public
export const startGuarding = async (req, res) => {
  try {
    const { device_id, start_latitude, start_longitude, userId } = req.body;

    if (!device_id) {
      return res.status(400).json({ message: 'device_id is required.' });
    }

    const session_id = uuidv4();
    
    const session = await GuardingSession.create({
      session_id,
      device_id,
      userId: userId || (req.user ? req.user._id : null),
      status: 'ACTIVE'
    });

    if (start_latitude !== undefined && start_longitude !== undefined) {
      await LocationUpdate.create({
        session_id,
        userId: userId || (req.user ? req.user._id : null),
        latitude: start_latitude,
        longitude: start_longitude
      });
    }

    res.status(201).json({ 
      message: 'Guarding session started.',
      session_id
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Stop a guarding session
// @route   POST /api/guarding/guard/stop
// @access  Public
export const stopGuarding = async (req, res) => {
  try {
    const { session_id, latitude, longitude } = req.body;

    if (!session_id) {
      return res.status(400).json({ message: 'session_id is required.' });
    }

    const session = await GuardingSession.findOneAndUpdate(
      { session_id },
      { status: 'COMPLETED', end_time: new Date() },
      { returnDocument: 'after' }
    );

    if (!session) {
      return res.status(404).json({ message: 'Session not found.' });
    }

    if (latitude !== undefined && longitude !== undefined) {
      await LocationUpdate.create({
        session_id,
        userId: req.body.userId || (req.user ? req.user._id : null),
        latitude,
        longitude,
        timestamp: new Date()
      });
    }

    res.status(200).json({ message: 'Guarding session stopped.', session });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Update location for a session
// @route   POST /api/guarding/location/update
// @access  Public
export const updateLocation = async (req, res) => {
  try {
    const { session_id, latitude, longitude, timestamp, userId: bodyUserId } = req.body;
    const userId = bodyUserId || (req.user ? req.user._id : null);

    if (!session_id || latitude === undefined || longitude === undefined) {
      return res.status(400).json({ message: 'session_id, latitude, and longitude are required.' });
    }

    const locationData = { 
      session_id, 
      latitude, 
      longitude,
      userId
    };
    if (timestamp) locationData.timestamp = new Date(timestamp);

    const location = await LocationUpdate.create(locationData);
    
    // Simulate notifying trusted contacts
    console.log(`📍 LOCATION SYNC: Session ${session_id} updated to (${latitude}, ${longitude}). Trusted contacts informed.`);

    res.status(201).json({ message: 'Location updated.' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Trigger an emergency alert
// @route   POST /api/guarding/alert/emergency
// @access  Public
export const triggerEmergency = async (req, res) => {
  try {
    const { session_id, latitude, longitude, timestamp } = req.body;

    if (!session_id) {
      return res.status(400).json({ message: 'session_id is required.' });
    }

    const alertData = { session_id, alert_type: 'EMERGENCY' };
    if (latitude !== undefined) alertData.latitude = latitude;
    if (longitude !== undefined) alertData.longitude = longitude;
    if (timestamp) alertData.timestamp = new Date(timestamp);

    const alert = await GuardingAlert.create(alertData);
    res.status(201).json({ message: 'Emergency alert logged.', alert_id: alert._id });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};


// @desc    Create a share location token
// @route   POST /api/guarding/share/create
// @access  Public
export const createShareLink = async (req, res) => {
  try {
    const { session_id } = req.body;

    if (!session_id) {
      return res.status(400).json({ message: 'session_id is required.' });
    }

    const token = uuidv4().substring(0, 8); // Short token for sharing
    
    // Expires in 24 hours
    const expires_at = new Date(Date.now() + 24 * 60 * 60 * 1000); 

    await ShareLink.create({
      token,
      session_id,
      expires_at
    });

    res.status(201).json({ token, expires_at });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Get latest location via share token
// @route   GET /api/guarding/share/:token
// @access  Public
export const getSharedLocation = async (req, res) => {
  try {
    const { token } = req.params;

    const shareLink = await ShareLink.findOne({ token, expires_at: { $gt: new Date() } });
    if (!shareLink) {
      return res.status(404).json({ message: 'Invalid or expired share link.' });
    }

    const latestLocation = await LocationUpdate.findOne({ session_id: shareLink.session_id })
      .sort({ timestamp: -1 });

    const session = await GuardingSession.findOne({ session_id: shareLink.session_id });

    if (!latestLocation) {
      return res.status(404).json({ message: 'No location data available for this session.' });
    }

    // Get traveled path history (last 50 points)
    const history = await LocationUpdate.find({ session_id: shareLink.session_id })
      .sort({ timestamp: -1 })
      .limit(50)
      .select('latitude longitude timestamp -_id');

    res.status(200).json({
      latitude: latestLocation.latitude,
      longitude: latestLocation.longitude,
      timestamp: latestLocation.timestamp,
      status: session ? session.status : 'UNKNOWN',
      path: history.reverse() // Return in chronological order
    });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Log a fake call event
// @route   POST /api/guarding/event/fake-call
// @access  Public
export const triggerFakeCall = async (req, res) => {
  try {
    // Basic logging, you could store this in a generic Events collection
    res.status(200).json({ message: 'Fake call event logged.' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};

// @desc    Log a fake video event
// @route   POST /api/guarding/event/fake-video
// @access  Public
export const triggerFakeVideo = async (req, res) => {
  try {
    res.status(200).json({ message: 'Fake video event logged.' });
  } catch (error) {
    res.status(500).json({ message: error.message });
  }
};
