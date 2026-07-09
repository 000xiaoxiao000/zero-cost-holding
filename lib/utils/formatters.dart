import 'package:intl/intl.dart';

class Formatters {
  static final _price = NumberFormat('#,##0.000', 'zh_CN');
  static final _pctSimple = NumberFormat('#,##0.00', 'zh_CN');
  static final _large = NumberFormat('#,##0.00', 'zh_CN');
  static final _date = DateFormat('yyyy-MM-dd');
  static final _dateShort = DateFormat('MM/dd');
  static final _dateTime = DateFormat('MM-dd HH:mm');

  static String price(double v) => _price.format(v);

  static String quantity(double v) {
    if (v == v.roundToDouble()) {
      return NumberFormat('#,##0', 'zh_CN').format(v);
    }
    return NumberFormat('#,##0.####', 'zh_CN').format(v);
  }

  static String change(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${_price.format(v)}';
  }

  static String percent(double v) {
    final sign = v >= 0 ? '+' : '';
    return '$sign${_pctSimple.format(v)}%';
  }

  static String date(DateTime d) => _date.format(d);
  static String dateShort(DateTime d) => _dateShort.format(d);
  static String dateTime(DateTime d) => _dateTime.format(d);

  /// 格式化大数字（亿/万）
  static String largeNumber(double v) {
    if (v.abs() >= 1e8) {
      return '${_large.format(v / 1e8)}亿';
    } else if (v.abs() >= 1e4) {
      return '${_large.format(v / 1e4)}万';
    }
    return _large.format(v);
  }

  static String marketCap(double v) {
    if (v <= 0) return '-';
    if (v >= 1e12) return '${(v / 1e12).toStringAsFixed(2)}万亿';
    if (v >= 1e8) return '${(v / 1e8).toStringAsFixed(2)}亿';
    return '${(v / 1e4).toStringAsFixed(2)}万';
  }
}
