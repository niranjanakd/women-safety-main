import express from 'express';
import mongoose from 'mongoose';
import dotenv from 'dotenv';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import http from 'http';
import { Server } from 'socket.io';
import connectDB from './config/db.js';
import authRoutes from './routes/authRoutes.js';
import userRoutes from './routes/userRoutes.js';
import destinationRoutes from './routes/destinationRoutes.js';
import incidentRoutes from './routes/incidentRoutes.js';
import alertRoutes from './routes/alertRoutes.js';
import resourceRoutes from './routes/resourceRoutes.js';
import guardingRoutes from './routes/guardingRoutes.js';
import chatRoutes from './routes/chatRoutes.js';
import trustedRoutes from './routes/trustedRoutes.js';
import policeRoutes from './routes/policeRoutes.js';
import seedDatabase, { seedEssentialData } from './utils/seeder.js';
import User from './models/User.js';

// Load env vars
dotenv.config();

// Connect to database and initialize
connectDB().then(async () => {
  try {
    // Always call the non-destructive seeding logic
    await seedDatabase();
  } catch (err) {
    console.error('Initialization error:', err);
  }
}).catch(err => {
  console.error('DB Connection error:', err);
});

const app = express();
const server = http.createServer(app);

// Initialize Socket.io for WebRTC signaling
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

io.on('connection', (socket) => {
  console.log(`[Socket.io] Client connected: ${socket.id}`);

  // Join a specific alert room
  socket.on('join-room', (roomId) => {
    socket.join(roomId);
    console.log(`[Socket.io] Socket ${socket.id} joined room ${roomId}`);
  });

  // WebRTC Signaling: Forward offer to the room
  socket.on('offer', (data) => {
    socket.to(data.roomId).emit('offer', data.offer);
  });

  // WebRTC Signaling: Forward answer to the room
  socket.on('answer', (data) => {
    socket.to(data.roomId).emit('answer', data.answer);
  });

  // WebRTC Signaling: Forward ICE candidates
  socket.on('ice-candidate', (data) => {
    socket.to(data.roomId).emit('ice-candidate', data.candidate);
  });

  socket.on('disconnect', () => {
    console.log(`[Socket.io] Client disconnected: ${socket.id}`);
  });
});

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// --- ABSOLUTE TOP LOGGER ---
app.use((req, res, next) => {
  console.log(`[TOP] Incoming: ${req.method} ${req.originalUrl}`);
  next();
});

// Middleware
app.use(cors());
app.use(express.json());

// Request Logger (with body)
app.use((req, res, next) => {
  if (req.originalUrl.includes('/auth/')) {
      console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);
      if (req.body && Object.keys(req.body).length > 0) {
        console.log(`  Body: ${JSON.stringify(req.body)}`);
      }
  }
  next();
});

// Mount routers
app.use('/api/auth', authRoutes);
app.use('/api/user', userRoutes);
app.use('/api/destinations', destinationRoutes);
app.use('/api/incidents', incidentRoutes);
app.use('/api/alerts', alertRoutes);
app.use('/api/resources', resourceRoutes);
app.use('/api/guarding', guardingRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/trusted-dashboard', trustedRoutes);
app.use('/api/police', policeRoutes);

// Static files
app.use(express.static(path.join(__dirname, '../public')));
app.use('/uploads', express.static(path.join(__dirname, '../uploads'), {
  setHeaders: (res, filePath) => {
    if (filePath.endsWith('.m3u8')) {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');
    }
  }
}));

// Root route
app.get('/', (req, res) => {
  res.send('Women Safety API is running...');
});

app.get('/api/health', async (req, res) => {
  try {
    const isAtlas = mongoose.connection.host.includes('mongodb.net');
    const userCount = await User.countDocuments();
    const resourceCount = await mongoose.model('Resource').countDocuments();
    const incidentCount = await mongoose.model('Incident').countDocuments();
    const dbName = mongoose.connection.name;

    res.status(200).json({
      status: 'running',
      message: 'Women Safety API is running...',
      database: isAtlas ? 'Atlas (Production)' : 'In-Memory (Empty/Testing)',
      db_name: dbName,
      users_in_db: userCount,
      resources_in_db: resourceCount,
      incidents_in_db: incidentCount,
      host: mongoose.connection.host,
      timestamp: new Date()
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message });
  }
});

// 404 Handler - MUST be after all routes
app.use((req, res, next) => {
  res.status(404).json({
    message: `Not Found - ${req.method} ${req.originalUrl}`
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  const statusCode = res.statusCode === 200 ? 500 : res.statusCode;
  res.status(statusCode).json({
    success: false,
    message: err.message,
    stack: process.env.NODE_ENV === 'production' ? null : err.stack,
  });
});

const PORT = process.env.PORT || 5000;

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running in ${process.env.NODE_ENV || 'development'} mode on http://0.0.0.0:${PORT}`);
});

// Catch unhandled rejections
process.on('unhandledRejection', (err) => {
  console.error('Unhandled Rejection:', err);
});

// Catch uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});
