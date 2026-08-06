import mongoose from 'mongoose';

const locationUpdateSchema = new mongoose.Schema({
  session_id: {
    type: String,
    required: true,
  },
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false,
  },
  latitude: {
    type: Number,
    required: true,
  },
  longitude: {
    type: Number,
    required: true,
  },
  timestamp: {
    type: Date,
    default: Date.now,
  }
});

// Create index for fast retrieval of latest locations
locationUpdateSchema.index({ session_id: 1, timestamp: -1 });

const LocationUpdate = mongoose.model('LocationUpdate', locationUpdateSchema);
export default LocationUpdate;
