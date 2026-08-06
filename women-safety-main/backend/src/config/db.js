import mongoose from 'mongoose';
import { MongoMemoryServer } from 'mongodb-memory-server';
import dns from 'dns';

// Fix for querySrv ECONNREFUSED when connecting to MongoDB Atlas
// This forces Node.js to use reliable DNS servers instead of the system default
dns.setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);

let mongoServer;

const connectDB = async () => {
  try {
    let uri = process.env.MONGO_URI;

    // Only use memory server if NO URI is provided in .env or if explicitly requested via 'memory' string
    if (!uri || uri.includes('memory')) {
      console.log('⚠️  MONGO_URI not found or set to memory. Spinning up In-Memory MongoDB Server...');
      mongoServer = await MongoMemoryServer.create();
      uri = mongoServer.getUri();
    } else {
      console.log(`🚀 Connecting to: ${uri.split('@')[1]?.split('/')[0] || 'Atlas'}`);
    }

    try {
      const conn = await mongoose.connect(uri, {
        serverSelectionTimeoutMS: 5000, // Timeout after 5 seconds instead of 30
      });
      console.log(`✅ MongoDB Connected: ${conn.connection.host}`);
    } catch (connError) {
      console.error(`❌ Atlas Connection Error: ${connError.message}`);
      if (!uri.includes('127.0.0.1')) {
        console.log('🔄 Falling back to In-Memory Server...');
        mongoServer = await MongoMemoryServer.create();
        const fallbackUri = mongoServer.getUri();
        await mongoose.connect(fallbackUri);
        console.log('✅ Connected to In-Memory MongoDB');
      } else {
        throw connError;
      }
    }
  } catch (error) {
    console.error(`❌ Critical Error: ${error.message}`);
    process.exit(1);
  }
};

export default connectDB;
