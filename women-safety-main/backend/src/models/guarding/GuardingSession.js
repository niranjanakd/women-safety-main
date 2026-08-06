import mongoose from 'mongoose';

const guardingSessionSchema = new mongoose.Schema({
  session_id: {
    type: String,
    required: true,
    unique: true,
  },
  device_id: {
    type: String,
    required: true,
  },
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false,
  },
  start_time: {
    type: Date,
    default: Date.now,
  },
  end_time: {
    type: Date,
  },
  status: {
    type: String,
    enum: ['ACTIVE', 'SAFE'],
    default: 'ACTIVE',
  }
});

const GuardingSession = mongoose.model('GuardingSession', guardingSessionSchema);
export default GuardingSession;
