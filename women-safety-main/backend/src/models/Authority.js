import mongoose from 'mongoose';
import { v4 as uuidv4 } from 'uuid';

const authoritySchema = new mongoose.Schema({
  userId: {
    type: String,
    unique: true,
    required: true,
    default: () => 'AUTH-' + uuidv4().split('-')[0].toUpperCase(),
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
  department: {
    type: String,
    trim: true,
  },
  badgeNumber: {
    type: String,
    trim: true,
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

authoritySchema.index({ currentLocation: '2dsphere' });

// Static Methods
authoritySchema.statics.createAuthority = async function (data) {
  if (!data.email && !data.phone) {
    throw new Error('Must provide either email or phone for registration');
  }
  const authority = new this(data);
  return authority.save();
};

authoritySchema.statics.findByEmail = function (email) {
  return this.findOne({ email });
};

authoritySchema.statics.findByPhone = function (phone) {
  return this.findOne({ phone });
};

authoritySchema.statics.findByMongoId = function (id) {
  return this.findById(id);
};

const Authority = mongoose.model('Authority', authoritySchema);
export default Authority;
