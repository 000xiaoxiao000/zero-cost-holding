import 'dart:convert';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import '../models/stock.dart';
import '../models/watchlist.dart';
import 'api_config.dart';

/// A股行情数据服务
///
/// 数据源优先级（行情/K线）：
///   1. 新浪财经（15分钟延迟行情，免费，合规）
///   2. 腾讯财经（备用）
///   3. 东方财富（第三备用）
///   4. 聚合数据 JuHe（需 key，准实时，--dart-define=JUHE_STOCK_KEY=xxx）
///
/// 搜索、指数、财务/质押/分红数据使用东方财富公开接口。
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

  /// sh600519 / sz000001
  String _sinaCode(String code, String market) =>
      '${market.toLowerCase()}$code';

  /// 东方财富 secid 格式：1.600519 / 0.000001
  String _emSecid(String code, String market) =>
      '${market == "SH" ? 1 : 0}.$code';

  double? _n(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll('%', '').replaceAll(',', '').trim();
    if (s.isEmpty || s == '-' || s == '--') return null;
    return double.tryParse(s);
  }

  void _log(String msg) => dev.log(msg, name: 'StockApiService');

  // ══════════════════════════════════════════════════════════════════════════
  // 实时/延迟行情
  // ══════════════════════════════════════════════════════════════════════════

  /// 获取单只股票行情，三路降级：新浪 → 腾讯 → 东方财富 → 聚合数据（需key）
  Future<Stock?> fetchStockQuote(String code, String market) async {
    Stock? r;

    r = await _quoteSina(code, market);
    if (r != null) { _log('行情[新浪] $code OK'); return r; }

    r = await _quoteQQ(code, market);
    if (r != null) { _log('行情[腾讯] $code OK'); return r; }

    r = await _quoteEM(code, market);
    if (r != null) { _log('行情[东方财富] $code OK'); return r; }

    if (ApiConfig.hasJuheKey) {
      r = await _quoteJuhe(code, market);
      if (r != null) { _log('行情[聚合] $code OK'); return r; }
    }

    _log('行情 $code 全部源失败');
    return null;
  }

  /// 新浪财经行情（15分钟延迟，免费）
  /// 格式：var hq_str_sh600519="名称,今开,昨收,现价,最高,最低,,,,成交量(手),成交额,..."
  Future<Stock?> _quoteSina(String code, String market) async {
    try {
      final resp = await _dio.get(
        '${ApiConfig.sinaQuoteBase}/list=${_sinaCode(code, market)}',
        options: Options(responseType: ResponseType.plain),
      );
      final body = resp.data?.toString() ?? '';
      final match = RegExp(r'"([^"]+)"').firstMatch(body);
      if (match == null) return null;
      final p = match.group(1)!.split(',');
      if (p.length < 10 || p[0].isEmpty) return null;
      final price = double.tryParse(p[3]) ?? 0.0;
      final preClose = double.tryParse(p[2]) ?? 0.0;
      if (price <= 0) return null;
      final change = price - preClose;
      return Stock(
        code: code,
        name: p[0],
        market: market,
        price: price,
        change: change,
        changePercent: preClose > 0 ? change / preClose * 100 : 0.0,
        open: double.tryParse(p[1]) ?? 0.0,
        high: double.tryParse(p[4]) ?? 0.0,
        low: double.tryParse(p[5]) ?? 0.0,
        preClose: preClose,
        volume: (double.tryParse(p[8]) ?? 0.0) * 100,
        turnover: double.tryParse(p[9]) ?? 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 腾讯财经行情（备用）
  /// 格式：v_sh600519="1~名称~600519~现价~昨收~今开~成交量..."
  Future<Stock?> _quoteQQ(String code, String market) async {
    try {
      final resp = await _dio.get(
        '${ApiConfig.qqQuoteBase}/q=${_sinaCode(code, market)}',
        options: Options(responseType: ResponseType.plain),
      );
      final body = resp.data?.toString() ?? '';
      final match = RegExp(r'"([^"]+)"').firstMatch(body);
      if (match == null) return null;
      final p = match.group(1)!.split('~');
      if (p.length < 40 || p[1].isEmpty) return null;
      final price = double.tryParse(p[3]) ?? 0.0;
      final preClose = double.tryParse(p[4]) ?? 0.0;
      if (price <= 0) return null;
      final change = price - preClose;
      return Stock(
        code: code,
        name: p[1],
        market: market,
        price: price,
        change: change,
        changePercent: preClose > 0 ? change / preClose * 100 : 0.0,
        open: double.tryParse(p[5]) ?? 0.0,
        high: double.tryParse(p[33]) ?? 0.0,
        low: double.tryParse(p[34]) ?? 0.0,
        preClose: preClose,
        volume: (double.tryParse(p[6]) ?? 0.0) * 100,
        turnover: double.tryParse(p[37]) ?? 0.0,
        pe: double.tryParse(p[39]) ?? 0.0,
        pb: double.tryParse(p[46]) ?? 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 聚合数据行情（需 key，准实时）
  Future<Stock?> _quoteJuhe(String code, String market) async {
    try {
      final resp = await _dio.get(
        ApiConfig.juheQuoteUrl,
        queryParameters: {
          'gid': _sinaCode(code, market),
          'key': ApiConfig.juheStockKey,
        },
      );
      final list = resp.data?['result'] as List?;
      if (list == null || list.isEmpty) return null;
      final d = list[0]['datas'];
      if (d == null) return null;
      final price = _n(d['nowPri']) ?? 0.0;
      final preClose = _n(d['yestodEndPri']) ?? 0.0;
      if (price <= 0) return null;
      final change = price - preClose;
      return Stock(
        code: code,
        name: d['name']?.toString() ?? code,
        market: market,
        price: price,
        change: change,
        changePercent: preClose > 0 ? change / preClose * 100 : 0.0,
        open: _n(d['todayStartPri']) ?? 0.0,
        high: _n(d['todayMax']) ?? 0.0,
        low: _n(d['todayMin']) ?? 0.0,
        preClose: preClose,
        volume: (_n(d['traNumber']) ?? 0.0) * 100,
        turnover: _n(d['traAmt']) ?? 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// 东方财富行情（第三备用，与搜索同域名，成功率较高）
  Future<Stock?> _quoteEM(String code, String market) async {
    try {
      final resp = await _dio.get(
        ApiConfig.emQuoteBase,
        queryParameters: {
          'fltt': 2,
          'invt': 2,
          'ut': ApiConfig.emUtToken,
          'fields': 'f43,f57,f58,f169,f170,f46,f44,f45,f47,f48,f116,f167,f168,f60',
          'secid': _emSecid(code, market),
        },
      );
      final d = resp.data?['data'];
      if (d == null) return null;
      final price = (_n(d['f43']) ?? 0.0);
      if (price <= 0) return null;
      final preClose = (_n(d['f60']) ?? 0.0);
      final change = price - preClose;
      return Stock(
        code: code,
        name: d['f58']?.toString() ?? '',
        market: market,
        price: price,
        change: change,
        changePercent: (_n(d['f170']) ?? 0.0),
        open: (_n(d['f46']) ?? 0.0),
        high: (_n(d['f44']) ?? 0.0),
        low: (_n(d['f45']) ?? 0.0),
        preClose: preClose,
        volume: (_n(d['f47']) ?? 0.0),
        turnover: (_n(d['f48']) ?? 0.0),
        pe: (_n(d['f167']) ?? 0.0),
        pb: (_n(d['f168']) ?? 0.0),
        marketCap: (_n(d['f116']) ?? 0.0),
      );
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 批量行情（自选股列表）
  // ══════════════════════════════════════════════════════════════════════════

  /// 批量拉取自选股行情，主源新浪（逗号分隔），取不到的逐只降级腾讯财经。
  Future<Map<String, Stock>> fetchBatchQuotes(List<Watchlist> watchlist) async {
    if (watchlist.isEmpty) return {};
    final result = <String, Stock>{};
    final codes =
        watchlist.map((w) => _sinaCode(w.stockCode, w.market)).join(',');
    try {
      final resp = await _dio.get(
        '${ApiConfig.sinaQuoteBase}/list=$codes',
        options: Options(responseType: ResponseType.plain),
      );
      final body = resp.data?.toString() ?? '';
      final re =
          RegExp(r'hq_str_(s[hz])(\d+)="([^"]*)"', multiLine: true);
      for (final m in re.allMatches(body)) {
        final mkt = m.group(1)!.toUpperCase();
        final code = m.group(2)!;
        final p = m.group(3)!.split(',');
        if (p.length < 10 || p[0].isEmpty) continue;
        final price = double.tryParse(p[3]) ?? 0.0;
        if (price <= 0) continue;
        final preClose = double.tryParse(p[2]) ?? 0.0;
        final change = price - preClose;
        result[code] = Stock(
          code: code,
          name: p[0],
          market: mkt,
          price: price,
          change: change,
          changePercent: preClose > 0 ? change / preClose * 100 : 0.0,
          open: double.tryParse(p[1]) ?? 0.0,
          high: double.tryParse(p[4]) ?? 0.0,
          low: double.tryParse(p[5]) ?? 0.0,
          preClose: preClose,
          volume: (double.tryParse(p[8]) ?? 0.0) * 100,
          turnover: double.tryParse(p[9]) ?? 0.0,
        );
      }
    } catch (e) {
      _log('批量行情[新浪]失败: $e');
    }
    // 对新浪未取到的，依次降级腾讯财经、东方财富
    for (final w in watchlist) {
      if (result.containsKey(w.stockCode)) continue;
      Stock? s = await _quoteQQ(w.stockCode, w.market);
      s ??= await _quoteEM(w.stockCode, w.market);
      if (s != null) result[w.stockCode] = s;
    }
    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 历史 K 线（日线，前复权）
  // ══════════════════════════════════════════════════════════════════════════

  /// 获取日K数据，主源新浪，降级腾讯财经。
  Future<List<Map<String, dynamic>>> fetchKlineDaily(
    String code,
    String market, {
    int limit = 120,
  }) async {
    final r = await _klineSina(code, market, limit: limit);
    if (r.isNotEmpty) return r;
    return _klineQQ(code, market, limit: limit);
  }

  /// 新浪历史日K（前复权）
  /// 接口同时可能返回 {d,o,c,h,l,v} 或 {date,open,close,high,low,volume}
  Future<List<Map<String, dynamic>>> _klineSina(
    String code,
    String market, {
    int limit = 120,
  }) async {
    try {
      final resp = await _dio.get(
        ApiConfig.sinaKlineBase,
        queryParameters: {
          'symbol': _sinaCode(code, market),
          'scale': 240,
          'ma': 'no',
          'datalen': limit,
        },
      );
      final raw = resp.data;
      final List<dynamic> items = raw is List
          ? raw
          : (raw is Map ? (raw['result']?['data'] as List? ?? []) : []);
      return items.map<Map<String, dynamic>>((k) {
        // 兼容两种字段名：短名 d/o/c/h/l/v 和长名 date/open/close/high/low/volume
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
    } catch (_) {
      return [];
    }
  }

  /// 腾讯财经历史日K（前复权，备用）
  Future<List<Map<String, dynamic>>> _klineQQ(
    String code,
    String market, {
    int limit = 120,
  }) async {
    try {
      final resp = await _dio.get(
        ApiConfig.qqKlineBase,
        queryParameters: {
          'param': '${_sinaCode(code, market)},day,,,$limit,qfq',
          '_var': 'kline_dayqfq',
        },
        options: Options(responseType: ResponseType.plain),
      );
      final body = resp.data?.toString() ?? '';
      final start = body.indexOf('{');
      if (start < 0) return [];
      final parsed =
          jsonDecode(body.substring(start)) as Map<String, dynamic>?;
      final qfqDay =
          parsed?['data']?[_sinaCode(code, market)]?['qfqday'] as List?;
      if (qfqDay == null) return [];
      return qfqDay.map<Map<String, dynamic>>((k) {
        if (k is! List || k.length < 6) return <String, dynamic>{};
        return {
          'date': k[0].toString(),
          'open': _n(k[1]) ?? 0.0,
          'close': _n(k[2]) ?? 0.0,
          'high': _n(k[3]) ?? 0.0,
          'low': _n(k[4]) ?? 0.0,
          'volume': _n(k[5]) ?? 0.0,
          'change_percent': 0.0,
        };
      }).where((k) => k.isNotEmpty && (k['close'] as double) > 0).toList();
    } catch (_) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 股票搜索（东方财富 suggest，无需 token）
  // ══════════════════════════════════════════════════════════════════════════

  /// 通过名称、代码或拼音首字母搜索 A 股
  /// 主源：东方财富 suggest（覆盖 Referer 为 eastmoney.com）
  /// 备用：新浪财经 suggest（无 Referer 限制）
  /// 通过名称、代码或拼音首字母搜索 A 股
  /// 主源：腾讯财经 smartbox（UTF-8 JSON，无 Referer 限制）
  /// 备用：东方财富 suggest（带正确 Referer）
  Future<List<Stock>> searchByName(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    List<Stock> result = await _searchQQ(keyword);
    if (result.isEmpty) {
      _log('搜索[$keyword] 腾讯无结果，降级东方财富');
      result = await _searchEM(keyword);
    }
    return result;
  }

  /// 腾讯财经 smartbox 搜索（主源）
  /// 返回 UTF-8 JSON，支持代码/名称/拼音，无 Referer 限制
  Future<List<Stock>> _searchQQ(String keyword) async {
    try {
      final resp = await _dio.get(
        'https://smartbox.gtimg.cn/s3/',
        queryParameters: {
          'v': '2',
          'ttype': '1',  // 1=股票
          'query': keyword.trim(),
        },
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Referer': 'https://gu.qq.com/'},
        ),
      );
      final body = resp.data?.toString() ?? '';
      // 格式: v_hint="sz300339^0^300339^润和软件^stock^..."
      // 多条结果以 "~" 分隔，每条字段以 "^" 分隔
      // 字段: 市场前缀代码 ^ 0 ^ 代码 ^ 名称 ^ 类型 ...
      final match = RegExp(r'v_hint="([^"]*)"').firstMatch(body);
      if (match == null || match.group(1)!.isEmpty) return [];

      final entries = match.group(1)!.split('~');
      final results = <Stock>[];
      for (final entry in entries) {
        final parts = entry.split('^');
        if (parts.length < 4) continue;
        final fullCode = parts[0].trim();  // 如 sz300339 / sh600519
        final code = parts[2].trim();
        final name = parts[3].trim();
        if (!RegExp(r'^\d{6}$').hasMatch(code)) continue;
        if (name.isEmpty) continue;
        // 只保留 A 股：sh/sz 前缀
        if (!fullCode.startsWith('sh') && !fullCode.startsWith('sz')) continue;
        final market = fullCode.startsWith('sh') ? 'SH' : 'SZ';
        results.add(Stock(code: code, name: name, market: market));
      }
      _log('搜索[QQ][$keyword] 结果: ${results.length} 条');
      return results;
    } catch (e) {
      _log('搜索[QQ][$keyword] 异常: $e');
      return [];
    }
  }

  /// 东方财富 suggest 搜索（备用）
  Future<List<Stock>> _searchEM(String keyword) async {
    try {
      final resp = await _dio.get(
        ApiConfig.emSuggestBase,
        queryParameters: {
          'input': keyword.trim(),
          'type': '14',
          'token': 'D43BF722C8E33BDC906FB84D85E326E8',
          'count': 20,
          'markettype': '',
          'mktnum': '',
          'jys': '',
          'classify': '',
          'securitytype': '',
        },
        options: Options(headers: {
          'Referer': 'https://www.eastmoney.com/',
          'Origin': 'https://www.eastmoney.com',
        }),
      );
      final raw = resp.data;
      if (raw == null) return [];
      Map<String, dynamic> data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw as Map);
      } else {
        final str = raw.toString().trim();
        if (str.startsWith('<')) {
          _log('搜索[EM][$keyword] 返回了 HTML，跳过');
          return [];
        }
        data = Map<String, dynamic>.from(jsonDecode(str) as Map);
      }
      final items = (data['QuotationCodeTable']?['Data'] as List?) ?? [];
      _log('搜索[EM][$keyword] 原始条数: ${items.length}');
      return items
          .whereType<Map>()
          .where((e) {
            final code = e['Code']?.toString() ?? '';
            if (code.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) {
              return false;
            }
            final type = e['SecurityType']?.toString() ?? '';
            final mktNum = e['MktNum']?.toString() ?? '';
            final classify = e['Classify']?.toString() ?? '';
            return type == '1' ||
                type == '2' ||
                mktNum == '0' ||
                mktNum == '1' ||
                classify == 'AShare';
          })
          .map((e) {
            final code = e['Code']!.toString();
            final mktNum = e['MktNum']?.toString() ?? '';
            final type = e['SecurityType']?.toString() ?? '';
            final String market;
            if (mktNum == '1' || type == '1') {
              market = 'SH';
            } else if (mktNum == '0' || type == '2') {
              market = 'SZ';
            } else {
              market = (code.startsWith('6') ||
                      code.startsWith('5') ||
                      code.startsWith('9'))
                  ? 'SH'
                  : 'SZ';
            }
            return Stock(
              code: code,
              name: e['Name']?.toString() ?? '',
              market: market,
            );
          })
          .where((s) => s.code.isNotEmpty && s.name.isNotEmpty)
          .toList();
    } catch (e) {
      _log('搜索[EM][$keyword] 异常: $e');
      return [];
    }
  }

  /// 搜索（兼容旧调用）
  Future<List<Stock>> searchStocks(String keyword) => searchByName(keyword);

  // ══════════════════════════════════════════════════════════════════════════
  // 市场指数（东方财富公开行情）
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<MarketIndex>> fetchMarketIndices() async {
    const secids = [
      '1.000001', '0.399001', '0.399006', '1.000300', '1.000016',
    ];
    const names = ['上证指数', '深证成指', '创业板指', '沪深300', '上证50'];
    try {
      final resp = await _dio.get(
        ApiConfig.emIndexBase,
        queryParameters: {
          'fltt': 2,
          'invt': 2,
          'ut': ApiConfig.emUtToken,
          'fields': 'f2,f3,f4,f12,f14',
          'secids': secids.join(','),
        },
      );
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
      return names
          .map((n) =>
              MarketIndex(code: '-', name: n, price: 0, change: 0, changePercent: 0))
          .toList();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 北向资金（东方财富）
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> fetchNorthboundFlow() async {
    try {
      final resp = await _dio.get(
        ApiConfig.emNorthboundBase,
        queryParameters: {
          'fields1': 'f1,f2,f3,f4',
          'fields2': 'f51,f52,f53,f54,f55,f56',
          'ut': ApiConfig.emUtToken,
        },
      );
      final d = resp.data?['data'];
      if (d == null) return {};
      return {
        'sh_net': (_n(d['f2']) ?? 0.0),
        'sz_net': (_n(d['f3']) ?? 0.0),
        'total_net': (_n(d['f4']) ?? 0.0),
      };
    } catch (_) {
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 自动排雷数据（财务/质押/分红）东方财富数据中心公开接口
  // ══════════════════════════════════════════════════════════════════════════

  Future<AutoRiskData> fetchAutoRiskData(String code, String market) async {
    final secuCode = '$code.${market == "SH" ? "SH" : "SZ"}';
    final notes = <String>[];

    final pledgeRows = await _fetchFirstReport(
      reportNames: const [
        'RPT_PLEDGE_RATIO',
        'RPTA_WEB_EQUITYPLEDGE',
        'RPT_F10_EH_EQUITYPLEDGE',
      ],
      filters: ['(SECURITY_CODE="$code")', '(SECUCODE="$secuCode")'],
      sortColumns: 'TRADE_DATE,END_DATE,REPORT_DATE',
    );

    final financeRows = await _fetchFirstReport(
      reportNames: const [
        'RPT_F10_FINANCE_MAINFINADATA',
        'RPT_F10_MAIN_TARGET',
        'RPT_DMSK_FN_MAININDICATOR',
      ],
      filters: ['(SECUCODE="$secuCode")', '(SECURITY_CODE="$code")'],
      sortColumns: 'REPORT_DATE,NOTICE_DATE',
    );

    final dividendRows = await _fetchFirstReport(
      reportNames: const [
        'RPT_SHAREBONUS_DET',
        'RPT_F10_SHAREBONUS',
        'RPT_F10_DIVIDEND',
      ],
      filters: ['(SECURITY_CODE="$code")', '(SECUCODE="$secuCode")'],
      sortColumns: 'REPORT_DATE,EX_DIVIDEND_DATE,NOTICE_DATE',
      pageSize: 20,
    );

    // 若有聚合数据 key，用聚合分红接口补充
    if (ApiConfig.hasJuheKey && dividendRows.isEmpty) {
      final juheDiv = await _fetchDividendJuhe(code, market);
      if (juheDiv.isNotEmpty) {
        notes.add('已通过聚合数据读取分红记录');
        final pledge = _firstNum(pledgeRows, const [
          'PLEDGE_RATIO', 'TOTAL_PLEDGE_RATIO', 'ZYBL',
        ]);
        if (pledge != null) notes.add('已自动读取质押率');
        final debtRatio = _firstNum(financeRows, const [
          'ZCFZL', 'DEBT_ASSET_RATIO', 'ASSET_LIAB_RATIO',
        ]);
        if (debtRatio != null) notes.add('已自动读取负债率');
        return AutoRiskData(
          pledgeRatio: pledge,
          debtRatio: debtRatio,
          dividendYears: juheDiv.length,
          dividendStability: juheDiv.length >= 5 ? 'stable' : 'normal',
          sourceNotes: notes,
        );
      }
    }

    final pledge = _firstNum(pledgeRows, const [
      'PLEDGE_RATIO', 'TOTAL_PLEDGE_RATIO', 'ZYBL',
      'PLEDGE_RATIO_TOTAL', 'PLEDGE_SHARE_RATIO',
    ]);
    if (pledge != null) notes.add('已自动读取质押率');

    final latestFinance =
        financeRows.isNotEmpty ? financeRows.first : null;

    final debtRatio = _firstNum(financeRows, const [
      'ZCFZL', 'DEBT_ASSET_RATIO', 'ASSET_LIAB_RATIO',
      'TOTAL_LIAB_RATIO', 'DEBT_TO_ASSETS',
    ]);
    if (debtRatio != null) notes.add('已自动读取负债率');

    final goodwillRatio = _extractGoodwill(latestFinance);
    if (goodwillRatio != null) notes.add('已自动估算商誉占比');

    final cashflowMargin = _extractCashflow(latestFinance);
    if (cashflowMargin != null) notes.add('已自动估算现金流利润比');

    final dividendYield = _firstNum(dividendRows, const [
      'DIVIDEND_YIELD', 'BONUS_YIELD', 'DIVIDEND_RATIO', 'CASH_DIVIDEND_YIELD',
    ]);
    final dividendYears = _countDivYears(dividendRows);
    final dividendStable = dividendYears >= 5
        ? 'stable'
        : dividendYears >= 2
            ? 'normal'
            : null;
    if (dividendYield != null || dividendYears > 0) {
      notes.add('已自动读取分红记录');
    }

    return AutoRiskData(
      pledgeRatio: pledge,
      debtRatio: debtRatio,
      goodwillRatio: goodwillRatio,
      cashflowMargin: cashflowMargin,
      dividendYield: dividendYield,
      dividendYears: dividendYears > 0 ? dividendYears : null,
      dividendStability: dividendStable,
      sourceNotes: notes,
    );
  }

  /// 聚合数据历史分红接口（需 key）
  Future<List<Map<String, dynamic>>> _fetchDividendJuhe(
      String code, String market) async {
    try {
      final resp = await _dio.get(
        ApiConfig.juheDividendUrl,
        queryParameters: {
          'gid': _sinaCode(code, market),
          'key': ApiConfig.juheStockKey,
          'page': 1,
          'perpage': 20,
        },
      );
      final list = resp.data?['result']?['data'] as List?;
      return list
              ?.whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList() ??
          [];
    } catch (_) {
      return [];
    }
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
          reportName: rn,
          filter: f,
          sortColumns: sortColumns,
          pageSize: pageSize,
        );
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
      final resp = await _dio.get(
        ApiConfig.emDatacenterBase,
        queryParameters: {
          'sortColumns': sortColumns,
          'sortTypes': '-1',
          'pageSize': pageSize,
          'pageNumber': 1,
          'reportName': reportName,
          'columns': 'ALL',
          'source': 'WEB',
          'client': 'WEB',
          'filter': filter,
        },
      );
      final data = resp.data?['result']?['data'];
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
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
    final direct = _firstNum([row], const [
      'GOODWILL_RATIO', 'GOODWILL_ASSET_RATIO', 'SYZB',
    ]);
    if (direct != null) return direct;
    final gw = _firstNum([row], const ['GOODWILL', 'GOODWILL_VALUE']);
    final ta = _firstNum([row], const [
      'TOTAL_ASSETS', 'TOTAL_ASSET', 'ASSETS_TOTAL',
    ]);
    if (gw == null || ta == null || ta <= 0) return null;
    return gw / ta * 100;
  }

  double? _extractCashflow(Map<String, dynamic>? row) {
    if (row == null) return null;
    final direct = _firstNum([row], const [
      'NETCASH_OPERATE_INCOME_RATIO', 'OPERATE_CASHFLOW_PROFIT_RATIO', 'JYXJLRTB',
    ]);
    if (direct != null) return direct;
    final cf = _firstNum([row], const [
      'NETCASH_OPERATE', 'NET_OPERATE_CASHFLOW', 'CASHFLOW_FROM_OPERATING',
    ]);
    final profit = _firstNum([row], const [
      'PARENT_NETPROFIT', 'NETPROFIT', 'NET_PROFIT',
    ]);
    if (cf == null || profit == null || profit == 0) return null;
    return cf / profit * 100;
  }

  int _countDivYears(List<Map<String, dynamic>> rows) {
    final years = <String>{};
    for (final row in rows) {
      final cash = _firstNum([row], const [
        'CASH_DIVIDEND', 'CASH_BONUS', 'ASSIGN_PROGRESS', 'BONUS_AMOUNT',
      ]);
      if (cash == null || cash <= 0) continue;
      final rawDate = row['REPORT_DATE'] ??
          row['EX_DIVIDEND_DATE'] ??
          row['NOTICE_DATE'] ??
          row['PLAN_NOTICE_DATE'];
      final date = rawDate?.toString() ?? '';
      if (date.length >= 4) years.add(date.substring(0, 4));
    }
    return years.length;
  }

  /// 估值快照（向后兼容）
  Future<Map<String, dynamic>> fetchValuation(
      String code, String market) async {
    final stock = await fetchStockQuote(code, market);
    if (stock == null) return {};
    return {
      'pe': stock.pe,
      'pb': stock.pb,
      'market_cap': stock.marketCap,
      'price': stock.price,
    };
  }
}

// ── 排雷数据返回值 ─────────────────────────────────────────────────────────────

class AutoRiskData {
  final double? pledgeRatio;
  final double? debtRatio;
  final double? goodwillRatio;
  final double? cashflowMargin;
  final double? dividendYield;
  final int? dividendYears;
  final String? dividendStability;
  final List<String> sourceNotes;

  const AutoRiskData({
    this.pledgeRatio,
    this.debtRatio,
    this.goodwillRatio,
    this.cashflowMargin,
    this.dividendYield,
    this.dividendYears,
    this.dividendStability,
    this.sourceNotes = const [],
  });

  bool get hasDeepData =>
      pledgeRatio != null ||
      debtRatio != null ||
      goodwillRatio != null ||
      cashflowMargin != null ||
      dividendYield != null ||
      dividendYears != null;
}
