import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class AlertPollingConfig {
  final bool enabled;
  final int intervalMinutes;
  final int startMinutes;
  final int endMinutes;

  const AlertPollingConfig({
    required this.enabled,
    required this.intervalMinutes,
    required this.startMinutes,
    required this.endMinutes,
  });

  static const defaultConfig = AlertPollingConfig(
    enabled: true,
    intervalMinutes: 3,
    startMinutes: 9 * 60 + 25,
    endMinutes: 15 * 60 + 5,
  );

  Duration get interval => Duration(minutes: intervalMinutes);

  String get startText => formatMinutes(startMinutes);
  String get endText => formatMinutes(endMinutes);

  AlertPollingConfig copyWith({
    bool? enabled,
    int? intervalMinutes,
    int? startMinutes,
    int? endMinutes,
  }) {
    return AlertPollingConfig(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
    );
  }

  static String formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class AlertPollingConfigService {
  static final AlertPollingConfigService _instance =
      AlertPollingConfigService._internal();
  factory AlertPollingConfigService() => _instance;
  AlertPollingConfigService._internal();

  static const _enabledKey = 'alert_polling_enabled';
  static const _intervalKey = 'alert_polling_interval_minutes';
  static const _startKey = 'alert_polling_start_minutes';
  static const _endKey = 'alert_polling_end_minutes';

  AlertPollingConfig? _cached;

  Future<AlertPollingConfig> load() async {
    if (_cached != null) return _cached!;

    final prefs = await SharedPreferences.getInstance();
    final defaults = AlertPollingConfig.defaultConfig;
    final config = AlertPollingConfig(
      enabled: prefs.getBool(_enabledKey) ?? defaults.enabled,
      intervalMinutes: _normalizeInterval(
        prefs.getInt(_intervalKey) ?? defaults.intervalMinutes,
      ),
      startMinutes: _normalizeMinuteOfDay(
        prefs.getInt(_startKey) ?? defaults.startMinutes,
      ),
      endMinutes: _normalizeMinuteOfDay(
        prefs.getInt(_endKey) ?? defaults.endMinutes,
      ),
    );
    _cached = _normalizeWindow(config);
    return _cached!;
  }

  Future<void> save(AlertPollingConfig config) async {
    final normalized = _normalizeWindow(
      config.copyWith(
        intervalMinutes: _normalizeInterval(config.intervalMinutes),
        startMinutes: _normalizeMinuteOfDay(config.startMinutes),
        endMinutes: _normalizeMinuteOfDay(config.endMinutes),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, normalized.enabled);
    await prefs.setInt(_intervalKey, normalized.intervalMinutes);
    await prefs.setInt(_startKey, normalized.startMinutes);
    await prefs.setInt(_endKey, normalized.endMinutes);
    _cached = normalized;
  }

  int _normalizeInterval(int value) => value.clamp(1, 60);

  int _normalizeMinuteOfDay(int value) => value.clamp(0, 23 * 60 + 59);

  AlertPollingConfig _normalizeWindow(AlertPollingConfig config) {
    if (config.startMinutes <= config.endMinutes) return config;
    return config.copyWith(
      startMinutes: math.min(config.startMinutes, config.endMinutes),
      endMinutes: math.max(config.startMinutes, config.endMinutes),
    );
  }
}
