import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import dns from 'dns';

// Ensure stable DNS for SRV resolution
dns.setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);

import User from './src/models/User.js';
import Volunteer from './src/models/Volunteer.js';
import Authority from './src/models/Authority.js';
import Incident from './src/models/Incident.js';
import Alert from './src/models/Alert.js';
import Resource from './src/models/Resource.js';
import TravelSession from './src/models/TravelSession.js';
import TrustedContact from './src/models/TrustedContact.js';
import Message from './src/models/Message.js';
import Destination from './src/models/Destination.js';
import GuardingSession from './src/models/guarding/GuardingSession.js';
import LocationUpdate from './src/models/guarding/LocationUpdate.js';
import CheckInRequest from './src/models/CheckInRequest.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '.env') });

const MONGODB_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/womensafety';

async function seedDatabase() {
  let retries = 5;
  while (retries > 0) {
    try {
      console.log(`📡 Connecting to MongoDB (Tries left: ${retries})...`);
      await mongoose.connect(MONGODB_URI, { 
        serverSelectionTimeoutMS: 10000,
        family: 4 
      });
      console.log('✅ Connected.');

      // --- CLEARING ALL OLD DATA ---
      console.log('🗑️ Clearing all collections...');
      await User.deleteMany({});
      await Volunteer.deleteMany({});
      await Authority.deleteMany({});
      await Incident.deleteMany({});
      await Alert.deleteMany({});
      await Resource.deleteMany({});
      await TravelSession.deleteMany({});
      await TrustedContact.deleteMany({});
      await Message.deleteMany({});
      await Destination.deleteMany({});
      try { await GuardingSession.deleteMany({}); } catch(e){}
      try { await LocationUpdate.deleteMany({}); } catch(e){}
      try { await CheckInRequest.deleteMany({}); } catch(e){}

      console.log('👤 Seeding Specific Demo Credentials...');

      const salt = await bcrypt.genSalt(10);
      const hash = await bcrypt.hash('password123', salt);

      // 1. Female User 1 (Ananya) — The PRIMARY "Trusted Contact" for others
      const ananya = new User({
        name: 'Ananya Roy',
        username: 'ananya_female',
        phone: '+919112223344',
        email: 'ananya@demo.com',
        gender: 'female',
        passwordHash: hash,
        role: 'user',
        isVerified: true,
        currentLocation: { type: 'Point', coordinates: [76.2999, 9.9816] },
        trustedContacts: [
          { name: 'Mother', phone: '+919998887770', relation: 'Family' }
        ]
      });
      await ananya.save();

      // 2. Female User 2 (Priya) — With Ananya as Trusted Contact
      const priya = new User({
        name: 'Priya Sharma',
        username: 'priya_female',
        phone: '+919112223355',
        email: 'priya@demo.com',
        gender: 'female',
        passwordHash: hash,
        role: 'user',
        isVerified: true,
        currentLocation: { type: 'Point', coordinates: [76.3066, 10.0249] },
        trustedContacts: [
          { name: 'Ananya Roy', phone: '+919112223344', relation: 'Friend' }
        ]
      });
      await priya.save();

      // 3. Male User (Rohan) — With Ananya as Trusted Contact
      const rohan = new User({
        name: 'Rohan Mehta',
        username: 'rohan_male',
        phone: '+919223334466',
        email: 'rohan@demo.com',
        gender: 'male',
        passwordHash: hash,
        role: 'user',
        isVerified: true,
        currentLocation: { type: 'Point', coordinates: [76.3195, 9.9472] },
        trustedContacts: [
          { name: 'Ananya Roy', phone: '+919112223344', relation: 'Sister' }
        ]
      });
      await rohan.save();

      // 4. Volunteer (Rahul) — Unapproved
      const rahul = new Volunteer({
        name: 'Rahul Kumar',
        username: 'rahul_volunteer',
        phone: '+919998887776',
        email: 'volunteer@demo.com',
        passwordHash: hash,
        gender: 'male',
        isVerified: true,
        isApproved: false,
        address: 'Beach Road, Fort Kochi',
        currentLocation: { type: 'Point', coordinates: [76.2421, 9.9658] }
      });
      await rahul.save();

      // 5. Police (Officer Suresh)
      const suresh = new Authority({
        name: 'Officer Suresh',
        username: 'suresh_police',
        phone: '+911111111111',
        email: 'police@demo.com',
        passwordHash: hash,
        department: 'Central Police Station',
        badgeNumber: 'POL-12345',
        isVerified: true,
        currentLocation: { type: 'Point', coordinates: [76.2825, 9.9785] }
      });
      await suresh.save();

      console.log('📖 Restoring 8 Guides & Tutorials...');

      const guides = [
        {
          title: 'Self Defense Basics',
          type: 'guide',
          category: 'Tutorial',
          description: 'Learn 5 essential moves to protect yourself in physical confrontations.',
          duration: '6 mins',
          url: 'https://youtube.com/watch?v=sample1',
          icon: 'fitness_center',
          color: '#FFF1F2',
          iconColor: '#E11D48'
        },
        {
          title: 'Using SOS Features',
          type: 'guide',
          category: 'App Guide',
          description: 'Master the voice and volume triggers for silent, fast emergency alerts.',
          duration: '4 mins',
          url: 'https://youtube.com/watch?v=sample2',
          icon: 'security',
          color: '#F0F9FF',
          iconColor: '#0369A1'
        },
        {
          title: 'Digital Safety Tips',
          type: 'guide',
          category: 'Safety',
          description: 'How to keep your personal data and location private while online.',
          duration: '8 mins',
          url: 'https://youtube.com/watch?v=sample3',
          icon: 'phonelink_lock',
          color: '#F0FDF4',
          iconColor: '#16A34A'
        },
        {
          title: 'Safe Travel Handbook',
          type: 'guide',
          category: 'Travel',
          description: 'Best practices for navigating public transport and walking at night.',
          duration: '10 mins',
          url: 'https://youtube.com/watch?v=sample4',
          icon: 'directions_walk',
          color: '#FFF7ED',
          iconColor: '#EA580C'
        },
        {
          title: 'Women\'s Legal Rights',
          type: 'guide',
          category: 'Legal',
          description: 'Understand the legal protections and reporting mechanisms in India.',
          duration: '12 mins',
          url: 'https://youtube.com/watch?v=sample5',
          icon: 'gavel',
          color: '#F5F3FF',
          iconColor: '#7C3AED'
        },
        {
          title: 'Fake Call Usage',
          type: 'guide',
          category: 'App Guide',
          description: 'Using the simulated call feature to deter potential stalkers discreetly.',
          duration: '3 mins',
          url: 'https://youtube.com/watch?v=sample6',
          icon: 'phone_callback',
          color: '#ECFEFF',
          iconColor: '#0891B2'
        },
        {
          title: 'Volunteer Best Practices',
          type: 'guide',
          category: 'Community',
          description: 'How to safely and effectively respond to nearby distress alerts.',
          duration: '7 mins',
          url: 'https://youtube.com/watch?v=sample7',
          icon: 'groups',
          color: '#FDF2F8',
          iconColor: '#DB2777'
        },
        {
          title: 'Post-Incident Steps',
          type: 'guide',
          category: 'Safety',
          description: 'Immediate actions to take for evidence collection and support after an incident.',
          duration: '5 mins',
          url: 'https://youtube.com/watch?v=sample8',
          icon: 'fact_check',
          color: '#F1F5F9',
          iconColor: '#475569'
        }
      ];

      await Resource.insertMany(guides);
      console.log(`✅ Successfully restored 5 Core Users and ${guides.length} Guides.`);

      console.log('✅ Seeding complete.');
      process.exit(0);
    } catch (error) {
      console.error(`❌ Attempt failed: ${error.message}`);
      retries--;
      if (retries === 0) {
        console.error('❌ Max retries reached.');
        process.exit(1);
      }
      console.log('🔄 Retrying in 5 seconds...');
      await new Promise(res => setTimeout(res, 5000));
    }
  }
}

seedDatabase();
