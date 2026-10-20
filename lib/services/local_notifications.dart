import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'notification_scheduler.dart';

/// Notifikasi lokal Android lewat flutter_local_notifications (PRD 9.3):
/// zona waktu perangkat, alarm tepat jika diizinkan (selain itu inexact,
/// bisa tertunda beberapa menit), dan dijadwalkan ulang setelah restart oleh
/// boot receiver plugin.
class LocalNotifications implements NotificationScheduler {
  LocalNotifications._();

  static final instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  var _ready = false;

  /// Payload notifikasi yang membuka aplikasi dari keadaan tertutup.
  String? launchPayload;

  /// Payload setiap kali notifikasi diketuk saat aplikasi berjalan.
  Stream<String> get taps => _taps.stream;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init({bool background = false}) async {
    if (_ready || !_supported) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _taps.add(payload);
      },
    );
    if (!background) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchPayload = launch!.notificationResponse?.payload;
      }
    }
    _ready = true;
  }

  /// Izin POST_NOTIFICATIONS di Android 13+.
  Future<bool> requestPermission() async {
    if (!_supported) return true;
    return await _android?.requestNotificationsPermission() ?? true;
  }

  Future<bool> notificationsEnabled() async {
    if (!_supported) return true;
    return await _android?.areNotificationsEnabled() ?? true;
  }

  /// Android 14+ menolak alarm tepat secara bawaan untuk instalasi baru.
  Future<bool> canScheduleExact() async {
    if (!_supported) return true;
    return await _android?.canScheduleExactNotifications() ?? true;
  }

  /// Membuka layar izin "Alarm & pengingat".
  Future<void> requestExactAlarms() async {
    if (!_supported) return;
    await _android?.requestExactAlarmsPermission();
  }

  NotificationDetails _details(NotifyChannel channel) => NotificationDetails(
    android: AndroidNotificationDetails(
      channel.id,
      channel.label,
      importance: channel == NotifyChannel.orders
          ? Importance.high
          : Importance.defaultImportance,
      priority: channel == NotifyChannel.orders
          ? Priority.high
          : Priority.defaultPriority,
      category: channel == NotifyChannel.orders
          ? AndroidNotificationCategory.reminder
          : null,
    ),
  );

  @override
  Future<void> replaceScheduled(List<PlannedNotification> notifications) async {
    if (!_supported) return;
    await init(background: true);
    await _plugin.cancelAllPendingNotifications();
    final mode = await canScheduleExact()
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final n in notifications) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: _details(n.channel),
        androidScheduleMode: mode,
        title: n.title,
        body: n.body,
        payload: n.payload,
      );
    }
  }

  @override
  Future<void> showNow(PlannedNotification notification) async {
    if (!_supported) return;
    await init(background: true);
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: _details(notification.channel),
      payload: notification.payload,
    );
  }
}
