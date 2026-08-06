import mongoose from 'mongoose';

const shareLinkSchema = new mongoose.Schema({
  token: {
    type: String,
    required: true,
    unique: true,
  },
  session_id: {
    type: String,
    required: true,
  },
  expires_at: {
    type: Date,
    required: true,
  }
});

// Auto-delete expired tokens
shareLinkSchema.index({ expires_at: 1 }, { expireAfterSeconds: 0 });

const ShareLink = mongoose.model('ShareLink', shareLinkSchema);
export default ShareLink;
