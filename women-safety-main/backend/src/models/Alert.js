import mongoose from 'mongoose';

const alertSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      ref: 'User',
    },
    status: {
      type: String,
      required: true,
      enum: ['active', 'in-progress', 'resolved', 'done'],
      default: 'active',
    },
    type: {
      type: String,
      default: 'SOS Alert',
    },
    location: {
      address: String,
      coordinates: {
        lat: Number,
        lng: Number,
      },
      point: {
        type: { type: String, enum: ['Point'], default: 'Point' },
        coordinates: { type: [Number] } // [longitude, latitude]
      }
    },
    notifiedContacts: [
      {
        name: String,
        phone: String,
        notifiedAt: {
          type: Date,
          default: Date.now,
        },
      },
    ],
    notifiedVolunteers: [
      {
        user: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        name: String,
        distance: Number,
        notifiedAt: { type: Date, default: Date.now },
        joinedAt: Date,
      }
    ],
    notifiedAuthorities: [
      {
        user: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        name: String,
        department: String,
        notifiedAt: { type: Date, default: Date.now },
      }
    ],
    evidence: [
      {
        fileUrl: String,
        fileType: { type: String, enum: ['audio', 'video', 'hls_stream'] },
        uploadedAt: { type: Date, default: Date.now },
      }
    ],
    incident: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Incident',
    },
    resolvedAt: {
      type: Date,
    },
  },
  {
    timestamps: true,
  }
);

// Add 2dsphere index for nearby queries
alertSchema.index({ 'location.point': '2dsphere' });

const Alert = mongoose.model('Alert', alertSchema);

export default Alert;
