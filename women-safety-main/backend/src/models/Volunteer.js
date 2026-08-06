import mongoose from 'mongoose';
import { v4 as uuidv4 } from 'uuid';

const volunteerSchema = new mongoose.Schema({
  userId: {
    type: String,
    unique: true,
    required: true,
    default: () => 'VOL-' + uuidv4().split('-')[0].toUpperCase(),
  },
  name: {
    type: String,
    required: true,
    trim: true,
  },
  email: {
    type: String,
    unique: true,
    sparse: true,
    trim: true,
    lowercase: true,
  },
  phone: {
    type: String,
    unique: true,
    sparse: true,
    trim: true,
  },
  passwordHash: {
    type: String,
    required: true,
  },
  address: {
    type: String,
    trim: true,
  },
  profilePhoto: {
    type: String,
  },
  currentLocation: {
    type: {
      type: String,
      enum: ['Point'],
      required: false
    },
    coordinates: {
      type: [Number], // [longitude, latitude]
      required: false
    }
  },
  isVerified: {
    type: Boolean,
    default: false,
  },
  isEmailVerified: {
    type: Boolean,
    default: false,
  },
  isPhoneVerified: {
    type: Boolean,
    default: false,
  },
}, {
  timestamps: true
});

volunteerSchema.index({ currentLocation: '2dsphere' });

// Static Methods
volunteerSchema.statics.createVolunteer = async function (data) {
  if (!data.email && !data.phone) {
    throw new Error('Must provide either email or phone for registration');
  }
  const volunteer = new this(data);
  return volunteer.save();
};

volunteerSchema.statics.findByEmail = function (email) {
  return this.findOne({ email });
};

volunteerSchema.statics.findByPhone = function (phone) {
  return this.findOne({ phone });
};

volunteerSchema.statics.findByMongoId = function (id) {
  return this.findById(id);
};

const Volunteer = mongoose.model('Volunteer', volunteerSchema);
export default Volunteer;
