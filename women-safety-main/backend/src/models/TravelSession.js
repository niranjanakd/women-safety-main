import mongoose from 'mongoose';

const travelSessionSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    startTime: {
      type: Date,
      default: Date.now,
    },
    endTime: {
      type: Date,
    },
    destination: {
      address: String,
      coordinates: {
        lat: Number,
        lng: Number,
      },
    },
    currentLocation: {
      type: {
        type: String,
        enum: ['Point'],
        default: 'Point',
      },
      coordinates: {
        type: [Number], // [longitude, latitude]
        required: true,
      },
    },
    status: {
      type: String,
      enum: ['active', 'completed', 'missed-checkin'],
      default: 'active',
    },
    lastLocationUpdate: {
      type: Date,
      default: Date.now,
    },
    routePoints: [
      {
        lat: Number,
        lng: Number,
      }
    ],
    shareToken: {
      type: String,
      unique: true,
      sparse: true, // Only for travel sessions that are shared
    },
  },
  {
    timestamps: true,
  }
);

// GeoJSON index
travelSessionSchema.index({ currentLocation: '2dsphere' });

// Virtual for duration calculation
travelSessionSchema.virtual('duration').get(function () {
  const end = this.endTime || new Date();
  const diff = end - this.startTime;
  const minutes = Math.floor(diff / 60000);
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
});

travelSessionSchema.set('toJSON', { virtuals: true });
travelSessionSchema.set('toObject', { virtuals: true });

const TravelSession = mongoose.model('TravelSession', travelSessionSchema);

export default TravelSession;
