import mongoose from 'mongoose';

const trustedContactSchema = new mongoose.Schema(
  {
    ownerUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    trustedUserId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    relationship: {
      type: String,
      required: true,
      trim: true,
    },
  },
  {
    timestamps: true,
  }
);

// Prevent duplicate trust links
trustedContactSchema.index({ ownerUserId: 1, trustedUserId: 1 }, { unique: true });

const TrustedContact = mongoose.model('TrustedContact', trustedContactSchema);

export default TrustedContact;
