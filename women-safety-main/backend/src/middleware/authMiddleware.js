import jwt from 'jsonwebtoken';
import User from '../models/User.js';
import Authority from '../models/Authority.js';
import Volunteer from '../models/Volunteer.js';

export const protect = async (req, res, next) => {
  let token;

  // Check if token exists in Authorization header
  if (
    req.headers.authorization &&
    req.headers.authorization.startsWith('Bearer')
  ) {
    try {
      // Get token from header
      token = req.headers.authorization.split(' ')[1];

      // Decode token
      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      // Get user from token and attach to request
      req.user = await User.findUserByMongoId(decoded.id).select('-passwordHash');

      // If not found in User, try Volunteer
      if (!req.user) {
        let volUser = await Volunteer.findByMongoId(decoded.id).select('-passwordHash');
        if (volUser) {
          req.user = Object.assign(volUser.toObject(), { role: 'volunteer', _id: volUser._id });
        }
      }

      // If not found in Volunteer either, try Authority (Police)
      if (!req.user) {
        let authUser = await Authority.findByMongoId(decoded.id).select('-passwordHash');
        if (authUser) {
          // Add role property so subsequent controllers know treating it like a user
          req.user = Object.assign(authUser.toObject(), { role: 'authority', _id: authUser._id });
        }
      }

      if (!req.user) {
        return res.status(401).json({ message: 'User not found for this token' });
      }

      next();
    } catch (error) {
      console.error(error);
      return res.status(401).json({ message: 'Not authorized, token failed' });
    }
  }

  if (!token) {
    return res.status(401).json({ message: 'Not authorized, no token provided' });
  }
};
