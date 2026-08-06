import Alert from '../models/Alert.js';
import User from '../models/User.js';
import Incident from '../models/Incident.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configure FFmpeg to use the static binary
ffmpeg.setFfmpegPath(ffmpegStatic);

// @desc    Trigger a new SOS alert
// @route   POST /api/alerts/trigger
// @access  Private
const triggerSOS = async (req, res) => {
  try {
    const { address, lat, lng } = req.body;

    // Get the user's trusted contacts
    const user = await User.findById(req.user._id).select('trustedContacts name');
    
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    // [IDEMPOTENCY] Check if user already has an active or in-progress SOS alert
    const existingAlert = await Alert.findOne({ 
      user: req.user._id, 
      status: { $in: ['active', 'in-progress'] } 
    });

    if (existingAlert) {
      // Update location for existing alert
      existingAlert.location = {
        address: address || existingAlert.location.address,
        coordinates: {
          lat: parseFloat(lat) || existingAlert.location.coordinates.lat,
          lng: parseFloat(lng) || existingAlert.location.coordinates.lng,
        },
        point: {
          type: 'Point',
          coordinates: [
            parseFloat(lng) || existingAlert.location.point.coordinates[0],
            parseFloat(lat) || existingAlert.location.point.coordinates[1]
          ]
        }
      };
      await existingAlert.save();
      
      console.log(`♻️  RE-TRIGGERED SOS: Updating existing alert ${existingAlert._id} for ${user.name}.`);
      
      return res.status(200).json({
        success: true,
        data: existingAlert,
        message: 'Existing SOS alert updated with new location'
      });
    }

    const notifiedContacts = user.trustedContacts.map(contact => ({
      name: contact.name,
      phone: contact.phone,
      notifiedAt: new Date()
    }));

    // Find volunteers within 2km radius
    const volunteers = await User.find({
      role: 'volunteer',
      currentLocation: {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)], // [longitude, latitude]
          },
          $maxDistance: 3000, // 3000 meters = 3km
        },
      },
    }).select('name currentLocation isOnline');

    // Filter for online volunteers
    const onlineVolunteers = volunteers.filter(v => v.isOnline);

    const notifiedVolunteers = onlineVolunteers.map(v => ({
      user: v._id,
      name: v.name,
      distance: 0, // In a real app, calculate actual distance or use aggregation
      notifiedAt: new Date(),
    }));

    // Find authorities
    const authorities = await User.find({ role: 'authority' }).select('name department');
    const notifiedAuthorities = authorities.map(a => ({
      user: a._id,
      name: a.name,
      department: a.department || 'Police',
      notifiedAt: new Date(),
    }));

    const alert = await Alert.create({
      user: req.user._id,
      status: 'active',
      type: 'SOS Alert',
      location: {
        address,
        coordinates: {
          lat: parseFloat(lat),
          lng: parseFloat(lng),
        },
        point: {
          type: 'Point',
          coordinates: [parseFloat(lng), parseFloat(lat)]
        }
      },
      notifiedContacts,
      notifiedVolunteers,
      notifiedAuthorities,
    });

    // Automatically create a corresponding Incident
    // Note: Incident model uses GeoJSON [lng, lat] array
    const incident = await Incident.create({
      userId: req.user._id,
      type: 'SOS Alert',
      description: `Emergency SOS Alert triggered at ${address}. Multi-tier notifications sent.`,
      severity: 'High',
      location: {
        type: 'Point',
        coordinates: [parseFloat(lng), parseFloat(lat)],
        address,
      },
      status: 'pending',
    });

    // Link Incident to Alert
    alert.incident = incident._id;
    await alert.save();

    console.log(`📡 SOS TRIGGERED and Incident created for ${req.user.name}.`);

    res.status(201).json({
      success: true,
      data: alert,
    });
  } catch (error) {
    res.status(400).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Resolve an active SOS alert
// @route   POST /api/alerts/resolve/:id
// @access  Private
const resolveSOS = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id);

    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    // Ensure only the user who triggered it (or maybe authority) can resolve it
    if (alert.user.toString() !== req.user._id.toString()) {
      return res.status(401).json({ success: false, message: 'Not authorized' });
    }

    alert.status = 'resolved';
    alert.resolvedAt = new Date();
    await alert.save();

    // Finalize HLS Stream if it exists so video players stop loading
    const m3u8Path = path.join(__dirname, '../../uploads/hls', alert._id.toString(), 'stream.m3u8');
    if (fs.existsSync(m3u8Path)) {
      const content = fs.readFileSync(m3u8Path, 'utf8');
      if (!content.includes('#EXT-X-ENDLIST')) {
        fs.appendFileSync(m3u8Path, '#EXT-X-ENDLIST\n');
      }
    }

    console.log(`✅ SOS RESOLVED for ${req.user.name}.`);

    res.json({
      success: true,
      data: alert,
    });
  } catch (error) {
    res.status(400).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Get current active alert for user
// @route   GET /api/alerts/active
// @access  Private
const getActiveAlert = async (req, res) => {
  try {
    const alert = await Alert.findOne({ 
      user: req.user._id, 
      status: 'active' 
    }).sort('-createdAt');

    res.json({
      success: true,
      data: alert,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Alert trusted contacts during safety check failure
// @route   POST /api/alerts/safety-check/trusted
// @access  Private
const alertTrustedContacts = async (req, res) => {
  try {
    const { lat, lng, address } = req.body;
    const user = await User.findById(req.user._id).select('name phone trustedContacts');
    
    if (!user || user.trustedContacts.length === 0) {
      return res.status(400).json({ success: false, message: 'No trusted contacts to notify' });
    }

    // Logic for SMS/Notification would go here
    console.log(`⚠️ SAFETY CHECK FAILED (Stage 1) for ${user.name}. Notifying trusted contacts.`);

    res.json({ success: true, message: 'Trusted contacts notified' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Alert volunteers during persistent safety check failure
// @route   POST /api/alerts/safety-check/volunteers
// @access  Private
const alertVolunteers = async (req, res) => {
  try {
    const { lat, lng, address } = req.body;
    const user = await User.findById(req.user._id).select('name phone');

    // Logic to find and notify nearby volunteers would go here
    console.log(`🚨 SAFETY CHECK FAILED (Stage 2 - CRITICAL) for ${user.name}. Notifying volunteers.`);

    res.json({ success: true, message: 'Nearby volunteers notified' });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Upload evidence (audio/video) for an SOS alert
// @route   POST /api/alerts/evidence/:id
// @access  Private
const uploadEvidence = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id);
    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No file provided' });
    }

    const fileType = req.file.mimetype.startsWith('video') ? 'video' : 'audio';

    if (fileType === 'video') {
      const alertId = alert._id.toString();
      const hlsDir = path.join(__dirname, '../../uploads/hls', alertId);
      
      if (!fs.existsSync(hlsDir)) {
        fs.mkdirSync(hlsDir, { recursive: true });
      }

      const m3u8Path = path.join(hlsDir, 'stream.m3u8');
      
      if (!fs.existsSync(m3u8Path)) {
        fs.writeFileSync(m3u8Path, '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:5\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-PLAYLIST-TYPE:EVENT\n');
      }

      const chunkIndex = alert.evidence.filter(e => e.fileType === 'video').length;
      const tsFileName = `segment_${chunkIndex}.ts`;
      const tsFilePath = path.join(hlsDir, tsFileName);
      const hlsUrl = `/uploads/hls/${alertId}/stream.m3u8`;

      // Trigger FFmpeg transcode async with STRICT memory limits for Render Free Tier (512MB)
      ffmpeg(req.file.path)
        .outputOptions([
          '-c:v libx264',
          '-preset ultrafast', // Use least CPU/RAM
          '-tune zerolatency', // Optimizes for real-time streaming
          '-x264-params keyint=30:scenecut=0', // Forces keyframes for seamless HLS
          '-threads 1',        // Force single thread to prevent memory spikes
          '-vf scale=-2:360',  // Downscale to 360p to maximize processing speed
          '-b:v 400k',         // Lower video bitrate
          '-c:a aac',
          '-b:a 64k',          // Lower audio bitrate
          '-f mpegts'
        ])
        .on('end', () => {
          // Add the DISCONTINUITY tag before appending the segment
          fs.appendFileSync(m3u8Path, `#EXT-X-DISCONTINUITY\n#EXTINF:5.0,\n${tsFileName}\n`);
          console.log(`[HLS] Segment ${chunkIndex} appended to ${alertId}`);
        })
        .on('error', (err) => {
          console.error(`[HLS] Transcode Error: ${err.message}`);
        })
        .save(tsFilePath);

      const normalizedPath = req.file.path.replace(/\\/g, '/');
      
      // Save the HLS URL to evidence if it's the first one
      if (chunkIndex === 0) {
        alert.evidence.push({
          fileUrl: hlsUrl,
          fileType: 'hls_stream',
          uploadedAt: new Date()
        });
      }

      // Always push the raw video chunk so chunkIndex increments for the next upload
      alert.evidence.push({
        fileUrl: `/${normalizedPath}`,
        fileType: 'video',
        uploadedAt: new Date()
      });
      
      await alert.save();
    } else {
      // Standard audio logic
      const normalizedPath = req.file.path.replace(/\\/g, '/');
      alert.evidence.push({
        fileUrl: `/${normalizedPath}`,
        fileType,
        uploadedAt: new Date()
      });
      await alert.save();
    }

    // If alert is linked to an incident, also update incident proofs
    if (alert.incident) {
      const normalizedPath = req.file.path.replace(/\\/g, '/');
      await Incident.findByIdAndUpdate(alert.incident, {
        $push: {
          proofs: {
            url: `/${normalizedPath}`,
            fileType: fileType === 'video' ? 'video' : 'image', // Incident model only supports image/video enum
          }
        }
      });
    }

    res.status(200).json({
      success: true,
      message: 'Evidence chunk queued for HLS conversion'
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Join an active SOS alert as a responder
// @route   POST /api/alerts/join/:id
// @access  Private
const joinAlert = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id);

    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    if (alert.status !== 'active') {
      return res.status(400).json({ success: false, message: 'Alert is no longer active' });
    }

    const { role, name, _id: userId } = req.user;

    if (role === 'volunteer') {
      // Check if already in notifiedVolunteers
      const volunteerIndex = alert.notifiedVolunteers.findIndex(v => v.user.toString() === userId.toString());
      if (volunteerIndex === -1) {
        alert.notifiedVolunteers.push({
          user: userId,
          name: name,
          notifiedAt: new Date(),
          joinedAt: new Date(),
          distance: 0 
        });
      } else if (!alert.notifiedVolunteers[volunteerIndex].joinedAt) {
        // If they were notified but hadn't joined yet
        alert.notifiedVolunteers[volunteerIndex].joinedAt = new Date();
      }
    } else if (role === 'authority') {
      const alreadyJoined = alert.notifiedAuthorities.some(a => a.user.toString() === userId.toString());
      if (!alreadyJoined) {
        alert.notifiedAuthorities.push({
          user: userId,
          name: name,
          department: req.user.department || 'Police',
          notifiedAt: new Date()
        });
      }
    } else {
      return res.status(403).json({ success: false, message: 'Only rescuers can join alerts' });
    }

    await alert.save();
    const populatedAlert = await Alert.findById(alert._id).populate('user', 'name phone');

    res.json({
      success: true,
      message: 'Successfully joined the rescue team',
      data: populatedAlert
    });
  } catch (error) {
    res.status(400).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Get nearby active SOS alerts for volunteers
// @route   GET /api/alerts/nearby
// @access  Private (Volunteers only typically)
const getNearbyAlerts = async (req, res) => {
  try {
    const { lat, lng, radius = 3000 } = req.query;
    if (!lat || !lng) {
      return res.status(400).json({ success: false, message: 'Please provide lat and lng' });
    }
    
    // Using MongoDB geospatial $near query for reliable results
    const radiusInMeters = parseFloat(radius);
    
    // Find active or in-progress alerts within radius
    const nearbyAlertsRaw = await Alert.find({
      status: { $in: ['active', 'in-progress'] },
      'location.point': {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)]
          },
          $maxDistance: radiusInMeters
        }
      }
    }).populate('user', 'name phone').lean(); // Use lean for easy distance injection
    
    // The $near query doesn't automatically return the distance. 
    // We calculate it for the frontend or use aggregation, but here manual check is fine for the filtered subset.
    const toRad = p => (p * Math.PI) / 180;
    const calculateDistance = (lat1, lon1, lat2, lon2) => {
      const R = 6371e3;
      const dLat = toRad(lat2 - lat1);
      const dLon = toRad(lon2 - lon1);
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * 
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      return R * c;
    };

    const nearbyAlerts = nearbyAlertsRaw.map(alert => {
      const distance = calculateDistance(
        parseFloat(lat), 
        parseFloat(lng), 
        alert.location.coordinates.lat, 
        alert.location.coordinates.lng
      );
      
      return {
        ...alert,
        distance,
        isJoined: alert.notifiedVolunteers.some(v => v.user.toString() === req.user._id.toString())
      };
    });

    res.json({
      success: true,
      data: nearbyAlerts
    });

  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message
    });
  }
};

// @desc    Update SOS alert status (in-progress/resolved/etc)
// @route   PUT /api/alerts/status/:id
// @access  Private
const updateAlertStatus = async (req, res) => {
  try {
    const { status } = req.body;
    const alert = await Alert.findById(req.params.id);

    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    // Role-based auth: In a real app, only specific rescuers or the victim should update
    const allowedRoles = ['volunteer', 'authority'];
    if (alert.user.toString() !== req.user._id.toString() && !allowedRoles.includes(req.user.role)) {
      return res.status(401).json({ success: false, message: 'Not authorized to update status' });
    }

    alert.status = status;
    if (status === 'resolved') {
      alert.resolvedAt = new Date();
      // Finalize HLS Stream if it exists so video players stop loading
      const m3u8Path = path.join(__dirname, '../../uploads/hls', alert._id.toString(), 'stream.m3u8');
      if (fs.existsSync(m3u8Path)) {
        const content = fs.readFileSync(m3u8Path, 'utf8');
        if (!content.includes('#EXT-X-ENDLIST')) {
          fs.appendFileSync(m3u8Path, '#EXT-X-ENDLIST\n');
        }
      }
    }
    await alert.save();

    // Sync with Incident status if applicable
    if (alert.incident) {
      const incidentStatusMap = {
        'active': 'pending',
        'in-progress': 'in-progress',
        'resolved': 'resolved'
      };
      await Incident.findByIdAndUpdate(alert.incident, { 
        status: incidentStatusMap[status] || 'pending' 
      });
    }

    console.log(`🏷️  SOS STATUS UPDATED to ${status} by ${req.user.name}.`);

    res.json({
      success: true,
      data: alert,
    });
  } catch (error) {
    res.status(400).json({
      success: false,
      message: error.message,
    });
  }
};

const getAlertDetails = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id)
      .populate('user', 'name phone profileHash currentAddress permanentAddress currentLocation')
      .populate('notifiedVolunteers.user', 'name phone');
    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }
    res.json({ success: true, data: alert });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get victim's live location
// @route   GET /api/alerts/:id/victim-location
// @access  Private
const getAlertVictimLocation = async (req, res) => {
  try {
    const alert = await Alert.findById(req.params.id).populate('user', 'currentLocation');
    if (!alert || !alert.user) {
      return res.status(404).json({ success: false, message: 'Alert or user not found' });
    }

    res.json({
      success: true,
      data: {
        coordinates: alert.user.currentLocation?.coordinates || alert.location.coordinates,
        updatedAt: new Date()
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Get volunteer performance statistics
// @route   GET /api/alerts/volunteer/stats
// @access  Private (Volunteer only)
const getVolunteerStats = async (req, res) => {
  try {
    const userId = req.user._id;

    // 1. People Helped (Resolved alerts where this volunteer was part of the notified list and joined)
    const resolvedAlerts = await Alert.find({
      status: 'resolved',
      'notifiedVolunteers.user': userId,
      'notifiedVolunteers.joinedAt': { $exists: true }
    });

    const peopleHelped = resolvedAlerts.length;

    // 2. Active Alerts (Alerts where this volunteer is currently joined)
    const activeAlertsCount = await Alert.countDocuments({
      status: 'active',
      'notifiedVolunteers.user': userId,
      'notifiedVolunteers.joinedAt': { $exists: true }
    });

    // 3. Avg Response Time (Difference between notifiedAt and joinedAt)
    let totalResponseTime = 0;
    let counts = 0;

    const allMyAlerts = await Alert.find({
      'notifiedVolunteers.user': userId,
      'notifiedVolunteers.joinedAt': { $exists: true }
    });

    allMyAlerts.forEach(alert => {
      const vEntry = alert.notifiedVolunteers.find(v => v.user.toString() === userId.toString());
      if (vEntry && vEntry.joinedAt && vEntry.notifiedAt) {
        const diff = vEntry.joinedAt - vEntry.notifiedAt; // ms
        totalResponseTime += diff;
        counts++;
      }
    });

    const avgResponseMs = counts > 0 ? totalResponseTime / counts : 0;
    const avgResponseMin = Math.round(avgResponseMs / 60000); // convert to minutes

    res.json({
      success: true,
      data: {
        peopleHelped,
        activeAlerts: activeAlertsCount,
        avgResponse: `${avgResponseMin} min`
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

export {
  triggerSOS,
  resolveSOS,
  getActiveAlert,
  alertTrustedContacts,
  alertVolunteers,
  uploadEvidence,
  joinAlert,
  getNearbyAlerts,
  updateAlertStatus,
  getAlertDetails,
  getAlertVictimLocation,
  getVolunteerStats
};
