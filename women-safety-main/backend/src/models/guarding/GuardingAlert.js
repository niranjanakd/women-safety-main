import mongoose from 'mongoose';

const guardingAlertSchema = new mongoose.Schema({
  session_id: {
    type: String,
    required: true,
  },
  alert_type: {
    type: String,
    enum: ['EMERGENCY'],
    default: 'EMERGENCY',
  },
  latitude: {
    type: Number,
  },
  longitude: {
    type: Number,
  },
  timestamp: {
    type: Date,
    default: Date.now,
  }
});

const GuardingAlert = mongoose.model('GuardingAlert', guardingAlertSchema);
export default GuardingAlert;
