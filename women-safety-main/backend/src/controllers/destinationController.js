import Destination from '../models/Destination.js';

// @desc    Get all destinations for user
// @route   GET /api/destinations
// @access  Private
export const getDestinations = async (req, res) => {
  try {
    const destinations = await Destination.find({ user: req.user._id });
    res.json({
      success: true,
      data: destinations
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Add a destination
// @route   POST /api/destinations
// @access  Private
export const addDestination = async (req, res) => {
  try {
    const { name, destinationName, placeName, address, latitude, longitude, coordinates } = req.body;
    
    // Support both frontend field names (name) and model field names (destinationName)
    const finalName = name || destinationName;
    const finalPlace = placeName || address;
    const finalAddress = address || placeName;
    
    // Extract coordinates safely
    let finalLat, finalLng;
    if (coordinates && typeof coordinates === 'object') {
      finalLat = coordinates.lat;
      finalLng = coordinates.lng;
    } else {
      finalLat = latitude;
      finalLng = longitude;
    }
    
    if (!finalName || !finalAddress || finalLat === undefined || finalLng === undefined) {
      return res.status(400).json({ 
        success: false,
        message: 'Please provide all required fields (name, address, coordinates)'
      });
    }

    const destination = new Destination({
      destinationName: finalName,
      placeName: finalPlace,
      address: finalAddress,
      latitude: Number(finalLat),
      longitude: Number(finalLng),
      user: req.user._id,
    });

    const createdDestination = await destination.save();
    res.status(201).json({
      success: true,
      data: createdDestination
    });

  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};

// @desc    Delete a destination
// @route   DELETE /api/destinations/:id
// @access  Private
export const deleteDestination = async (req, res) => {
  try {
    const destination = await Destination.findById(req.params.id);

    if (destination) {
      if (destination.user.toString() !== req.user._id.toString()) {
        return res.status(401).json({ success: false, message: 'Not authorized' });
      }

      await destination.deleteOne();
      res.json({ success: true, message: 'Destination removed' });
    } else {
      res.status(404).json({ success: false, message: 'Destination not found' });
    }
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
};
