import Message from '../models/Message.js';
import Alert from '../models/Alert.js';

// @desc    Get all messages for an SOS alert
// @route   GET /api/chat/:alertId
// @access  Private
const getSOSMessages = async (req, res) => {
  try {
    const { alertId } = req.params;

    // Optional: Verify user has access to this alert (triggered it, or is notified volunteer/authority)
    const messages = await Message.find({ alert: alertId }).sort('createdAt');

    res.json({
      success: true,
      data: messages,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

// @desc    Send a message in an SOS alert chat
// @route   POST /api/chat/:alertId
// @access  Private
const sendSOSMessage = async (req, res) => {
  try {
    const { alertId } = req.params;
    const { content } = req.body;

    if (!content || content.trim() === '') {
      return res.status(400).json({ success: false, message: 'Message content is required' });
    }

    const alert = await Alert.findById(alertId);
    if (!alert) {
      return res.status(404).json({ success: false, message: 'Alert not found' });
    }

    const message = await Message.create({
      alert: alertId,
      victim: alert.user, // The person who triggered the SOS
      incident: alert.incident, // Linked incident context
      sender: req.user._id,
      senderName: req.user.name,
      senderRole: req.user.role, // 'user', 'volunteer', or 'authority'
      content,
    });

    res.status(201).json({
      success: true,
      data: message,
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: error.message,
    });
  }
};

export {
  getSOSMessages,
  sendSOSMessage,
};
