import Incident from '../models/Incident.js';

// @desc    Create new incident report with proofs
// @route   POST /api/incidents
// @access  Private
const createIncident = async (req, res) => {
  try {
    const { type, description, severity, address, lat, lng } = req.body;
    
    console.log('--- Create Incident Request ---');
    console.log('Body:', JSON.stringify(req.body, null, 2));
    console.log('Files Count:', req.files ? req.files.length : 0);

    const proofs = [];
    if (req.files && req.files.length > 0) {
      req.files.forEach((file) => {
        const fileType = file.mimetype.startsWith('video') ? 'video' : 'image';
        const normalizedPath = file.path.replace(/\\/g, '/');
        proofs.push({
          url: `/${normalizedPath}`,
          fileType: fileType,
        });
      });
    }

    const incident = await Incident.create({
      userId: req.user._id,
      type,
      description,
      severity,
      location: {
        type: 'Point',
        coordinates: [parseFloat(lng), parseFloat(lat)],
        address,
      },
      proofs,
    });

    console.log('Incident Created Successfully:', incident._id);
    res.status(201).json({
      success: true,
      data: incident,
    });
  } catch (error) {
    console.error('Create Incident Error:', error);
    res.status(400).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Get all incidents (Admin/Authority/Volunteer view)
// @route   GET /api/incidents
// @access  Private/Role-aware
const getIncidents = async (req, res) => {
  try {
    const { lat, lng, radius = 5000, hours } = req.query; // Default 5km radius
    let query = {};

    if (hours) {
      const timeAgo = new Date(Date.now() - parseInt(hours) * 60 * 60 * 1000);
      query.createdAt = { $gte: timeAgo };
    }

    if (lat && lng) {
      query['location.coordinates'] = {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)],
          },
          $maxDistance: parseInt(radius),
        },
      };
    }

    const incidents = await Incident.find(query).populate('user', 'name email phone').sort('-createdAt');
    res.json({
      success: true,
      data: incidents,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Get user's own incidents
// @route   GET /api/incidents/my
// @access  Private
const getMyIncidents = async (req, res) => {
  try {
    const incidents = await Incident.find({ user: req.user._id }).sort('-createdAt');
    res.json({
      success: true,
      data: incidents,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Get incidents for map visualization (All users)
// @route   GET /api/incidents/map
// @access  Private
const getMapIncidents = async (req, res) => {
  try {
    const { lat, lng, radius = 5000, hours } = req.query;
    let query = {};

    if (hours) {
      const timeAgo = new Date(Date.now() - parseInt(hours) * 60 * 60 * 1000);
      query.createdAt = { $gte: timeAgo };
    }

    if (lat && lng) {
      query['location.coordinates'] = {
        $near: {
          $geometry: {
            type: 'Point',
            coordinates: [parseFloat(lng), parseFloat(lat)],
          },
          $maxDistance: parseInt(radius),
        },
      };
    }

    const incidents = await Incident.find(query, 'type location severity status createdAt').sort('-createdAt');
    res.json({
      success: true,
      data: incidents,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

export {
  createIncident,
  getIncidents,
  getMyIncidents,
  getMapIncidents
};
