import mongoose from 'mongoose';

const guardingProfileSchema = new mongoose.Schema({
  device_id: {
    type: String,
    required: true,
    unique: true,
  },
  name: {
    type: String, // Optional user name given during registration
  },
  created_at: {
    type: Date,
    default: Date.now,
  }
});

const GuardingProfile = mongoose.model('GuardingProfile', guardingProfileSchema);
export default GuardingProfile;
