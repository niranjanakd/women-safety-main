import mongoose from 'mongoose';

const incidentSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      required: true,
      ref: 'User',
    },
    type: {
      type: String,
      required: true,
      enum: ['Harassment', 'Physical Assault', 'Theft', 'Suspicious Activity', 'SOS Alert', 'Other'],
    },
    location: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: {
        type: [Number], // [lng, lat]
        required: true,
      },
      address: String,
    },
    severity: {
      type: String,
      required: true,
      enum: ['Low', 'Medium', 'High'],
      default: 'Medium',
    },
    description: {
      type: String,
      required: true,
    },
    proofs: [
      {
        url: {
          type: String,
          required: true,
        },
        fileType: {
          type: String,
          required: true,
          enum: ['image', 'video'],
        },
        uploadedAt: {
          type: Date,
          default: Date.now,
        },
      },
    ],
    status: {
      type: String,
      required: true,
      enum: ['pending', 'under-investigation', 'in-progress', 'resolved'],
      default: 'pending',
    },
  },
  {
    timestamps: true,
  }
);

incidentSchema.index({ location: '2dsphere' });

const Incident = mongoose.model('Incident', incidentSchema);

export default Incident;
