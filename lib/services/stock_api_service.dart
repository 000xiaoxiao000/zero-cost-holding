import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:gbk_codec/gbk_codec.dart';
import '../models/stock.dart';
import '../models/watchlist.dart';
import 'api_config.dart';

// ── 辅助数据类（顶层，供类内方法引用） ────────────────────────────────────────

class _SinaFinanceResult {
  final double? debtRatio;
  final double? cashflowMargin;
  final double? goodwillRatio;
  final double? pledgeRatio;
  final double? dividendYield;
  final int dividendYears;
  const _SinaFinanceResult({
    this.debtRatio,
    this.cashflowMargin,
    this.goodwillRatio,
    this.pledgeRatio,
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

  /// 东方财富数据中心 SECUCODE 后缀：沪 SH / 深 SZ / 北交所 BJ
  String _secuCode(String code, String market) => '$code.$market';

  String _inferMarket(String code) {
    // 北交所：老代码 43/83/87/88/8x、新代码 920 前缀（需在 '9' 判断之前）
    if (code.startsWith('92') || code.startsWith('8') ||
        code.startsWith('43') || code.startsWith('40')) return 'BJ';
    if (code.startsWith('6') || code.startsWith('5') || code.startsWith('9')) return 'SH';
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
    // 优先 UTF-8：部分接口已是 UTF-8，解码无替换符即采用
    try {
      final s = utf8.decode(bytes);
      if (!s.contains('\uFFFD')) return s;
    } catch (_) {}
    // 新浪财经 F10 等页面为 GBK/GB2312。
    // 注意：必须用 gbk_bytes.decode（含双字节合并逻辑），
    // gbk.decode 有 bug（逐单字节查表，双字节合并被注释掉），会解出乱码。
    try {
      return gbk_bytes.decode(bytes);
    } catch (_) {}
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
    var r = await _quoteAllSources(code, market);
    // 全部源失败：market 可能错（尤其北交所 920xxx 新代码常被误判为 SZ），
    // 依次尝试其余市场前缀自愈。
    if (r == null) {
      for (final m in const ['BJ', 'SH', 'SZ']) {
        if (m == market) continue;
        r = await _quoteAllSources(code, m);
        if (r != null) { _log('行情 $code 兜底市场 $m 命中（原 $market）'); break; }
      }
    }
    if (r == null) { _log('行情 $code 全部源失败'); return null; }
    // 名称为空或为 GBK 乱码时，用东方财富 suggest（UTF-8）补查
    if (r.name.isEmpty || _looksMojibake(r.name)) {
      final name = await fetchStockName(code);
      if (name.isNotEmpty) r = r.copyWith(name: name);
    }
    return r;
  }

  Future<Stock?> _quoteAllSources(String code, String market) async {
    Stock? r = await _quoteSqt(code, market);
    if (r != null) { _log('行情[sqt] $code($market) OK'); return r; }
    r = await _quoteSina(code, market);
    if (r != null) { _log('行情[新浪] $code($market) OK'); return r; }
    if (ApiConfig.hasJuheKey) {
      r = await _quoteJuhe(code, market);
      if (r != null) { _log('行情[聚合] $code($market) OK'); return r; }
    }
    r = await _quoteEM(code, market);
    if (r != null) { _log('行情[EM] $code($market) OK'); return r; }
    return null;
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
            type == '77' || type == '78' ||
            mktNum == '0' || mktNum == '1' || mktNum == '2' ||
            classify == 'AShare' || classify == 'FundShare' ||
            classify == 'ETFShare' || classify == 'BjShare';
      }).map((e) {
        final code = e['Code']!.toString();
        final mktNum = e['MktNum']?.toString() ?? '';
        final type = e['SecurityType']?.toString() ?? '';
        final classify = e['Classify']?.toString() ?? '';
        final String market;
        // 北交所优先：新代码 920/老代码 43/83/87/88 前缀，
        // 东方财富 suggest 对北交所常返回 MktNum=0（与深圳同组），
        // 故必须先按代码前缀判定，否则会被误判为 SZ。
        if (mktNum == '2' || type == '77' || type == '78' ||
            code.startsWith('92') || code.startsWith('43') ||
            code.startsWith('83') || code.startsWith('87') ||
            code.startsWith('88')) {
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
        final secuCode = _secuCode(code, market);
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

  Future<AutoRiskData> fetchAutoRiskData(String code, String market, {double? price}) async {
    if (_isFundCode(code)) return _fetchFundRiskData(code, market);
    final secuCode = _secuCode(code, market);
    final notes = <String>[];

    final results = await Future.wait<dynamic>([
      _sinaFinanceData(code, market, price: price),
      _fetchFirstReport(
        // 东方财富股权质押数据中心：detail 报表按 SCODE 过滤（非 SECURITY_CODE）
        reportNames: const [
          'RPT_CSDC_LIST', 'RPT_CUSTOM_STOCK_PLEDGE_STATISTICS',
          'RPT_STOCK_PLEDGE_STATISTICS', 'RPT_PLEDGE_RATIO',
          'RPTA_WEB_EQUITYPLEDGE', 'RPT_F10_EH_EQUITYPLEDGE',
        ],
        filters: [
          '(SCODE="$code")', '(SECURITY_CODE="$code")', '(SECUCODE="$secuCode")',
        ],
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

    double? pledge = _firstNum(pledgeRows, const [
      'PLEDGE_RATIO', 'TOTAL_PLEDGE_RATIO', 'ZYBL', 'PLEDGE_RATIO_TOTAL',
      'PLEDGE_NUM_RATIO', 'PLEDGERTATIO', 'TOTAL_SHARE_RATIO', 'ZYGSZB',
    ]);
    // datacenter 未命中时，走东方财富 F10 专用子域兜底
    if (pledge == null) {
      if (pledgeRows.isNotEmpty) {
        _log('质押率[$code] datacenter 未匹配字段，首行keys=${pledgeRows.first.keys.toList()}');
      } else {
        _log('质押率[$code] datacenter 无返回行，尝试 emweb F10');
      }
      pledge = await _fetchPledgeRatioEm(code, market);
    }
    if (pledge != null) notes.add('已自动读取质押率');

    final debtRatio = sinaData.debtRatio
        ?? _firstNum(financeRows, const ['DEBTASSETRATIO', 'ZCFZL', 'DEBT_ASSET_RATIO', 'ASSET_LIAB_RATIO']);
    if (debtRatio != null) notes.add('已自动读取负债率');

    final cashflowMargin = sinaData.cashflowMargin
        ?? _extractCashflow(financeRows.isNotEmpty ? financeRows.first : null);
    if (cashflowMargin != null) notes.add('已自动读取现金流利润比');

    final goodwillRatio = sinaData.goodwillRatio
        ?? _extractGoodwill(financeRows.isNotEmpty ? financeRows.first : null);
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

  /// 新浪 F10 页面是 GBK 编码，用 gbk_codec 正确解码为中文后以中文正则解析：
  ///   1. 分红页：ASCII 日期统计连续分红年数；列位置取「每10股派息」，
  ///      结合当前股价自算股息率。
  ///   2. 财务指标页：直接取预计算好的「资产负债率(%)」「经营现金净流量与
  ///      净利润的比率(%)」。
  ///   3. 资产负债表页：取「商誉」「所有者权益合计」算商誉占净资产比例。
  Future<_SinaFinanceResult> _sinaFinanceData(
      String code, String market, {double? price}) async {
    double? debtRatio, cashflowMargin, dividendYield;
    int dividendYears = 0;

    // 股息率自算需要股价；调用方未传时自行拉取一次实时行情
    double? px = price;
    if (px == null || px <= 0) {
      try {
        final q = await _quoteSqt(code, market);
        px = q?.price;
      } catch (_) {}
    }

    // ── 分红历史：连续分红年数 + 每股派息 → 自算股息率 ──────────────────────
    try {
      final resp = await _dio.get(
        'https://money.finance.sina.com.cn/corp/go.php/vISSUE_ShareBonus/stockid/$code.phtml',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': 'https://finance.sina.com.cn/'},
        ),
      );
      final body = _decodeGbkBytes(resp.data as List<int>? ?? []);

      // 新浪分红表列顺序：公告日期 | 分红年度 | 送股 | 转增 | 派息(每10股,元) | ...
      // 含短横线的日期 td 不会匹配纯数字正则，故行内「纯数字 td」按序为：
      //   [0]=送股  [1]=转增  [2]=派息(每10股,税前,元)
      final years = <String>{};
      double? latestPerShareDiv;
      String? latestYear;
      final rowRe = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
      for (final rowM in rowRe.allMatches(body)) {
        final row = rowM.group(1)!;
        final yrM = RegExp(r'(\d{4})-\d{2}-\d{2}').firstMatch(row);
        if (yrM == null) continue;
        final nums = RegExp(r'<td[^>]*?>\s*([\d]+\.?\d*)\s*</td>')
            .allMatches(row)
            .map((m) => double.tryParse(m.group(1)!) ?? 0.0)
            .toList();
        if (nums.isEmpty) continue;
        // 派息为第 3 个纯数字列（index 2）；不足 3 列时取最后一个非零值兜底
        final double cashPer10 = nums.length >= 3
            ? nums[2]
            : (nums.where((v) => v > 0).isEmpty ? 0.0 : nums.lastWhere((v) => v > 0));
        final year = yrM.group(1)!;
        // 仅当该年确有现金派息才计入连续分红年数
        if (cashPer10 > 0) years.add(year);
        // 最近一条（页面时间倒序）且有派息的记录用于自算股息率
        if (latestYear == null && cashPer10 > 0) {
          latestYear = year;
          latestPerShareDiv = cashPer10 / 10.0;
        }
      }
      dividendYears = years.length;

      if (latestPerShareDiv != null && latestPerShareDiv > 0 &&
          px != null && px > 0) {
        dividendYield = latestPerShareDiv / px * 100;
      }
      _log('新浪F10分红[$code] 连续${dividendYears}年 每股派息=$latestPerShareDiv 股息率=$dividendYield');
    } catch (e) {
      _log('新浪F10分红[$code] 异常: $e');
    }

    // ── 财务指标：优先财务指标页取预计算比率；失败则从报表自算 ─────────────
    double? goodwillRatio;
    try {
      final resp = await _dio.get(
        'https://money.finance.sina.com.cn/corp/go.php/vFD_FinancialGuideLine/stockid/$code/ctrl/all/displaytype/4.phtml',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': 'https://finance.sina.com.cn/'},
        ),
      );
      final html = _decodeGbkBytes(resp.data as List<int>? ?? []);
      debtRatio = _firstRatioAfterLabel(html, '资产负债率', min: 0, max: 100);
      cashflowMargin = _firstRatioAfterLabel(
        html, '经营现金净流量与净利润的比率',
        min: -100000, max: 100000, allowNegative: true,
      ) ?? _firstRatioAfterLabel(
        html, '经营现金净流量对净利润的比率',
        min: -100000, max: 100000, allowNegative: true,
      );
      _log('新浪F10财务指标[$code] 负债率=$debtRatio 现金流比=$cashflowMargin');
    } catch (e) {
      _log('新浪F10财务指标[$code] 异常: $e');
    }

    // ── 资产负债表：商誉/净资产 + 负债率兜底自算 ───────────────────────────
    try {
      final resp = await _dio.get(
        'https://money.finance.sina.com.cn/corp/go.php/vFD_BalanceSheet/stockid/$code/ctrl/part/displaytype/4.phtml',
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Referer': 'https://finance.sina.com.cn/'},
        ),
      );
      final html = _decodeGbkBytes(resp.data as List<int>? ?? []);
      // 商誉（精确匹配，排除「商誉减值」）
      final goodwill = _firstAmountAfterLabel(html, '商誉', excludeSuffix: ['减值']);
      // 所有者权益(或股东权益)合计
      final equity = _firstAmountAfterLabel(html, '所有者权益（或股东权益）合计')
          ?? _firstAmountAfterLabel(html, '所有者权益合计')
          ?? _firstAmountAfterLabel(html, '股东权益合计');
      if (goodwill != null && equity != null && equity > 0 && goodwill < equity) {
        goodwillRatio = goodwill / equity * 100;
      }
      // 负债率兜底：负债合计 / 资产总计 * 100（词边界避免命中「流动负债合计」）
      if (debtRatio == null) {
        final totalLiab = _firstAmountAfterLabel(html, '负债合计', wordBoundary: true);
        final totalAsset = _firstAmountAfterLabel(html, '资产总计', wordBoundary: true);
        if (totalLiab != null && totalAsset != null && totalAsset > 0) {
          debtRatio = totalLiab / totalAsset * 100;
        }
      }
      _log('新浪F10资产负债[$code] 商誉=$goodwill 净资产=$equity 占比=$goodwillRatio 负债率=$debtRatio');
    } catch (e) {
      _log('新浪F10资产负债[$code] 异常: $e');
    }

    // ── 现金流比兜底：经营现金流净额 / 净利润 * 100 ────────────────────────
    if (cashflowMargin == null) {
      try {
        final resp = await _dio.get(
          'https://money.finance.sina.com.cn/corp/go.php/vFD_CashFlow/stockid/$code/ctrl/part/displaytype/4.phtml',
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Referer': 'https://finance.sina.com.cn/'},
          ),
        );
        final html = _decodeGbkBytes(resp.data as List<int>? ?? []);
        final opCash = _firstAmountAfterLabel(html, '经营活动产生的现金流量净额');
        final netProfit = _firstAmountAfterLabel(html, '净利润', wordBoundary: true);
        if (opCash != null && netProfit != null && netProfit != 0) {
          cashflowMargin = opCash / netProfit * 100;
        }
        _log('新浪F10现金流[$code] 经营现金=$opCash 净利润=$netProfit 现金流比=$cashflowMargin');
      } catch (e) {
        _log('新浪F10现金流[$code] 异常: $e');
      }
    }

    return _SinaFinanceResult(
      debtRatio: debtRatio,
      cashflowMargin: cashflowMargin,
      goodwillRatio: goodwillRatio,
      dividendYield: dividendYield,
      dividendYears: dividendYears,
    );
  }

  /// 在已解码 HTML 中定位「指标名(可含%)」后紧跟的第一个百分比数值。
  double? _firstRatioAfterLabel(String html, String label,
      {double min = 0, double max = 100, bool allowNegative = false}) {
    final idx = html.indexOf(label);
    if (idx < 0) return null;
    // 从标签之后截取一段窗口，提取第一个数字（可带负号/小数）
    final window = html.substring(idx + label.length,
        (idx + label.length + 400).clamp(0, html.length));
    final numRe = allowNegative
        ? RegExp(r'(-?\d+\.?\d*)')
        : RegExp(r'(\d+\.?\d*)');
    for (final m in numRe.allMatches(window)) {
      final v = double.tryParse(m.group(1)!);
      if (v == null) continue;
      // 跳过年份样整数
      if (!m.group(1)!.contains('.') && v >= 1990 && v <= 2100) continue;
      if (v >= min && v <= max && v != 0) return v;
    }
    return null;
  }

  /// 在已解码 HTML 中定位「指标名」后紧跟的第一个金额（元，可为大数）。
  /// [excludeSuffix] 若标签后紧跟这些字符则跳过（避免误命中派生科目）。
  /// [wordBoundary] 要求标签前一个字符不是中文（避免「负债合计」误命中
  /// 「流动负债合计」「非流动负债合计」等前缀复合词）。
  double? _firstAmountAfterLabel(String html, String label,
      {List<String> excludeSuffix = const [], bool wordBoundary = false}) {
    int from = 0;
    final cjk = RegExp(r'[\u4e00-\u9fff]');
    while (true) {
      final idx = html.indexOf(label, from);
      if (idx < 0) return null;
      from = idx + label.length;
      // 词边界：标签前一字符若为中文，说明是复合词的一部分，跳过
      if (wordBoundary && idx > 0 && cjk.hasMatch(html[idx - 1])) continue;
      // 检查排除后缀
      final after = html.substring(from, (from + 6).clamp(0, html.length));
      if (excludeSuffix.any((s) => after.startsWith(s))) continue;
      final window = html.substring(from, (from + 400).clamp(0, html.length));
      final m = RegExp(r'(-?\d[\d,]*\.?\d*)').firstMatch(window);
      if (m != null) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null && v.abs() > 0) return v;
      }
    }
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

  /// 大股东质押率：东方财富 F10 股权质押接口（emweb 子域），返回 UTF-8 JSON。
  /// 关键：PageAjax 接口必须带 `X-Requested-With: XMLHttpRequest` 头，
  /// 否则东方财富会返回整张 HTML 页面而非 JSON。
  /// 返回值语义：
  ///   - >=0：命中质押数据（含明确的 0% 无质押）
  ///   - null：所有源均不可达或未返回可识别的质押数据，无法判断（显示「—」）
  Future<double?> _fetchPledgeRatioEm(String code, String market) async {
    final secid = '$market$code';
    // 优先尝试 datacenter 的股权质押专用报表（个股维度，返回 JSON）
    final dc = await _fetchPledgeFromGpzy(code);
    if (dc != null) return dc;

    for (final url in [
      'https://emweb.securities.eastmoney.com/PC_HSF10/EquityPledge/PageAjax?code=$secid',
      'https://emweb.eastmoney.com/PC_HSF10/EquityPledge/PageAjax?code=$secid',
    ]) {
      try {
        final resp = await _dio.get(
          url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://emweb.securities.eastmoney.com/pc_hsf10/pages/index.html?type=web&code=$secid',
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': 'application/json, text/javascript, */*; q=0.01',
            },
          ),
        );
        final raw = resp.data?.toString() ?? '';
        if (raw.isEmpty) { _log('质押率[$code] emweb 空响应'); continue; }
        final trimmed = raw.trimLeft();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          final decoded = jsonDecode(raw);
          final r = _extractPledgeFromEmF10(decoded);
          if (r != null) { _log('质押率[$code] emweb F10 JSON 命中=$r%'); return r; }
          _log('质押率[$code] emweb JSON 未定位字段，keys=${decoded is Map ? decoded.keys.toList() : "list"}');
        } else {
          // 返回的是 HTML：从中提取「质押」附近的百分比，或内嵌 JSON 数据
          final r = _pledgeFromHtml(raw);
          if (r != null) { _log('质押率[$code] emweb HTML 提取=$r%'); return r; }
          _log('质押率[$code] emweb HTML 未定位质押值(前200)=${raw.substring(0, raw.length.clamp(0, 200))}');
        }
      } catch (e) {
        _log('质押率[$code] emweb 异常: $e');
      }
    }
    return null;
  }

  /// 东方财富数据中心「股权质押·个股质押比例」接口（RPT_CSDC_LIST 等），返回 JSON。
  Future<double?> _fetchPledgeFromGpzy(String code) async {
    for (final rn in const [
      'RPT_CSDC_LIST',
      'RPT_CUSTOM_STOCK_PLEDGE_STATISTICS',
      'RPT_STOCK_PLEDGE_STATISTICS',
    ]) {
      try {
        final resp = await _dio.get(
          ApiConfig.emDatacenterBase,
          queryParameters: {
            'sortColumns': 'TRADE_DATE', 'sortTypes': '-1',
            'pageSize': 1, 'pageNumber': 1,
            'reportName': rn, 'columns': 'ALL',
            'source': 'WEB', 'client': 'WEB',
            'filter': '(SECURITY_CODE="$code")',
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Referer': 'https://data.eastmoney.com/gpzy/',
              'Origin': 'https://data.eastmoney.com',
            },
          ),
        );
        final raw = resp.data?.toString() ?? '';
        if (raw.isEmpty || !raw.trimLeft().startsWith('{')) continue;
        final decoded = jsonDecode(raw);
        final data = (decoded is Map ? decoded['result'] : null);
        final rows = (data is Map ? data['data'] : null);
        if (rows is! List || rows.isEmpty) continue;
        final v = _findPledgeRatio(rows.first);
        if (v != null) { _log('质押率[$code] gpzy[$rn] 命中=$v%'); return v; }
      } catch (e) {
        _log('质押率[$code] gpzy[$rn] 异常: $e');
      }
    }
    return null;
  }

  /// 从 HTML 文本中提取质押比例：优先匹配「质押…百分比」，其次内嵌 JSON。
  double? _pledgeFromHtml(String html) {
    // 内嵌 JSON 字段
    for (final key in const ['zgpl', 'zybl', 'zzgszszb', 'pledge_ratio']) {
      final m = RegExp('"$key"\\s*:\\s*"?(-?\\d+\\.?\\d*)', caseSensitive: false)
          .firstMatch(html);
      if (m != null) {
        final v = double.tryParse(m.group(1)!);
        if (v != null && v > 0 && v <= 100) return v;
      }
    }
    // 文本形式：「(整体/累计)质押比例 12.34%」「质押股份占总股本 12.34%」
    for (final pat in [
      RegExp(r'质押比例[^\d%]{0,10}(\d+\.?\d*)\s*%'),
      RegExp(r'质押股份?占总股本[^\d%]{0,10}(\d+\.?\d*)\s*%'),
      RegExp(r'占总股本比?例?[^\d%]{0,10}(\d+\.?\d*)\s*%'),
    ]) {
      final m = pat.firstMatch(html);
      if (m != null) {
        final v = double.tryParse(m.group(1)!);
        if (v != null && v > 0 && v <= 100) return v;
      }
    }
    return null;
  }

  /// 从东方财富 F10 EquityPledge 接口 JSON 中提取最新一期质押比例。
  /// 接口质押比例常见字段：zgpl（占总股本比例）、zybl（质押比例）。
  double? _extractPledgeFromEmF10(dynamic decoded) {
    return _findPledgeRatio(decoded);
  }

  /// 在 emweb 返回的嵌套 JSON 中递归查找「质押比例」类字段（0~100 的百分比）。
  /// ZGPL=占总股本比例、ZYBL=质押比例、ZZGSZSZB=占总股本市值比。
  double? _findPledgeRatio(dynamic node) {
    const keyHints = [
      'ZGPL', 'ZYBL', 'ZZGSZSZB', 'PLEDGE_RATIO', 'ZYGSZB', 'ZYBLTOTAL',
      'ZLZGBBL', 'PLEDGENUMRATIO',
    ];
    if (node is Map) {
      // 先在本层按 key 命中
      for (final entry in node.entries) {
        final k = entry.key.toString().toUpperCase();
        if (keyHints.any((h) => k.contains(h))) {
          final v = _n(entry.value);
          if (v != null && v > 0 && v <= 100) return v;
        }
      }
      // 再递归子节点（列表型数据通常首元素为最新一期）
      for (final v in node.values) {
        final r = _findPledgeRatio(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final e in node) {
        final r = _findPledgeRatio(e);
        if (r != null) return r;
      }
    }
    return null;
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
      final secuCode = _secuCode(code, market);
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
