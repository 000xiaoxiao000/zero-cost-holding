import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import '../models/stock.dart';
import '../models/watchlist.dart';
import 'api_config.dart';

// ── 辅助数据类（顶层，供类内方法引用） ────────────────────────────────────────

class _SinaFinanceResult {
  final double? debtRatio;
  final double? cashflowMargin;
  final double? dividendYield;
  final int dividendYears;
  const _SinaFinanceResult({
    this.debtRatio,
    this.cashflowMargin,
    this.dividendYield,
    this.dividendYears = 0,
  });
}

class AutoRiskData {
  final double? pledgeRatio;
  final double? debtRatio;
  final double? goodwillRatio;
  final double? cashflowMargin;
  final double? dividendYield;
  final int? dividendYears;
  final String? dividendStability;
  final List<String> sourceNotes;
  final bool isFund;
  const AutoRiskData({
    this.pledgeRatio,
    this.debtRatio,
    this.goodwillRatio,
    this.cashflowMargin,
    this.dividendYield,
    this.dividendYears,
    this.dividendStability,
    this.sourceNotes = const [],
    this.isFund = false,
  });
  bool get hasDeepData =>
      pledgeRatio != null || debtRatio != null || goodwillRatio != null ||
      cashflowMargin != null || dividendYield != null || dividendYears != null;
}

// ── 主服务类 ──────────────────────────────────────────────────────────────────

class StockApiService {
  static final StockApiService _instance = StockApiService._internal();
  factory StockApiService() => _instance;
  StockApiService._internal();

  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        'Referer': 'https://finance.sina.com.cn/',
      },
    ));
  }

  // ── 工具 ──────────────────────────────────────────────────────────────────

  String _sinaCode(String code, String market) => '${market.toLowerCase()}$code';
  String _emSecid(String code, String market) => '${market == "SH" ? 1 : 0}.$code';

  String _inferMarket(String code) {
    if (code.startsWith('6') || code.startsWith('5') || code.startsWith('9')) return 'SH';
    if (code.startsWith('8') || code.startsWith('43') || code.startsWith('40')) return 'BJ';
    return 'SZ';
  }

  bool isFundCode(String code) => _isFundCode(code);
  String inferMarket(String code) => _inferMarket(code);

  bool _isFundCode(String code) =>
      code.startsWith('15') || code.startsWith('16') || code.startsWith('17') ||
      code.startsWith('18') || code.startsWith('51') || code.startsWith('56') ||
      code.startsWith('58') || code.startsWith('50');

  double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll('%', '').replaceAll(',', '').trim();
    if (s.isEmpty || s == '-' || s == '--') return null;
    return double.tryParse(s);
  }

  void _log(String msg) => dev.log(msg, name: 'StockApiService');

  String _decodeGbkBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';
    try {
      final s = utf8.decode(bytes);
      if (!s.contains('\uFFFD')) return s;
    } catch (_) {}
    // 无 GBK 解码器，回退 latin1：ASCII 段（数字/日期/符号）完全正确，
    // 中文段为乱码（需调用方用 UTF-8 接口另行补充中文）
    return latin1.decode(bytes, allowInvalid: true);
  }

  /// 判断字符串是否为 GBK→latin1 乱码：
  /// 乱码文本几乎全是 U+0080~U+00FF 的 Latin-1 补充字符，且不含正常 CJK。
  bool _looksMojibake(String s) {
    if (s.isEmpty) return false;
    final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(s);
    if (hasCjk) return false;
    final latinSupp = s.runes.where((r) => r >= 0x80 && r <= 0xFF).length;
    // 超过 1 个高位拉丁字符且无 CJK，判定为乱码
    return latinSupp >= 1;
  }

  // ── 名称补查 ──────────────────────────────────────────────────────────────

  Future<String> fetchStockName(String code) async {
    try {
      final resp = await _dio.get(
        ApiConfig.emSuggestBase,
        queryParameters: {
          'input': code, 'type': '14',
          'token': 'D43BF722C8E33BDC906FB84D85E326E8',
          'count': 5, 'markettype': '',
        },
        options: Options(headers: {'Referer': 'https://www.eastmoney.com/'}),
      );
      final raw = resp.data;
      Map<String, dynamic> data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw as Map);
      } else {
        final str = raw.toString().trim();
        if (str.startsWith('<')) return '';
        data = Map<String, dynamic>.from(jsonDecode(str) as Map);
      }
      final items = (data['QuotationCodeTable']?['Data'] as List?) ?? [];
      for (final e in items.whereType<Map>()) {
        if (e['Code']?.toString() == code) return e['Name']?.toString() ?? '';
      }
      if (items.isNotEmpty) return (items.first as Map)['Name']?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  // ── 实时行情 ──────────────────────────────────────────────────────────────

  /// 优先腾讯sqt → 新浪 → 聚合 → 东方财富；名称由 fetchStockName 兜底
  Future<Stock?> fetchStockQuote(String code, String market) async {
    Stock? r;
    r = await _quoteSqt(code, market);
    if (r != null) { _log('行情[sqt] $code OK'); }
    if (r == null) {
      r = await _quoteSina(code, market);
      if (r != null) { _log('行情[新浪] $code OK'); }
    }
    if (r == null && ApiConfig.hasJuheKey) {
      r = await _quoteJuhe(code, market);
      if (r != null) { _log('行情[聚合] $code OK'); }
    }
    if (r == null) {
      r = await _quoteEM(code, market);
      if (r != null) { _log('行情[EM] $code OK'); }
    }
    if (r == null) { _log('行情 $code 全部源失败'); return null; }
    // 名称为空或为 GBK 乱码时，用东方财富 suggest（UTF-8）补查
    if (r.name.isEmpty || _looksMojibake(r.name)) {
      final name = await fetchStockName(code);
      if (name.isNotEmpty) r = r.copyWith(name: name);
    }
    return r;
  }

  Future<Stock?> _quoteSqt(String code, String market) async {
    try {
      final resp = await _dio.get(
        'https://sqt.gtimg.cn/q=${_sinaCode(code, market)}',
        options: Options(responseType: ResponseType.bytes, headers: {'Referer': 'https://gu.qq.com/'}),
      );
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);
      final match = RegExp(r'"([^"]+)"').firstMatch(body);
      if (match == null) return null;
      final p = match.group(1)!.split('~');
      if (p.length < 40 || p[1].isEmpty) return null;
      final price = double.tryParse(p[3]) ?? 0.0;
      final preClose = double.tryParse(p[4]) ?? 0.0;
      if (price <= 0) return null;
      final marketCapYi = double.tryParse(p.length > 44 ? p[44] : '') ?? 0.0;
      return Stock(
        code: code, name: p[1], market: market,
        price: price, change: price - preClose,
        changePercent: preClose > 0 ? (price - preClose) / preClose * 100 : 0.0,
        open: double.tryParse(p[5]) ?? 0.0,
        high: double.tryParse(p.length > 33 ? p[33] : '') ?? 0.0,
        low: double.tryParse(p.length > 34 ? p[34] : '') ?? 0.0,
        preClose: preClose,
        volume: (double.tryParse(p[6]) ?? 0.0) * 100,
        turnover: double.tryParse(p.length > 37 ? p[37] : '') ?? 0.0,
        pe: double.tryParse(p.length > 39 ? p[39] : '') ?? 0.0,
        pb: double.tryParse(p.length > 46 ? p[46] : '') ?? 0.0,
        marketCap: marketCapYi > 0 ? marketCapYi * 1e8 : 0.0,
      );
    } catch (_) { return null; }
  }

  Future<Stock?> _quoteSina(String code, String market) async {
    try {
      final resp = await _dio.get(
        '${ApiConfig.sinaQuoteBase}/list=${_sinaCode(code, market)}',
        options: Options(responseType: ResponseType.bytes),
      );
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);
      final match = RegExp(r'"([^"]+)"').firstMatch(body);
      if (match == null) return null;
      final p = match.group(1)!.split(',');
      if (p.length < 10) return null;
      final price = double.tryParse(p[3]) ?? 0.0;
      final preClose = double.tryParse(p[2]) ?? 0.0;
      if (price <= 0) return null;
      return Stock(
        code: code, name: '', market: market,
        price: price, change: price - preClose,
        changePercent: preClose > 0 ? (price - preClose) / preClose * 100 : 0.0,
        open: double.tryParse(p[1]) ?? 0.0,
        high: double.tryParse(p[4]) ?? 0.0,
        low: double.tryParse(p[5]) ?? 0.0,
        preClose: preClose,
        volume: (double.tryParse(p[8]) ?? 0.0) * 100,
        turnover: double.tryParse(p[9]) ?? 0.0,
      );
    } catch (_) { return null; }
  }

  Future<Stock?> _quoteJuhe(String code, String market) async {
    try {
      final resp = await _dio.get(ApiConfig.juheQuoteUrl,
          queryParameters: {'gid': _sinaCode(code, market), 'key': ApiConfig.juheStockKey});
      final list = resp.data?['result'] as List?;
      if (list == null || list.isEmpty) return null;
      final d = list[0]['datas'];
      if (d == null) return null;
      final price = _n(d['nowPri']) ?? 0.0;
      final preClose = _n(d['yestodEndPri']) ?? 0.0;
      if (price <= 0) return null;
      return Stock(
        code: code, name: d['name']?.toString() ?? code, market: market,
        price: price, change: price - preClose,
        changePercent: preClose > 0 ? (price - preClose) / preClose * 100 : 0.0,
        open: _n(d['todayStartPri']) ?? 0.0, high: _n(d['todayMax']) ?? 0.0,
        low: _n(d['todayMin']) ?? 0.0, preClose: preClose,
        volume: (_n(d['traNumber']) ?? 0.0) * 100, turnover: _n(d['traAmt']) ?? 0.0,
      );
    } catch (_) { return null; }
  }

  Future<Stock?> _quoteEM(String code, String market) async {
    try {
      final resp = await _dio.get(ApiConfig.emQuoteBase, queryParameters: {
        'fltt': 1, 'invt': 2, 'ut': ApiConfig.emUtToken,
        'fields': 'f43,f57,f58,f169,f170,f46,f44,f45,f47,f48,f116,f167,f168,f60,f162',
        'secid': _emSecid(code, market),
      }, options: Options(headers: {'Referer': 'https://quote.eastmoney.com/'}));
      final d = resp.data?['data'];
      if (d == null) return null;
      final price = _n(d['f43']) ?? 0.0;
      if (price <= 0) return null;
      final preClose = _n(d['f60']) ?? 0.0;
      return Stock(
        code: code, name: d['f58']?.toString() ?? '', market: market,
        price: price, change: price - preClose,
        changePercent: _n(d['f170']) ?? 0.0,
        open: _n(d['f46']) ?? 0.0, high: _n(d['f44']) ?? 0.0,
        low: _n(d['f45']) ?? 0.0, preClose: preClose,
        volume: _n(d['f47']) ?? 0.0, turnover: _n(d['f48']) ?? 0.0,
        pe: _n(d['f167']) ?? 0.0, pb: _n(d['f168']) ?? 0.0,
        marketCap: _n(d['f116']) ?? 0.0, turnoverRate: _n(d['f162']) ?? 0.0,
      );
    } catch (_) { return null; }
  }

  // ── 批量行情 ──────────────────────────────────────────────────────────────

  Future<Map<String, Stock>> fetchBatchQuotes(List<Watchlist> watchlist) async {
    if (watchlist.isEmpty) return {};
    final result = <String, Stock>{};
    final codes = watchlist.map((w) => _sinaCode(w.stockCode, w.market)).join(',');
    try {
      final resp = await _dio.get('https://sqt.gtimg.cn/q=$codes',
          options: Options(responseType: ResponseType.bytes, headers: {'Referer': 'https://gu.qq.com/'}));
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);
      final re = RegExp(r'v_(sh|sz|bj)(\d{6})="([^"]+)"', multiLine: true);
      for (final m in re.allMatches(body)) {
        final mktRaw = m.group(1)!.toUpperCase();
        final code = m.group(2)!;
        final p = m.group(3)!.split('~');
        if (p.length < 40 || p[1].isEmpty) continue;
        final price = double.tryParse(p[3]) ?? 0.0;
        if (price <= 0) continue;
        final preClose = double.tryParse(p[4]) ?? 0.0;
        final mkt = mktRaw == 'SH' ? 'SH' : mktRaw == 'BJ' ? 'BJ' : 'SZ';
        final marketCapYi = double.tryParse(p.length > 44 ? p[44] : '') ?? 0.0;
        result[code] = Stock(
          code: code, name: p[1], market: mkt,
          price: price, change: price - preClose,
          changePercent: preClose > 0 ? (price - preClose) / preClose * 100 : 0.0,
          open: double.tryParse(p[5]) ?? 0.0,
          high: double.tryParse(p.length > 33 ? p[33] : '') ?? 0.0,
          low: double.tryParse(p.length > 34 ? p[34] : '') ?? 0.0,
          preClose: preClose,
          volume: (double.tryParse(p[6]) ?? 0.0) * 100,
          turnover: double.tryParse(p.length > 37 ? p[37] : '') ?? 0.0,
          pe: double.tryParse(p.length > 39 ? p[39] : '') ?? 0.0,
          pb: double.tryParse(p.length > 46 ? p[46] : '') ?? 0.0,
          marketCap: marketCapYi > 0 ? marketCapYi * 1e8 : 0.0,
        );
      }
    } catch (e) { _log('批量行情[sqt]失败: $e'); }
    for (final w in watchlist) {
      if (result.containsKey(w.stockCode)) continue;
      final s = await _quoteSqt(w.stockCode, w.market);
      result[w.stockCode] = s ?? Stock(code: w.stockCode, name: w.stockName, market: w.market);
    }
    // 自选股名称已存在 DB（w.stockName），若行情源返回乱码则用 DB 名称覆盖
    for (final w in watchlist) {
      final s = result[w.stockCode];
      if (s != null && (s.name.isEmpty || _looksMojibake(s.name)) && w.stockName.isNotEmpty) {
        result[w.stockCode] = s.copyWith(name: w.stockName);
      }
    }
    return result;
  }

  // ── 历史K线 ───────────────────────────────────────────────────────────────

  /// 腾讯K线主源 → 新浪备用，不使用东方财富push域名
  Future<List<Map<String, dynamic>>> fetchKlineDaily(
      String code, String market, {int limit = 120}) async {
    final r = await _klineQQ(code, market, limit: limit);
    if (r.isNotEmpty) return r;
    return _klineSina(code, market, limit: limit);
  }

  Future<List<Map<String, dynamic>>> _klineQQ(
      String code, String market, {int limit = 120}) async {
    try {
      final resp = await _dio.get(
        ApiConfig.qqKlineBase,
        queryParameters: {
          'param': '${_sinaCode(code, market)},day,,,$limit,qfq',
          '_var': 'kline_dayqfq',
        },
        options: Options(responseType: ResponseType.bytes),
      );
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);
      final start = body.indexOf('{');
      if (start < 0) return [];
      final parsed = jsonDecode(body.substring(start)) as Map<String, dynamic>?;
      final qfqDay = parsed?['data']?[_sinaCode(code, market)]?['qfqday'] as List?;
      if (qfqDay == null) return [];
      return qfqDay.map<Map<String, dynamic>>((k) {
        if (k is! List || k.length < 6) return <String, dynamic>{};
        return {
          'date': k[0].toString(), 'open': _n(k[1]) ?? 0.0,
          'close': _n(k[2]) ?? 0.0, 'high': _n(k[3]) ?? 0.0,
          'low': _n(k[4]) ?? 0.0, 'volume': _n(k[5]) ?? 0.0,
          'change_percent': 0.0,
        };
      }).where((k) => k.isNotEmpty && (k['close'] as double) > 0).toList();
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> _klineSina(
      String code, String market, {int limit = 120}) async {
    try {
      final resp = await _dio.get(ApiConfig.sinaKlineBase, queryParameters: {
        'symbol': _sinaCode(code, market), 'scale': 240, 'ma': 'no', 'datalen': limit,
      });
      final raw = resp.data;
      final List<dynamic> items = raw is List
          ? raw
          : (raw is Map ? (raw['result']?['data'] as List? ?? []) : []);
      return items.map<Map<String, dynamic>>((k) {
        final close = _n(k['close']) ?? _n(k['c']) ?? 0.0;
        return {
          'date': k['date']?.toString() ?? k['d']?.toString() ?? '',
          'open': _n(k['open']) ?? _n(k['o']) ?? 0.0,
          'close': close,
          'high': _n(k['high']) ?? _n(k['h']) ?? 0.0,
          'low': _n(k['low']) ?? _n(k['l']) ?? 0.0,
          'volume': _n(k['volume']) ?? _n(k['v']) ?? 0.0,
          'change_percent': _n(k['p']) ?? 0.0,
        };
      }).where((k) => (k['close'] as double) > 0).toList();
    } catch (_) { return []; }
  }

  // ── 搜索 ──────────────────────────────────────────────────────────────────

  Future<List<Stock>> searchByName(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    return _searchEM(keyword);
  }

  Future<List<Stock>> searchStocks(String keyword) => searchByName(keyword);

  Future<List<Stock>> _searchEM(String keyword) async {
    try {
      final resp = await _dio.get(ApiConfig.emSuggestBase, queryParameters: {
        'input': keyword.trim(), 'type': '14',
        'token': 'D43BF722C8E33BDC906FB84D85E326E8',
        'count': 20, 'markettype': '', 'mktnum': '', 'jys': '',
        'classify': '', 'securitytype': '',
      }, options: Options(headers: {
        'Referer': 'https://www.eastmoney.com/',
        'Origin': 'https://www.eastmoney.com',
      }));
      final raw = resp.data;
      if (raw == null) return [];
      Map<String, dynamic> data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw as Map);
      } else {
        final str = raw.toString().trim();
        if (str.startsWith('<')) { _log('搜索[EM][$keyword] 返回HTML'); return []; }
        data = Map<String, dynamic>.from(jsonDecode(str) as Map);
      }
      final items = (data['QuotationCodeTable']?['Data'] as List?) ?? [];
      _log('搜索[EM][$keyword] ${items.length}条');
      return items.whereType<Map>().where((e) {
        final code = e['Code']?.toString() ?? '';
        if (code.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) return false;
        final type = e['SecurityType']?.toString() ?? '';
        final mktNum = e['MktNum']?.toString() ?? '';
        final classify = e['Classify']?.toString() ?? '';
        return type == '1' || type == '2' || type == '8' || type == '25' ||
            mktNum == '0' || mktNum == '1' ||
            classify == 'AShare' || classify == 'FundShare' || classify == 'ETFShare';
      }).map((e) {
        final code = e['Code']!.toString();
        final mktNum = e['MktNum']?.toString() ?? '';
        final type = e['SecurityType']?.toString() ?? '';
        final classify = e['Classify']?.toString() ?? '';
        final String market;
        if (mktNum == '2' || type == '77' || type == '78') {
          market = 'BJ';
        } else if (mktNum == '1' || type == '1') {
          market = 'SH';
        } else if (mktNum == '0' || type == '2') {
          market = 'SZ';
        } else {
          market = _inferMarket(code);
        }
        final bool isFund = type == '8' || type == '25' ||
            classify == 'FundShare' || classify == 'ETFShare' ||
            code.startsWith('15') || code.startsWith('16') ||
            code.startsWith('17') || code.startsWith('18') ||
            code.startsWith('51') || code.startsWith('56') ||
            code.startsWith('58') || code.startsWith('50');
        return Stock(code: code, name: e['Name']?.toString() ?? '', market: market, isFund: isFund);
      }).where((s) => s.code.isNotEmpty && s.name.isNotEmpty).toList();
    } catch (e) {
      _log('搜索[EM][$keyword] 异常: $e');
      return [];
    }
  }

  // ── 市场指数 ──────────────────────────────────────────────────────────────

  Future<List<MarketIndex>> fetchMarketIndices() async {
    const secids = ['1.000001', '0.399001', '0.399006', '1.000300', '1.000016'];
    const names = ['上证指数', '深证成指', '创业板指', '沪深300', '上证50'];
    try {
      final resp = await _dio.get(ApiConfig.emIndexBase, queryParameters: {
        'fltt': 2, 'invt': 2, 'ut': ApiConfig.emUtToken,
        'fields': 'f2,f3,f4,f12,f14', 'secids': secids.join(','),
      });
      final items = resp.data?['data']?['diff'] as List? ?? [];
      return List.generate(items.length, (i) {
        final item = items[i];
        return MarketIndex(
          code: item['f12']?.toString() ?? secids[i].split('.').last,
          name: names[i],
          price: (_n(item['f2']) ?? 0.0),
          change: (_n(item['f4']) ?? 0.0),
          changePercent: (_n(item['f3']) ?? 0.0),
        );
      });
    } catch (_) {
      return names.map((n) =>
          MarketIndex(code: '-', name: n, price: 0, change: 0, changePercent: 0)).toList();
    }
  }

  // ── 北向资金 ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchNorthboundFlow() async {
    try {
      final resp = await _dio.get(ApiConfig.emNorthboundBase, queryParameters: {
        'fields1': 'f1,f2,f3,f4', 'fields2': 'f51,f52,f53,f54,f55,f56',
        'ut': ApiConfig.emUtToken,
      });
      final d = resp.data?['data'];
      if (d == null) return {};
      return {
        'sh_net': (_n(d['f2']) ?? 0.0),
        'sz_net': (_n(d['f3']) ?? 0.0),
        'total_net': (_n(d['f4']) ?? 0.0),
      };
    } catch (_) { return {}; }
  }

  // ── 基金排雷数据 ──────────────────────────────────────────────────────────

  Future<AutoRiskData> _fetchFundRiskData(String code, String market) async {
    final notes = <String>[];
    double? divYield;
    int? divYears;
    String? divStability;

    try {
      final resp = await _dio.get(ApiConfig.emQuoteBase, queryParameters: {
        'fltt': 2, 'invt': 2, 'ut': ApiConfig.emUtToken,
        'fields': 'f43,f57,f58,f164,f173', 'secid': _emSecid(code, market),
      });
      final d = resp.data?['data'];
      if (d != null) {
        final divCount = (_n(d['f164']) ?? 0).toInt();
        final yield12m = _n(d['f173']);
        if (yield12m != null && yield12m > 0) { divYield = yield12m; notes.add('已读取基金近12月分红收益率'); }
        if (divCount > 0) {
          divYears = divCount.clamp(1, 30);
          divStability = divCount >= 5 ? 'stable' : divCount >= 2 ? 'normal' : null;
          notes.add('已读取基金分红次数（$divCount次）');
        }
      }
    } catch (e) { _log('基金行情[$code] 异常: $e'); }

    if (divYears == null || divYield == null) {
      try {
        final secuCode = '$code.${market == "SH" ? "SH" : "SZ"}';
        final rows = await _fetchFirstReport(
          reportNames: const ['RPT_FUND_BONUS', 'RPT_F10_FUND_DIVIDEND'],
          filters: ['(FUND_CODE="$code")', '(SECUCODE="$secuCode")'],
          sortColumns: 'EX_DIVIDEND_DATE,REPORT_DATE', pageSize: 20,
        );
        if (rows.isNotEmpty) {
          final years = <String>{};
          double totalYield = 0; int yieldCount = 0;
          for (final r in rows) {
            final cashDiv = _firstNum([r], const ['BONUS_AMOUNT', 'CASH_DIVIDEND', 'DIVIDEND_AMOUNT', 'PER_BONUS']);
            if (cashDiv != null && cashDiv > 0) {
              final date = (r['EX_DIVIDEND_DATE'] ?? r['REPORT_DATE'] ?? '').toString();
              if (date.length >= 4) years.add(date.substring(0, 4));
            }
            final y = _firstNum([r], const ['DIVIDEND_YIELD', 'BONUS_YIELD', 'ZXGXL']);
            if (y != null && y > 0) { totalYield += y; yieldCount++; }
          }
          if (years.isNotEmpty && divYears == null) {
            divYears = years.length;
            divStability = years.length >= 5 ? 'stable' : years.length >= 2 ? 'normal' : null;
            notes.add('已读取基金分红历史（${years.length}年）');
          }
          if (yieldCount > 0 && divYield == null) {
            divYield = totalYield / yieldCount;
            notes.add('已读取基金平均分红收益率');
          }
        }
      } catch (e) { _log('基金分红[$code] 异常: $e'); }
    }

    if (notes.isEmpty) notes.add('基金财务/分红数据未取到，请手动核查基金定期报告');
    return AutoRiskData(
      dividendYield: divYield, dividendYears: divYears,
      dividendStability: divStability, sourceNotes: notes, isFund: true,
    );
  }

  // ── 自动排雷（股票） ──────────────────────────────────────────────────────

  Future<AutoRiskData> fetchAutoRiskData(String code, String market) async {
    if (_isFundCode(code)) return _fetchFundRiskData(code, market);
    final secuCode = '$code.${market == "SH" ? "SH" : "SZ"}';
    final notes = <String>[];

    final results = await Future.wait<dynamic>([
      _sinaFinanceData(code, market),
      _fetchFirstReport(
        reportNames: const ['RPT_PLEDGE_RATIO', 'RPTA_WEB_EQUITYPLEDGE', 'RPT_F10_EH_EQUITYPLEDGE'],
        filters: ['(SECURITY_CODE="$code")', '(SECUCODE="$secuCode")'],
        sortColumns: 'TRADE_DATE,END_DATE,REPORT_DATE',
      ),
      _fetchFirstReport(
        reportNames: const ['RPT_F10_MAIN_TARGET', 'RPT_F10_FINANCE_MAINFINADATA'],
        filters: ['(SECUCODE="$secuCode")', '(SECURITY_CODE="$code")'],
        sortColumns: 'REPORT_DATE,NOTICE_DATE',
      ),
      _fetchFirstReport(
        reportNames: const ['RPT_SHAREBONUS_DET', 'RPT_F10_SHAREBONUS'],
        filters: ['(SECURITY_CODE="$code")', '(SECUCODE="$secuCode")'],
        sortColumns: 'REPORT_DATE,EX_DIVIDEND_DATE',
        pageSize: 20,
      ),
    ]);

    final sinaData    = results[0] as _SinaFinanceResult;
    final pledgeRows  = results[1] as List<Map<String, dynamic>>;
    final financeRows = results[2] as List<Map<String, dynamic>>;
    final divRows     = results[3] as List<Map<String, dynamic>>;

    final pledge = _firstNum(pledgeRows,
        const ['PLEDGE_RATIO', 'TOTAL_PLEDGE_RATIO', 'ZYBL', 'PLEDGE_RATIO_TOTAL']);
    if (pledge != null) notes.add('已自动读取质押率');

    final debtRatio = sinaData.debtRatio
        ?? _firstNum(financeRows, const ['DEBTASSETRATIO', 'ZCFZL', 'DEBT_ASSET_RATIO', 'ASSET_LIAB_RATIO']);
    if (debtRatio != null) notes.add('已自动读取负债率');

    final cashflowMargin = sinaData.cashflowMargin
        ?? _extractCashflow(financeRows.isNotEmpty ? financeRows.first : null);
    if (cashflowMargin != null) notes.add('已自动读取现金流利润比');

    final goodwillRatio = _extractGoodwill(financeRows.isNotEmpty ? financeRows.first : null);
    if (goodwillRatio != null) notes.add('已自动估算商誉占比');

    double? dividendYield = sinaData.dividendYield
        ?? _firstNum(divRows, const ['DIVIDEND_YIELD', 'ZXGXL', 'BONUS_YIELD', 'CASH_DIVIDEND_YIELD']);

    int totalDivYears = sinaData.dividendYears > 0
        ? sinaData.dividendYears
        : _countDivYears(divRows);

    if (ApiConfig.hasJuheKey && totalDivYears == 0) {
      final juheDiv = await _fetchDividendJuhe(code, market);
      if (juheDiv.isNotEmpty) { totalDivYears = juheDiv.length; notes.add('已通过聚合数据读取分红记录'); }
    }

    if (dividendYield != null || totalDivYears > 0) {
      notes.add('已自动读取分红记录${sinaData.dividendYears > 0 ? "（新浪F10）" : "（数据中心）"}');
    }

    return AutoRiskData(
      pledgeRatio: pledge, debtRatio: debtRatio,
      goodwillRatio: goodwillRatio, cashflowMargin: cashflowMargin,
      dividendYield: dividendYield,
      dividendYears: totalDivYears > 0 ? totalDivYears : null,
      dividendStability: totalDivYears >= 5 ? 'stable' : totalDivYears >= 2 ? 'normal' : null,
      sourceNotes: notes,
    );
  }

  // ── 新浪F10财务 ───────────────────────────────────────────────────────────

  Future<_SinaFinanceResult> _sinaFinanceData(String code, String market) async {
    double? debtRatio, cashflowMargin, dividendYield;
    int dividendYears = 0;

    // 说明：新浪 F10 页面是 GBK 编码，Dart 无 GBK 解码器，中文全是乱码，
    // 所以负债率/现金流等需要中文锚点的字段无法从新浪页面解析，
    // 这些字段改由东方财富 datacenter（UTF-8 JSON）提供。
    // 新浪页面仅用于提取「连续分红年数」——它只依赖 ASCII 日期，不受乱码影响。

    // ── 分红历史（仅提取 ASCII 日期，统计连续分红年数） ─────────────────────
    try {
      final resp = await _dio.get(
        'https://money.finance.sina.com.cn/corp/go.php/vISSUE_ShareBonus/stockid/$code.phtml',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': 'https://finance.sina.com.cn/'},
        ),
      );
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);

      // 每行格式：年份出现在 <td>2023-xx-xx</td>，同行某列有 >0 的派息金额
      final years = <String>{};
      final rowRe = RegExp(
        r'<tr[^>]*>(.*?)</tr>',
        dotAll: true,
      );
      for (final rowM in rowRe.allMatches(body)) {
        final row = rowM.group(1)!;
        // 找年份
        final yrM = RegExp(r'(\d{4})-\d{2}-\d{2}').firstMatch(row);
        if (yrM == null) continue;
        // 找 >0 的数字（排除全0行：0.00 分红方案为不分配）
        final hasDiv = RegExp(r'<td[^>]*?>\s*([1-9]\d*\.?\d*)\s*</td>').hasMatch(row);
        if (hasDiv) years.add(yrM.group(1)!);
      }
      dividendYears = years.length;
      _log('新浪F10分红[$code] 连续${dividendYears}年');
    } catch (e) {
      _log('新浪F10分红[$code] 异常: $e');
    }

    return _SinaFinanceResult(
      debtRatio: debtRatio,
      cashflowMargin: cashflowMargin,
      dividendYield: dividendYield,
      dividendYears: dividendYears,
    );
  }

  // ── datacenter 辅助 ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchDividendJuhe(String code, String market) async {
    try {
      final resp = await _dio.get(ApiConfig.juheDividendUrl, queryParameters: {
        'gid': _sinaCode(code, market), 'key': ApiConfig.juheStockKey,
        'page': 1, 'perpage': 20,
      });
      final list = resp.data?['result']?['data'] as List?;
      return list?.whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v))).toList() ?? [];
    } catch (_) { return []; }
  }

  Future<List<Map<String, dynamic>>> _fetchFirstReport({
    required List<String> reportNames,
    required List<String> filters,
    required String sortColumns,
    int pageSize = 5,
  }) async {
    for (final rn in reportNames) {
      for (final f in filters) {
        final rows = await _datacenterRows(
            reportName: rn, filter: f, sortColumns: sortColumns, pageSize: pageSize);
        if (rows.isNotEmpty) return rows;
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _datacenterRows({
    required String reportName,
    required String filter,
    required String sortColumns,
    int pageSize = 5,
  }) async {
    try {
      // responseType: plain 强制获取原始字符串，避免 Dio 自动 JSON 解析
      // 在某些 Android 环境下 Dio 会把 JSON List 解析成 LinkedHashMap<String,dynamic>
      // 导致后续 whereType<Map> 迭代时出现 'String is not subtype of int' 错误
      final resp = await _dio.get(
        ApiConfig.emDatacenterBase,
        queryParameters: {
          'sortColumns': sortColumns, 'sortTypes': '-1',
          'pageSize': pageSize, 'pageNumber': 1,
          'reportName': reportName, 'columns': 'ALL',
          'source': 'WEB', 'client': 'WEB', 'filter': filter,
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': 'https://data.eastmoney.com/',
            'Origin': 'https://www.eastmoney.com',
          },
        ),
      );
      final raw = resp.data?.toString() ?? '';
      if (raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final result = decoded['result'];
      if (result is! Map) return [];
      final data = result['data'];
      if (data is! List) {
        _log('datacenter[$reportName] 无数据, result keys=${(result as Map).keys.toList()}');
        return [];
      }
      return data
          .whereType<Map>()
          .map<Map<String, dynamic>>(
            (e) => Map<String, dynamic>.fromEntries(
              (e as Map).entries.map((en) => MapEntry(en.key.toString(), en.value)),
            ),
          )
          .toList();
    } catch (e) {
      _log('datacenter[$reportName] 异常: $e');
      return [];
    }
  }

  double? _firstNum(List<Map<String, dynamic>> rows, List<String> keys) {
    for (final row in rows) {
      for (final key in keys) {
        final v = _n(row[key]);
        if (v != null) return v;
      }
      for (final entry in row.entries) {
        if (keys.any((k) => entry.key.toUpperCase().contains(k))) {
          final v = _n(entry.value);
          if (v != null) return v;
        }
      }
    }
    return null;
  }

  double? _extractGoodwill(Map<String, dynamic>? row) {
    if (row == null) return null;
    final direct = _firstNum([row], const ['GOODWILL_RATIO', 'GOODWILL_ASSET_RATIO']);
    if (direct != null) return direct;
    final gw = _firstNum([row], const ['GOODWILL', 'GOODWILL_VALUE', 'SHANGYU']);
    final equity = _firstNum([row],
        const ['PARENTEQUITY', 'TOTAL_EQUITY', 'EQUITY', 'OWNERSHIPTOTAL']);
    if (gw != null && equity != null && equity > 0) return gw / equity * 100;
    final ta = _firstNum([row],
        const ['TOTALASSETS', 'TOTAL_ASSETS', 'TOTAL_ASSET', 'ASSETS_TOTAL']);
    if (gw == null || ta == null || ta <= 0) return null;
    return gw / ta * 100;
  }

  double? _extractCashflow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final direct = _firstNum([row], const [
      'JYXJLRTB', 'NETCASH_OPERATE_INCOME_RATIO', 'OPERATE_CASHFLOW_PROFIT_RATIO', 'XJLLBZ',
    ]);
    if (direct != null) return direct;
    final cf = _firstNum([row], const [
      'NETCASH_OPERATE', 'JYHDXJLLJE', 'NET_OPERATE_CASHFLOW', 'CASHFLOW_FROM_OPERATING',
    ]);
    final profit = _firstNum([row], const [
      'PARENTNETPROFIT', 'PARENT_NETPROFIT', 'NETPROFIT', 'NET_PROFIT', 'JLRGSHFJDGDLR',
    ]);
    if (cf == null || profit == null || profit == 0) return null;
    return cf / profit * 100;
  }

  int _countDivYears(List<Map<String, dynamic>> rows) {
    final years = <String>{};
    for (final row in rows) {
      final cash = _firstNum([row], const [
        'PRETAX_BONUS_RMB', 'PER_CASH_DIV', 'CASH_DIV_PRETAX',
        'CASH_DIVIDEND', 'CASH_BONUS', 'BONUS_AMOUNT',
      ]);
      if (cash == null || cash <= 0) continue;
      final rawDate = row['REPORT_DATE'] ?? row['EX_DIVIDEND_DATE'] ??
          row['NOTICE_DATE'] ?? row['PLAN_NOTICE_DATE'];
      final date = rawDate?.toString() ?? '';
      if (date.length >= 4) years.add(date.substring(0, 4));
    }
    return years.length;
  }

  // ── PE/PB 历史百分位 ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchValuation(String code, String market) async {
    final stock = await fetchStockQuote(code, market);
    if (stock == null) return {};
    return {'pe': stock.pe, 'pb': stock.pb, 'market_cap': stock.marketCap, 'price': stock.price};
  }

  Future<({int? pePercentile, int? pbPercentile})> fetchValuationPercentile(
      String code, String market) async {
    if (_isFundCode(code)) return (pePercentile: null, pbPercentile: null);

    // 主源：新浪F10历史PE
    try {
      final resp = await _dio.get(
        'https://money.finance.sina.com.cn/corp/go.php/vFD_PEHistory/symbol/${_sinaCode(code, market)}.phtml',
        options: Options(responseType: ResponseType.plain,
            headers: {'Referer': 'https://finance.sina.com.cn/'}),
      );
      final body = resp.data?.toString() ?? '';
      final jsonMatch = RegExp(r'\[[\s\S]+\]').firstMatch(body);
      if (jsonMatch != null) {
        final rawList = jsonDecode(jsonMatch.group(0)!) as List?;
        if (rawList != null && rawList.isNotEmpty) {
          final pes = rawList.whereType<Map>()
              .map((e) => _n(e['pe'] ?? e['PE'] ?? e['value']))
              .whereType<double>().where((v) => v > 0 && v < 1000).toList();
          if (pes.isNotEmpty) {
            final pePct = _percentileOf(pes, pes.last);
            _log('历史PE[新浪F10] $code PE百分位=$pePct (${pes.length}条)');
            return (pePercentile: pePct, pbPercentile: null);
          }
        }
      }
    } catch (e) { _log('历史PE[新浪F10] $code 异常: $e'); }

    // 降级：datacenter-web
    try {
      final secuCode = '$code.${market == "SH" ? "SH" : "SZ"}';
      final allRows = <Map<String, dynamic>>[];
      for (final rn in const ['RPT_F10_PEandPB', 'RPT_VALUATION_HISTORY']) {
        for (final f in ['(SECUCODE="$secuCode")', '(SECURITY_CODE="$code")']) {
          if (allRows.isNotEmpty) break;
          for (int page = 1; page <= 2; page++) {
            try {
              final resp = await _dio.get(
                ApiConfig.emDatacenterBase,
                queryParameters: {
                  'sortColumns': 'TRADE_DATE,REPORT_DATE', 'sortTypes': '-1',
                  'pageSize': 50, 'pageNumber': page,
                  'reportName': rn, 'columns': 'ALL',
                  'source': 'WEB', 'client': 'WEB', 'filter': f,
                },
                options: Options(
                  responseType: ResponseType.plain,
                  headers: {
                    'Referer': 'https://data.eastmoney.com/',
                    'Origin': 'https://www.eastmoney.com',
                  },
                ),
              );
              final raw = resp.data?.toString() ?? '';
              if (raw.isEmpty) continue;
              final decoded = jsonDecode(raw);
              if (decoded is! Map) continue;
              final result = decoded['result'];
              if (result is! Map) continue;
              final data = result['data'];
              if (data is! List || data.isEmpty) continue;
              allRows.addAll(data.whereType<Map>().map<Map<String, dynamic>>(
                (e) => Map<String, dynamic>.fromEntries(
                  (e as Map).entries.map((en) => MapEntry(en.key.toString(), en.value)),
                ),
              ));
            } catch (_) {}
          }
          if (allRows.isNotEmpty) break;
        }
        if (allRows.isNotEmpty) break;
      }
      if (allRows.isNotEmpty) {
        final pes = allRows.map((r) => _firstNum([r], const ['PE_TTM', 'PE', 'PELYR']))
            .whereType<double>().where((v) => v > 0 && v < 1000).toList();
        final pbs = allRows.map((r) => _firstNum([r], const ['PB', 'PB_MRQ']))
            .whereType<double>().where((v) => v > 0).toList();
        final pePct = _percentileOf(pes, pes.isNotEmpty ? pes.first : null);
        final pbPct = _percentileOf(pbs, pbs.isNotEmpty ? pbs.first : null);
        _log('历史估值[datacenter] $code PE百分位=$pePct PB百分位=$pbPct (${allRows.length}条)');
        return (pePercentile: pePct, pbPercentile: pbPct);
      }
    } catch (e) { _log('历史估值[datacenter] $code 异常: $e'); }

    return (pePercentile: null, pbPercentile: null);
  }

  // ── ATR 计算 ──────────────────────────────────────────────────────────────

  double? calculateATR(List<Map<String, dynamic>> klines, {int period = 14}) {
    if (klines.length < period + 1) return null;
    final recent = klines.sublist(klines.length - (period + 1));
    final trs = <double>[];
    for (int i = 1; i < recent.length; i++) {
      final high = _n(recent[i]['high']) ?? 0.0;
      final low = _n(recent[i]['low']) ?? 0.0;
      final prevClose = _n(recent[i - 1]['close']) ?? 0.0;
      if (high <= 0 || prevClose <= 0) continue;
      trs.add([high - low, (high - prevClose).abs(), (low - prevClose).abs()]
          .reduce((a, b) => a > b ? a : b));
    }
    if (trs.isEmpty) return null;
    return trs.reduce((a, b) => a + b) / trs.length;
  }

  int? _percentileOf(List<double> series, double? value) {
    if (series.isEmpty || value == null) return null;
    final sorted = List<double>.from(series)..sort();
    final below = sorted.where((v) => v < value).length;
    return ((below / sorted.length) * 100).round();
  }
}
