import mongoose from 'mongoose';

const trustedContactSchema = new mongoose.Schema({
  name: { type: String, required: true },
  phone: { type: String, required: true },
  relation: { type: String, required: true },
}, { _id: true }); // keep _id for easy deletion

const userSchema = new mongoose.Schema({
  userId: {
    type: String,
    unique: true,
    required: true,
    default: () => new mongoose.Types.ObjectId().toString(),
  },
  name: {
    type: String,
    required: true,
    trim: true,
  },
  username: {
    type: String,
    required: true,
    unique: true,
    trim: true,
  },
  email: {
    type: String,
    unique: true,
    sparse: true,
    trim: true,
    lowercase: true,
  },
  age: {
    type: Number,
  },
  gender: {
    type: String,
    enum: ['male', 'female', 'other'],
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
  role: {
    type: String,
    enum: ['user', 'volunteer', 'authority'],
    default: 'user',
  },
  trustedContacts: [trustedContactSchema],
  address: {
    type: String,
    trim: true,
  },
  profilePhoto: {
    type: String, // URL or file path
  },
  guardianModeEnabled: {
    type: Boolean,
    default: false,
  },
  currentLocation: {
    type: {
      type: String,
      enum: ['Point'],    // 'location.type' must be 'Point'
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

  isPhoneVerified: {
    type: Boolean,
    default: false,
  },
  otpCode: {
    type: String,
    select: false,
  },
  otpExpires: {
    type: Date,
    select: false,
  },

  sosTriggerWord: {

    type: String,
    default: 'red',
    trim: true,
    lowercase: true,
  },
  isOnline: {
    type: Boolean,
    default: false,
  },
  permanentAddress: {
    type: String,
    trim: true,
  },
  currentAddressString: {
    type: String,
    trim: true,
  },
  aadhaarNumber: {
    type: String,
    trim: true,
    unique: true,
    sparse: true,
  },
  isApproved: {
    type: Boolean,
    default: false,
  },
  pendingUpdate: {
    name: String,
    phone: String,
    address: String,
    permanentAddress: String,
    profilePhoto: String,
    submittedAt: Date
  },
}, {
  timestamps: true // Automatically manages createdAt and updatedAt
});

// Create 2dsphere index for location queries
userSchema.index({ currentLocation: '2dsphere' });

// --- D1 Static Methods ---

userSchema.statics.createUser = async function (userData) {
  if (!userData.phone) {
    throw new Error('Must provide phone for registration');
  }
  const user = new this(userData);
  return user.save();
};


userSchema.statics.findUserByPhone = function (phone) {
  return this.findOne({ phone });
};

userSchema.statics.findUserById = function (userId) {
  return this.findOne({ userId });
};

userSchema.statics.findUserByMongoId = function (id) {
  return this.findById(id);
};

userSchema.statics.updateUser = function (userId, updateData) {
  return this.findOneAndUpdate({ userId }, updateData, { returnDocument: 'after' });
};

userSchema.statics.deleteUser = function (userId) {
  return this.findOneAndDelete({ userId });
};

userSchema.statics.addTrustedContact = async function (userId, contactData) {
  return this.findOneAndUpdate(
    { userId },
    { $push: { trustedContacts: contactData } },
    { returnDocument: 'after', runValidators: true }
  );
};

userSchema.statics.removeTrustedContact = async function (userId, contactId) {
  return this.findOneAndUpdate(
    { userId },
    { $pull: { trustedContacts: { _id: contactId } } },
    { returnDocument: 'after' }
  );
};

userSchema.statics.updateTrustedContact = async function (userId, contactId, contactData) {
  const updateFields = {};
  if (contactData.name) updateFields['trustedContacts.$.name'] = contactData.name;
  if (contactData.phone) updateFields['trustedContacts.$.phone'] = contactData.phone;
  if (contactData.relation) updateFields['trustedContacts.$.relation'] = contactData.relation;

  return this.findOneAndUpdate(
    { userId, 'trustedContacts._id': contactId },
    { $set: updateFields },
    { returnDocument: 'after', runValidators: true }
  );
};

const User = mongoose.model('User', userSchema);
export default User;
