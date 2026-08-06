import dotenv from 'dotenv';
import nodemailer from 'nodemailer';
import twilio from 'twilio';

dotenv.config();

// Initialize Twilio client if credentials exist
const twilioClient = process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN 
  ? twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN)
  : null;

// Initialize Nodemailer transporter if credentials exist
const transporter = process.env.EMAIL_USER && process.env.EMAIL_PASS
  ? nodemailer.createTransport({
      service: process.env.EMAIL_SERVICE || 'gmail',
      auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS,
      },
    })
  : null;

/**
 * Utility to send emails.
 * Uses Nodemailer if configured, otherwise falls back to console logging.
 */
export const sendEmail = async ({ to, subject, body, otp }) => {
  console.log(`\n--- [MAIL SERVICE] Processing for ${to} ---`);
  
  if (otp) {
    console.log(`🔑 [DEVELOPER] Email OTP for ${to}: ${otp}`);
  }

  if (transporter) {
//...

    try {
      await transporter.sendMail({
        from: process.env.EMAIL_FROM || process.env.EMAIL_USER,
        to,
        subject,
        text: body,
      });
      console.log(`✅ Email sent successfully to ${to}`);
      return true;
    } catch (error) {
      console.error(`❌ Email failed for ${to}:`, error.message);
    }
  }

  console.log(`[DEV/MOCK] Subject: ${subject}`);
  console.log(`[DEV/MOCK] Body Snippet: ${body.substring(0, 50)}...`);
  console.log(`--- [END MAIL] ---\n`);

  return true;
};

/**
 * Utility to send SMS.
 * Uses Twilio if configured, otherwise falls back to console logging.
 */
export const sendSMS = async ({ to, message, otp }) => {
  console.log(`\n--- [SMS SERVICE] Processing for ${to} ---`);
  console.log(`🔑 [DEVELOPER] Message: ${message}`);

  if (otp) {
    console.log(`🔑 [DEVELOPER] SMS OTP for ${to}: ${otp}`);
  }

  if (twilioClient && process.env.TWILIO_PHONE_NUMBER) {
//...

    try {
      await twilioClient.messages.create({
        body: message,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: to.startsWith('+') ? to : `+91${to}`, // Default to +91 if no country code
      });
      console.log(`✅ SMS sent successfully to ${to}`);
      return true;
    } catch (error) {
      console.error(`❌ SMS failed for ${to}:`, error.message);
    }
  }

  console.log(`--- [END SMS] ---\n`);

  return true;
};



