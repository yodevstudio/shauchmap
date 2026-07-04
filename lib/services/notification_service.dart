import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  final List<String> _reengagementTitles = [
    "It's quiet out there",
    "Ready for a clean break?",
    "Your map needs you",
  ];
  final List<String> _reengagementBodies = [
    "Help others find safe restrooms nearby.",
    "Add or review a toilet to help the community.",
    "Share a clean spot today.",
  ];

  final List<String> _rateVisitTitles = [
    "How was your visit?",
    "Rate your recent stop",
    "Share your experience",
  ];
  final List<String> _rateVisitBodies = [
    "Your review helps keep the map accurate.",
    "Did it meet expectations? Let others know.",
    "Tap to rate the toilet you visited.",
  ];

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      tz.initializeTimeZones();
      String timeZoneName = (await FlutterTimezone.getLocalTimezone())
          .toString();
      if (timeZoneName.startsWith('TimezoneInfo(')) {
        final parts = timeZoneName.split(',');
        if (parts.isNotEmpty) {
          timeZoneName = parts[0].replaceAll('TimezoneInfo(', '').trim();
        }
      }
      tz.setLocalLocation(tz.getLocation(timeZoneName));

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint("Notification init error: $e");
    }
  }

  Future<void> requestPermissionIfNeeded() async {
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint("Notification permission error: $e");
    }
  }

  Future<bool> _canScheduleThisWeek() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekStartMs = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    ).millisecondsSinceEpoch;

    final currentWeekStartMs = prefs.getInt('notif_week_start_ms') ?? 0;
    int count = prefs.getInt('notif_week_count') ?? 0;

    if (currentWeekStartMs != weekStartMs) {
      await prefs.setInt('notif_week_start_ms', weekStartMs);
      await prefs.setInt('notif_week_count', 0);
      count = 0;
    }
    return count < 2;
  }

  Future<void> _recordScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('notif_week_count') ?? 0;
    await prefs.setInt('notif_week_count', count + 1);
  }

  tz.TZDateTime _getValidTime(tz.TZDateTime scheduledTime) {
    if (scheduledTime.hour >= 21) {
      return tz.TZDateTime(
        tz.local,
        scheduledTime.year,
        scheduledTime.month,
        scheduledTime.day + 1,
        9,
      );
    } else if (scheduledTime.hour < 9) {
      return tz.TZDateTime(
        tz.local,
        scheduledTime.year,
        scheduledTime.month,
        scheduledTime.day,
        9,
      );
    }
    return scheduledTime;
  }

  Future<void> scheduleReengagementNudge() async {
    try {
      if (!_isInitialized) await init();
      await _flutterLocalNotificationsPlugin.cancel(id: 1);

      if (!await _canScheduleThisWeek()) return;

      final prefs = await SharedPreferences.getInstance();
      int index = prefs.getInt('notif_reengage_idx') ?? 0;
      final title = _reengagementTitles[index % _reengagementTitles.length];
      final body = _reengagementBodies[index % _reengagementBodies.length];
      await prefs.setInt('notif_reengage_idx', index + 1);

      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 4,
        18,
      );
      scheduledDate = _getValidTime(scheduledDate);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'reengage_channel',
            'Re-engagement',
            channelDescription: 'Reminders to help the community',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 1,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
      await _recordScheduled();
    } catch (e) {
      debugPrint("scheduleReengagementNudge error: $e");
    }
  }

  Future<void> scheduleRateVisitNudge() async {
    try {
      if (!_isInitialized) await init();
      await _flutterLocalNotificationsPlugin.cancel(id: 2);

      if (!await _canScheduleThisWeek()) return;

      final prefs = await SharedPreferences.getInstance();
      final toiletName = prefs.getString('pending_review_toilet_name');
      if (toiletName == null) return;

      int index = prefs.getInt('notif_rate_idx') ?? 0;
      final title = _rateVisitTitles[index % _rateVisitTitles.length];
      final body = _rateVisitBodies[index % _rateVisitBodies.length];
      await prefs.setInt('notif_rate_idx', index + 1);

      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        10,
      );
      scheduledDate = _getValidTime(scheduledDate);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'rate_channel',
            'Review Reminders',
            channelDescription: 'Reminders to rate your recent visits',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id: 2,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
      await _recordScheduled();
    } catch (e) {
      debugPrint("scheduleRateVisitNudge error: $e");
    }
  }

  Future<void> cancelRateVisitNudge() async {
    try {
      if (!_isInitialized) await init();
      await _flutterLocalNotificationsPlugin.cancel(id: 2);
    } catch (e) {
      debugPrint("cancelRateVisitNudge error: $e");
    }
  }

  Future<void> resetReengagementNudge() async {
    await scheduleReengagementNudge();
  }
}
