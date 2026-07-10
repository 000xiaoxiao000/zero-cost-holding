import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 系统通知服务 — 盘中价格提醒
///
/// 使用方式：
///   1. main() 中调用 await NotificationService().init()
///   2. 行情轮询回调里调用 checkAndNotify(...)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 已推送记录（code → 上次推送的价格区间，防止重复轰炸）
  final Map<String, _NotifyRecord> _lastNotified = {};

  // 同一标的两次推送之间的最短冷却时间（分钟）
  static const _cooldownMinutes = 30;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
    dev.log('NotificationService 初始化完成', name: 'NotificationService');
  }

  /// 请求 Android 13+ 通知权限（在 init 之后调用一次即可）
  Future<void> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  /// 检查价格并在触及目标价/警戒价时发送通知
  ///
  /// [code]        股票代码
  /// [name]        股票名称
  /// [price]       当前价格
  /// [targetPrice] 目标价（涨到此价位时提醒收割）
  /// [alertPrice]  警戒价（跌到此价位时提醒关注）
  Future<void> checkAndNotify({
    required String code,
    required String name,
    required double price,
    double? targetPrice,
    double? alertPrice,
  }) async {
    if (!_initialized || price <= 0) return;

    final record = _lastNotified[code];
    final now = DateTime.now();

    // 目标价触发（上穿目标价）
    if (targetPrice != null && targetPrice > 0 && price >= targetPrice) {
      if (_canNotify(record, 'target', now)) {
        await _send(
          id: code.hashCode & 0x7FFFFFFF,
          title: '收割提醒 · $name',
          body:
              '现价 ¥${price.toStringAsFixed(3)} 已触及目标价 ¥${targetPrice.toStringAsFixed(3)}，可考虑按计划回收部分仓位',
          channelId: 'harvest',
          channelName: '收割提醒',
        );
        _lastNotified[code] = _NotifyRecord(type: 'target', time: now);
        return;
      }
    }

    // 警戒价触发（下穿警戒价）
    if (alertPrice != null && alertPrice > 0 && price <= alertPrice) {
      if (_canNotify(record, 'alert', now)) {
        await _send(
          id: (code.hashCode + 1) & 0x7FFFFFFF,
          title: '警戒提醒 · $name',
          body:
              '现价 ¥${price.toStringAsFixed(3)} 已触及警戒价 ¥${alertPrice.toStringAsFixed(3)}，请关注风险',
          channelId: 'alert',
          channelName: '警戒提醒',
        );
        _lastNotified[code] = _NotifyRecord(type: 'alert', time: now);
      }
    }
  }

  /// 检查播种账本批次，并在触及回收价时提醒按计划收割。
  Future<void> checkRecoverAndNotify({
    required String code,
    required String name,
    required int batchId,
    required double price,
    required double recoverPrice,
    double? recoverQuantity,
    String quantityUnit = '股',
  }) async {
    if (!_initialized || price <= 0 || recoverPrice <= 0) return;
    if (price < recoverPrice) return;

    final key = 'recover:$batchId';
    final record = _lastNotified[key];
    final now = DateTime.now();
    if (!_canNotify(record, 'recover', now)) return;

    final quantityText = recoverQuantity != null && recoverQuantity > 0
        ? '，计划回收 ${_formatQuantity(recoverQuantity)}$quantityUnit'
        : '';
    await _send(
      id: key.hashCode & 0x7FFFFFFF,
      title: '回收触发 · $name',
      body:
          '现价 ¥${price.toStringAsFixed(3)} 已达到回收触发价 ¥${recoverPrice.toStringAsFixed(3)}$quantityText，可检查零成本收割计划',
      channelId: 'recover',
      channelName: '回收触发提醒',
    );
    _lastNotified[key] = _NotifyRecord(type: 'recover', time: now);
  }

  /// 检查播种计划下一档，并在触及灌溉价时提醒低吸检查。
  Future<void> checkIrrigationAndNotify({
    required String code,
    required String name,
    required String planKey,
    required int batchIndex,
    required double price,
    required double irrigationPrice,
  }) async {
    if (!_initialized || price <= 0 || irrigationPrice <= 0) return;
    if (price > irrigationPrice) return;

    final key = 'irrigation:$planKey:$batchIndex';
    final record = _lastNotified[key];
    final now = DateTime.now();
    if (!_canNotify(record, 'irrigation', now)) return;

    await _send(
      id: key.hashCode & 0x7FFFFFFF,
      title: '灌溉提醒 · $name',
      body:
          '现价 ¥${price.toStringAsFixed(3)} 已达到第 $batchIndex 批灌溉价 ¥${irrigationPrice.toStringAsFixed(3)}，可检查播种计划',
      channelId: 'irrigation',
      channelName: '灌溉低吸提醒',
    );
    _lastNotified[key] = _NotifyRecord(type: 'irrigation', time: now);
  }

  bool _canNotify(_NotifyRecord? record, String type, DateTime now) {
    if (record == null) return true;
    if (record.type != type) return true;
    return now.difference(record.time).inMinutes >= _cooldownMinutes;
  }

  Future<void> _send({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBanner: true,
      ),
    );
    try {
      await _plugin.show(id, title, body, details);
    } catch (e) {
      dev.log('通知发送失败: $e', name: 'NotificationService');
    }
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}

class _NotifyRecord {
  final String type;
  final DateTime time;
  const _NotifyRecord({required this.type, required this.time});
}
