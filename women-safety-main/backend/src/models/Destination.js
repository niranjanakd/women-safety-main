import mongoose from 'mongoose';

const destinationSchema = new mongoose.Schema({
  destinationName: {
    type: String,
    required: true,
    trim: true,
  },
  placeName: {
    type: String,
    required: true,
    trim: true,
  },
  address: {
    type: String,
    required: true,
  },
  latitude: {
    type: Number,
    required: true,
  },
  longitude: {
    type: Number,
    required: true,
  },
  user: {
    type: mongoose.Schema.Types.ObjectId,
    required: true,
    ref: 'User',
  },
}, {
  timestamps: true,
});

const Destination = mongoose.model('Destination', destinationSchema);

export default Destination;
