import mongoose from 'mongoose';
import dotenv from 'dotenv';
import connectDB from './src/config/db.js';
import User from './src/models/User.js';

dotenv.config();

const check = async () => {
    try {
        await connectDB();
        const users = await User.find().sort({ createdAt: -1 }).limit(10);
        const count = await User.countDocuments();
        console.log(`TOTAL USERS: ${count}`);
        console.log('--- RECENT 10 ---');
        users.forEach(u => {
            console.log(`[${u.role}] ${u.phone} (${u.name}) - Verified: ${u.isVerified}`);
        });
        process.exit(0);
    } catch (err) {
        console.error('Error:', err);
        process.exit(1);
    }
};

check();
