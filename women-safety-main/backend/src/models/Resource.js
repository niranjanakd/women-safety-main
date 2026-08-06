import mongoose from 'mongoose';

const resourceSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
    },
    subtitle: {
      type: String,
      trim: true,
    },
    description: {
      type: String,
      trim: true,
    },
    type: {
      type: String,
      required: true,
      enum: ['haven', 'guide', 'helpline'],
    },
    category: {
      type: String,
      trim: true,
    },
    icon: {
      type: String, // String representation of the icon name (e.g., 'verified_user')
    },
    color: {
      type: String, // Hex code (e.g., '#EFF6FF')
    },
    iconColor: {
      type: String, // Hex code (e.g., '#2563EB')
    },
    status: {
      type: String, // e.g., '24/7 Open'
    },
    phone: {
      type: String,
    },
    duration: {
      type: String, // e.g., '5 mins' (for guides)
    },
    location: {
      type: {
        type: String,
        enum: ['Point'],
      },
      coordinates: {
        type: [Number], // [longitude, latitude]
        required: false,
      },
      address: String,
    },
    distance: {
      type: String, // For mock purposes if needed
    },
    url: {
      type: String, // YouTube link
    },
  },
  {
    timestamps: true,
  }
);

resourceSchema.index({ location: '2dsphere' });

const Resource = mongoose.model('Resource', resourceSchema);

export default Resource;
