import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' hide NotificationVisibility;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import 'guarding_api_service.dart';
import 'api_service.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:record/record.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:perfect_volume_control/perfect_volume_control.dart';

const notificationChannelId = 'guarding_foreground';
const notificationId = 888;
DateTime? _lastVoiceSosTime;

// --- Background Service State (Top-level) ---
final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
Model? _voskModel;
Recognizer? _voskRecognizer;
final AudioRecorder _recorder = AudioRecorder();
StreamSubscription<Uint8List>? _audioStream;
String _backgroundTriggerWord = "red";
bool _pauseVolumeListener = false;

List<DateTime> _volumeClickTimes = [];
Timer? _sosCountdownTimer;
int _remainingSeconds = 0;

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  // Initialize notifications for Android Foreground Service
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'Guarding Mode', // title
    description: 'Continuously syncing location for your safety.', // description
    importance: Importance.low, // low importance keeps it from ringing constantly
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: notificationChannelId,
      initialNotificationTitle: 'Guarding Mode Active',
      initialNotificationContent: 'Connecting...',
      foregroundServiceNotificationId: notificationId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('ic_bg_service_small');
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload == 'cancel_sos') {
        service.invoke('cancelSos');
      }
    },
  );

  // Allow UI to stop service
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Handle Cancellation
  service.on('cancelSos').listen((event) {
    debugPrint("SOS CANCELLED BY USER");
    _sosCountdownTimer?.cancel();
    _sosCountdownTimer = null;
    flutterLocalNotificationsPlugin.cancel(id: notificationId + 5);
  });

  // Check if we have an active session
  final prefs = await SharedPreferences.getInstance();
  final sessionId = prefs.getString('active_guarding_session');
  final bool isAlwaysOnVoice = prefs.getBool('always_on_voice_enabled') ?? true;
  final String? authToken = prefs.getString('auth_token');
  final String? role = prefs.getString('user_role');
  final String? gender = prefs.getString('user_gender');

  // Hard stop: no one is signed in
  if (authToken == null || authToken.isEmpty) {
    debugPrint("Background Service stopped: No user signed in.");
    service.stopSelf();
    return;
  }

  // Fallback: If gender is null (legacy session), assume female to keep safety tools active.
  bool isAuthorizedRole = (role == 'user' || role == 'UserRole.user') && (gender != 'male');

  if (!isAuthorizedRole || (sessionId == null && !isAlwaysOnVoice)) {
    // Stop if role is not 'user'/female OR (no active guarding session AND always-on voice is disabled)
    debugPrint("Background Service stopped: Not authorized (role=$role, gender=$gender) or features disabled.");
    service.stopSelf();
    return;
  }

  String notificationTitle = sessionId != null ? 'Guarding Mode Active' : 'Always-On Safety Active';
  String notificationBody = sessionId != null 
      ? 'Tracking and syncing your location for your safety.'
      : 'Listening for your rescue word "red" hands-free.';

  flutterLocalNotificationsPlugin.show(
    id: notificationId,
    title: notificationTitle,
    body: notificationBody,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        'Guarding Mode',
        channelDescription: 'Continuously syncing location for your safety.',
        icon: 'ic_bg_service_small', 
        ongoing: true,
      ),
    ),
  );

  // Initialize Volume Listener
  PerfectVolumeControl.stream.listen((volume) {
    _handleVolumeClick(service, flutterLocalNotificationsPlugin);
  });

  // Start initial listening
  _startBackgroundListening(service, flutterLocalNotificationsPlugin);

  // Background Safety Check State
  int backgroundSecondsElapsed = 0;
  bool isSafetyCheckPending = false;
  Timer? backgroundSafetyTimer;

  // Listen for UI events
  service.on('safetyConfirmed').listen((event) {
    backgroundSecondsElapsed = 0;
    isSafetyCheckPending = false;
    backgroundSafetyTimer?.cancel();
    debugPrint("Background safety confirmed by UI");
  });

  service.on('checkStatus').listen((event) async {
    final checkPrefs = await SharedPreferences.getInstance();
    final sId = checkPrefs.getString('active_guarding_session');
    final isAoV = checkPrefs.getBool('always_on_voice_enabled') ?? true;
    if (sId == null && !isAoV) {
      service.stopSelf();
    }
  });

  // Periodically update location and check safety/arrival
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    if (service is AndroidServiceInstance) {
      if (!(await service.isForegroundService())) {
        timer.cancel();
        return;
      }
    }

    backgroundSecondsElapsed += 30;

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final currentPrefs = await SharedPreferences.getInstance();
      final currentSessionId = currentPrefs.getString('active_guarding_session');
      final currentIsAlwaysOn = currentPrefs.getBool('always_on_voice_enabled') ?? true;

      // Stop if both features are now disabled
      if (currentSessionId == null && !currentIsAlwaysOn) {
        service.stopSelf();
        return;
      }

      // --- FEATURE ISOLATION LOGIC ---
      if (currentSessionId != null) {
        final destLat = currentPrefs.getDouble('active_destination_lat');
        final destLng = currentPrefs.getDouble('active_destination_lng');

        // 1. Auto-Arrival Detection (20m)
        if (destLat != null && destLng != null) {
          double distance = _calculateDistance(
            position.latitude,
            position.longitude,
            destLat,
            destLng,
          );
          if (distance < 20) {
            debugPrint("Arrived at destination in background. Stopping service.");
            service.invoke('stopService');
            return;
          }
        }

        // 2. Safety Check Trigger (every 5 mins)
        if (backgroundSecondsElapsed >= 300 && !isSafetyCheckPending) {
          isSafetyCheckPending = true;
          _showBackgroundSafetyNotification(flutterLocalNotificationsPlugin);
          
          backgroundSafetyTimer = Timer(const Duration(seconds: 60), () async {
            if (isSafetyCheckPending) {
              debugPrint("Background safety check failed. Alerting contacts.");
              await ApiService.alertTrustedContacts(
                position.latitude, 
                position.longitude, 
                "Automated Background Safety Check Failure"
              );
              isSafetyCheckPending = false;
              backgroundSecondsElapsed = 0;
            }
          });
        }

        // 3. Sync Location with Backend
        if (currentSessionId != 'local_offline_session') {
          await GuardingApiService.updateLocation(
            currentSessionId, 
            position.latitude, 
            position.longitude
          );
        }
      } else {
        // Guarding Mode is OFF. Only Voice Listener runs.
        // We do NOT sync location or run arrival/safety checks here.
        debugPrint("Background: Continuous Voice SOS active (No location syncing).");
      }
    } catch (e) {
      debugPrint("Error in background loop: $e");
    }
  });
}

Future<void> _startBackgroundListening(ServiceInstance service, FlutterLocalNotificationsPlugin notifications) async {
  try {
    final p = await SharedPreferences.getInstance();
    _backgroundTriggerWord = p.getString('active_sos_trigger_word') ?? "help";

    // 1. Initialize Model if not already loaded
    if (_voskModel == null) {
      debugPrint("Vosk: Extracting model from assets...");
      final String modelPath = await ModelLoader()
          .loadFromAssets('assets/models/vosk-model.zip');
      
      debugPrint("Vosk: Model extracted to $modelPath");
      _voskModel = await _vosk.createModel(modelPath);
      debugPrint("Vosk: Model instance created.");
    }

    // 2. Setup Recognizer
    if (_voskRecognizer == null && _voskModel != null) {
      _voskRecognizer = await _vosk.createRecognizer(
        model: _voskModel!,
        sampleRate: 16000,
      );
    }

    if (_voskRecognizer == null) return;

    // 3. Start Recording Stream (16kHz Mono)
    if (await _recorder.hasPermission()) {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _recorder.startStream(config);
      
      _audioStream?.cancel();
      _audioStream = stream.listen((Uint8List data) async {
        final isFinal = await _voskRecognizer!.acceptWaveformBytes(data);
        final resultJson = isFinal 
            ? await _voskRecognizer!.getResult() 
            : await _voskRecognizer!.getPartialResult();

        if (resultJson.isNotEmpty) {
          try {
            final Map<String, dynamic> result = json.decode(resultJson);
            String words = (result['text'] ?? result['partial'] ?? '').toString().toLowerCase();
            
            if (words.contains(_backgroundTriggerWord) || words.contains("sos")) {
               await _handleVoskTrigger(notifications);
            }
          } catch (e) {
            // Partial results can be ignored
          }
        }
      });
      debugPrint("Vosk: Silent offline listener active.");
    }
  } catch (e) {
    debugPrint("Vosk Initialization Error: $e");
  }
}

Future<void> _handleVoskTrigger(FlutterLocalNotificationsPlugin notifications) async {
  final now = DateTime.now();
  if (_lastVoiceSosTime != null && now.difference(_lastVoiceSosTime!).inMinutes < 2) {
    return;
  }
  _lastVoiceSosTime = now;
  
  debugPrint("CORE ALERT: Vosk Offline SOS Triggered!");
  
  Position pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
  );
  await ApiService.triggerSOS("Offline Voice Trigger", pos.latitude, pos.longitude);
  
  notifications.show(
    id: notificationId + 2,
    title: '🚨 EMERGENCY SOS TRIGGERED',
    body: 'Detected offline voice trigger. Alerting contacts!',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        'Guarding Mode',
        importance: Importance.max,
        priority: Priority.high,
        color: Colors.red,
        ongoing: false,
        playSound: false,
        enableVibration: false,
        icon: 'ic_bg_service_small', 
      ),
    ),
  );
}

void _handleVolumeClick(ServiceInstance service, FlutterLocalNotificationsPlugin notifications) async {
  if (_pauseVolumeListener) return;
  
  final now = DateTime.now();
  _volumeClickTimes.add(now);
  
  if (_volumeClickTimes.length > 3) {
    _volumeClickTimes.removeAt(0);
  }

  if (_volumeClickTimes.length == 3) {
    final firstClick = _volumeClickTimes[0];
    if (now.difference(firstClick).inSeconds <= 2) {
      debugPrint("PHYSICAL TRIGGER: 3 clicks detected! Starting 5s countdown...");
      _volumeClickTimes.clear(); 
      _startNotificationCountdown(service, notifications);
    }
  }

  try {
    double currentVolume = await PerfectVolumeControl.getVolume();
    if (currentVolume >= 1.0) {
      _pauseVolumeListener = true;
      await PerfectVolumeControl.setVolume(0.85);
      Future.delayed(const Duration(milliseconds: 300), () { _pauseVolumeListener = false; });
    } else if (currentVolume <= 0.0) {
      _pauseVolumeListener = true;
      await PerfectVolumeControl.setVolume(0.15);
      Future.delayed(const Duration(milliseconds: 300), () { _pauseVolumeListener = false; });
    }
  } catch (e) {
    debugPrint("Volume boundary adjust error: $e");
  }
}

void _startNotificationCountdown(ServiceInstance service, FlutterLocalNotificationsPlugin notifications) {
  if (_sosCountdownTimer != null) return;

  _remainingSeconds = 5;
  
  void updateNotification() {
    notifications.show(
      id: notificationId + 5,
      title: '🚨 EMERGENCY SOS ACTIVATING',
      body: 'Activating in $_remainingSeconds seconds...',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          'Guarding Mode',
          importance: Importance.max,
          priority: Priority.high,
          color: Colors.red,
          ongoing: true,
          icon: 'ic_bg_service_small',
          actions: <AndroidNotificationAction>[
            const AndroidNotificationAction(
              'cancel_sos',
              'CANCEL SOS',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: 'cancel_sos',
    );
  }

  updateNotification();

  _sosCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
    _remainingSeconds--;
    if (_remainingSeconds <= 0) {
      timer.cancel();
      _sosCountdownTimer = null;
      notifications.cancel(id: notificationId + 5);
      await _triggerSosImmediately(notifications);
    } else {
      updateNotification();
    }
  });
}

Future<void> _triggerSosImmediately(FlutterLocalNotificationsPlugin notifications) async {
  try {
    Position pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
    );
    await ApiService.triggerSOS("Physical Button Trigger", pos.latitude, pos.longitude);
    
    notifications.show(
      id: notificationId + 3,
      title: '🚨 EMERGENCY SOS TRIGGERED',
      body: 'Physical button pattern detected. Alerting contacts!',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          notificationChannelId,
          'Guarding Mode',
          importance: Importance.max,
          priority: Priority.high,
          color: Colors.red,
          playSound: false,
          enableVibration: false,
          icon: 'ic_bg_service_small', 
        ),
      ),
    );
  } catch (e) {
    debugPrint("SOS Trigger Error: $e");
  }
}

double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295;
  final haversine = 0.5 -
      math.cos((lat2 - lat1) * p) / 2 +
      math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
  return 12742 * math.asin(math.sqrt(haversine)) * 1000;
}

void _showBackgroundSafetyNotification(FlutterLocalNotificationsPlugin plugin) {
  plugin.show(
    id: notificationId + 1,
    title: 'Safety Check',
    body: 'Are you safe? Please confirm now.',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannelId,
        'Guarding Mode',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        actions: <AndroidNotificationAction>[
          const AndroidNotificationAction(
            'safe_action',
            "I'M SAFE",
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
    ),
  );
}
