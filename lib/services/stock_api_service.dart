import 'package:dio/dio.dart';
import '../models/stock.dart';
import '../models/watchlist.dart';

/// 东方财富公开接口封装
class StockApiService {
  static const _eastMoneySearchToken =
      String.fromEnvironment('EASTMONEY_SEARCH_TOKEN');

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
        'Referer': 'https://m.eastmoney.com/',
      },
    ));
  }

  /// 获取沪深主要指数
  Future<List<MarketIndex>> fetchMarketIndices() async {
    const codes = [
      '1.000001', // 上证指数
      '0.399001', // 深证成指
      '0.399006', // 创业板指
      '1.000300', // 沪深300
      '1.000016', // 上证50
    ];
    final names = ['上证指数', '深证成指', '创业板指', '沪深300', '上证50'];

    try {
      final resp = await _dio.get(
        'https://push2.eastmoney.com/api/qt/ulist.np/get',
        queryParameters: {
          'fltt': 2,
          'invt': 2,
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
          'fields': 'f2,f3,f4,f12,f14',
          'secids': codes.join(','),
        },
      );
      final data = resp.data;
      if (data == null || data['data'] == null) return _fallbackIndices(names);
      final items = data['data']['diff'] as List? ?? [];
      return List.generate(items.length, (i) {
        final item = items[i];
        return MarketIndex(
          code: item['f12']?.toString() ?? codes[i].split('.').last,
          name: names[i],
          price: (item['f2'] ?? 0.0).toDouble(),
          change: (item['f4'] ?? 0.0).toDouble(),
          changePercent: (item['f3'] ?? 0.0).toDouble(),
        );
      });
    } catch (_) {
      return _fallbackIndices(names);
    }
  }

  List<MarketIndex> _fallbackIndices(List<String> names) {
    return names
        .map((n) => MarketIndex(
              code: '-',
              name: n,
              price: 0,
              change: 0,
              changePercent: 0,
            ))
        .toList();
  }

  /// 搜索股票（支持名称、代码、拼音首字母）
  Future<List<Stock>> searchStocks(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    if (_eastMoneySearchToken.isEmpty) return searchByName(keyword);

    try {
      final resp = await _dio.get(
        'https://searchapi.eastmoney.com/api/suggest/get',
        queryParameters: {
          'input': keyword,
          'type': '14',
          'token': _eastMoneySearchToken,
          'count': 20,
        },
      );
      final data = resp.data;
      if (data == null || data['QuotationCodeTable'] == null) {
        return searchByName(keyword);
      }
      final items = data['QuotationCodeTable']['Data'] as List? ?? [];
      final results = items
          .where((e) => e['SecurityType'] == '1' || e['SecurityType'] == '2')
          .map((e) {
        final mkt = e['SecurityType'] == '1' ? 'SH' : 'SZ';
        return Stock(
          code: e['Code'] ?? '',
          name: e['Name'] ?? '',
          market: mkt,
        );
      }).toList();
      if (results.isEmpty) return searchByName(keyword);
      return results;
    } catch (_) {
      return searchByName(keyword);
    }
  }

  /// 通过东方财富公开 suggest 接口搜索（不需要 token）
  Future<List<Stock>> searchByName(String keyword) async {
    if (keyword.trim().isEmpty) return [];
    try {
      final resp = await _dio.get(
        'https://suggest3.eastmoney.com/api/suggest/get',
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
      );
      final data = resp.data;
      if (data == null) return [];
      final table = data['QuotationCodeTable'];
      if (table == null) return [];
      final items = table['Data'] as List? ?? [];
      return items
          .where((e) {
            final type = e['SecurityType']?.toString() ?? '';
            final market = e['MktNum']?.toString() ?? '';
            return (type == '1' || type == '2') &&
                (market == '0' || market == '1');
          })
          .map((e) {
            final mktNum = e['MktNum']?.toString() ?? '0';
            final mkt = mktNum == '1' ? 'SH' : 'SZ';
            return Stock(
              code: e['Code'] ?? '',
              name: e['Name'] ?? '',
              market: mkt,
            );
          })
          .where((s) => s.code.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取单只股票实时行情
  Future<Stock?> fetchStockQuote(String code, String market) async {
    final secid = '${market == "SH" ? 1 : 0}.$code';
    try {
      final resp = await _dio.get(
        'https://push2.eastmoney.com/api/qt/stock/get',
        queryParameters: {
          'fltt': 2,
          'invt': 2,
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
          'fields':
              'f43,f57,f58,f169,f170,f46,f44,f45,f168,f47,f116,f167,f161,f49',
          'secid': secid,
        },
      );
      final d = resp.data?['data'];
      if (d == null) return null;
      return Stock(
        code: code,
        name: d['f58'] ?? '',
        market: market,
        price: (d['f43'] ?? 0.0).toDouble(),
        change: (d['f169'] ?? 0.0).toDouble(),
        changePercent: (d['f170'] ?? 0.0).toDouble(),
        high: (d['f44'] ?? 0.0).toDouble(),
        low: (d['f45'] ?? 0.0).toDouble(),
        open: (d['f46'] ?? 0.0).toDouble(),
        volume: (d['f47'] ?? 0.0).toDouble(),
        turnover: (d['f48'] ?? 0.0).toDouble(),
        pe: (d['f167'] ?? 0.0).toDouble(),
        pb: (d['f168'] ?? 0.0).toDouble(),
        marketCap: (d['f116'] ?? 0.0).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 批量获取自选股行情
  Future<Map<String, Stock>> fetchBatchQuotes(List<Watchlist> watchlist) async {
    if (watchlist.isEmpty) return {};
    final secids = watchlist
        .map((w) => '${w.market == "SH" ? 1 : 0}.${w.stockCode}')
        .join(',');
    try {
      final resp = await _dio.get(
        'https://push2.eastmoney.com/api/qt/ulist.np/get',
        queryParameters: {
          'fltt': 2,
          'invt': 2,
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
          'fields': 'f2,f3,f4,f12,f13,f14,f15,f16,f17,f47,f116,f167,f168',
          'secids': secids,
        },
      );
      final items = (resp.data?['data']?['diff'] as List?) ?? [];
      final result = <String, Stock>{};
      for (final item in items) {
        final code = item['f12']?.toString() ?? '';
        if (code.isEmpty) continue;
        final mkt = item['f13'] == 1 ? 'SH' : 'SZ';
        result[code] = Stock(
          code: code,
          name: item['f14'] ?? '',
          market: mkt,
          price: (item['f2'] ?? 0.0).toDouble(),
          change: (item['f4'] ?? 0.0).toDouble(),
          changePercent: (item['f3'] ?? 0.0).toDouble(),
          high: (item['f15'] ?? 0.0).toDouble(),
          low: (item['f16'] ?? 0.0).toDouble(),
          open: (item['f17'] ?? 0.0).toDouble(),
          volume: (item['f47'] ?? 0.0).toDouble(),
          marketCap: (item['f116'] ?? 0.0).toDouble(),
          pe: (item['f167'] ?? 0.0).toDouble(),
          pb: (item['f168'] ?? 0.0).toDouble(),
        );
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 获取K线数据（日线）
  Future<List<Map<String, dynamic>>> fetchKlineDaily(String code, String market,
      {int limit = 120}) async {
    final secid = '${market == "SH" ? 1 : 0}.$code';
    try {
      final resp = await _dio.get(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get',
        queryParameters: {
          'fields1': 'f1,f2,f3,f4,f5,f6',
          'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
          'klt': 101, // 日K
          'fqt': 1, // 前复权
          'secid': secid,
          'beg': 0,
          'end': '20500101',
          'lmt': limit,
        },
      );
      final klines = (resp.data?['data']?['klines'] as List?) ?? [];
      return klines.map<Map<String, dynamic>>((k) {
        final parts = (k as String).split(',');
        return {
          'date': parts[0],
          'open': double.tryParse(parts[1]) ?? 0.0,
          'close': double.tryParse(parts[2]) ?? 0.0,
          'high': double.tryParse(parts[3]) ?? 0.0,
          'low': double.tryParse(parts[4]) ?? 0.0,
          'volume': double.tryParse(parts[5]) ?? 0.0,
          'turnover': double.tryParse(parts[6]) ?? 0.0,
          'change_percent': double.tryParse(parts[8]) ?? 0.0,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取股票财务估值数据（PE历史百分位需要历史数据计算）
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

  /// 尽可能自动拉取排雷数据。
  ///
  /// 东方财富公开 datacenter 报表字段会随页面和报告期变化，因此这里使用多报表、
  /// 多字段名容错匹配。取不到的数据保持 null，由页面继续允许用户手工核验。
  Future<AutoRiskData> fetchAutoRiskData(String code, String market) async {
    final secuCode = '$code.${market == "SH" ? "SH" : "SZ"}';
    final notes = <String>[];

    final pledgeRows = await _fetchFirstAvailableReport(
      reportNames: const [
        'RPT_PLEDGE_RATIO',
        'RPTA_WEB_EQUITYPLEDGE',
        'RPT_F10_EH_EQUITYPLEDGE',
      ],
      filters: [
        '(SECURITY_CODE="$code")',
        '(SECUCODE="$secuCode")',
      ],
      sortColumns: 'TRADE_DATE,END_DATE,REPORT_DATE',
    );

    final financeRows = await _fetchFirstAvailableReport(
      reportNames: const [
        'RPT_F10_FINANCE_MAINFINADATA',
        'RPT_F10_MAIN_TARGET',
        'RPT_DMSK_FN_MAININDICATOR',
      ],
      filters: [
        '(SECUCODE="$secuCode")',
        '(SECURITY_CODE="$code")',
      ],
      sortColumns: 'REPORT_DATE,NOTICE_DATE',
    );

    final dividendRows = await _fetchFirstAvailableReport(
      reportNames: const [
        'RPT_SHAREBONUS_DET',
        'RPT_F10_SHAREBONUS',
        'RPT_F10_DIVIDEND',
      ],
      filters: [
        '(SECURITY_CODE="$code")',
        '(SECUCODE="$secuCode")',
      ],
      sortColumns: 'REPORT_DATE,EX_DIVIDEND_DATE,NOTICE_DATE',
      pageSize: 20,
    );

    final pledge = _firstNumber(pledgeRows, const [
      'PLEDGE_RATIO',
      'TOTAL_PLEDGE_RATIO',
      'ZYBL',
      'PLEDGE_RATIO_TOTAL',
      'PLEDGE_SHARE_RATIO',
    ]);
    if (pledge != null) notes.add('已自动读取质押率');

    final latestFinance = financeRows.isNotEmpty ? financeRows.first : null;
    final debtRatio = _firstNumber(financeRows, const [
      'ZCFZL',
      'DEBT_ASSET_RATIO',
      'ASSET_LIAB_RATIO',
      'TOTAL_LIAB_RATIO',
      'DEBT_TO_ASSETS',
    ]);
    if (debtRatio != null) notes.add('已自动读取负债率');

    final goodwillRatio = _extractGoodwillRatio(latestFinance);
    if (goodwillRatio != null) notes.add('已自动估算商誉占比');

    final cashflowMargin = _extractCashflowMargin(latestFinance);
    if (cashflowMargin != null) notes.add('已自动估算现金流利润比');

    final dividendYield = _firstNumber(dividendRows, const [
      'DIVIDEND_YIELD',
      'BONUS_YIELD',
      'DIVIDEND_RATIO',
      'CASH_DIVIDEND_YIELD',
    ]);
    final dividendYears = _countDividendYears(dividendRows);
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

  Future<List<Map<String, dynamic>>> _fetchFirstAvailableReport({
    required List<String> reportNames,
    required List<String> filters,
    required String sortColumns,
    int pageSize = 5,
  }) async {
    for (final reportName in reportNames) {
      for (final filter in filters) {
        final rows = await _fetchDatacenterRows(
          reportName: reportName,
          filter: filter,
          sortColumns: sortColumns,
          pageSize: pageSize,
        );
        if (rows.isNotEmpty) return rows;
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchDatacenterRows({
    required String reportName,
    required String filter,
    required String sortColumns,
    int pageSize = 5,
  }) async {
    try {
      final resp = await _dio.get(
        'https://datacenter-web.eastmoney.com/api/data/v1/get',
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

  double? _firstNumber(List<Map<String, dynamic>> rows, List<String> keys) {
    for (final row in rows) {
      for (final key in keys) {
        final value = _number(row[key]);
        if (value != null) return value;
      }
      for (final entry in row.entries) {
        final upper = entry.key.toUpperCase();
        if (keys.any((k) => upper.contains(k))) {
          final value = _number(entry.value);
          if (value != null) return value;
        }
      }
    }
    return null;
  }

  double? _extractGoodwillRatio(Map<String, dynamic>? row) {
    if (row == null) return null;
    final direct = _firstNumber([
      row
    ], const [
      'GOODWILL_RATIO',
      'GOODWILL_ASSET_RATIO',
      'SYZB',
    ]);
    if (direct != null) return direct;
    final goodwill = _firstNumber([row], const ['GOODWILL', 'GOODWILL_VALUE']);
    final totalAssets = _firstNumber([
      row
    ], const [
      'TOTAL_ASSETS',
      'TOTAL_ASSET',
      'ASSETS_TOTAL',
    ]);
    if (goodwill == null || totalAssets == null || totalAssets <= 0) {
      return null;
    }
    return goodwill / totalAssets * 100;
  }

  double? _extractCashflowMargin(Map<String, dynamic>? row) {
    if (row == null) return null;
    final direct = _firstNumber([
      row
    ], const [
      'NETCASH_OPERATE_INCOME_RATIO',
      'OPERATE_CASHFLOW_PROFIT_RATIO',
      'JYXJLRTB',
    ]);
    if (direct != null) return direct;
    final cashflow = _firstNumber([
      row
    ], const [
      'NETCASH_OPERATE',
      'NET_OPERATE_CASHFLOW',
      'CASHFLOW_FROM_OPERATING',
    ]);
    final profit = _firstNumber([
      row
    ], const [
      'PARENT_NETPROFIT',
      'NETPROFIT',
      'NET_PROFIT',
    ]);
    if (cashflow == null || profit == null || profit == 0) return null;
    return cashflow / profit * 100;
  }

  int _countDividendYears(List<Map<String, dynamic>> rows) {
    final years = <String>{};
    for (final row in rows) {
      final cash = _firstNumber([
        row
      ], const [
        'CASH_DIVIDEND',
        'CASH_BONUS',
        'ASSIGN_PROGRESS',
        'BONUS_AMOUNT',
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

  double? _number(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text =
        value.toString().replaceAll('%', '').replaceAll(',', '').trim();
    if (text.isEmpty || text == '-' || text == '--') return null;
    return double.tryParse(text);
  }

  /// 获取资金流向（北向资金）
  Future<Map<String, dynamic>> fetchNorthboundFlow() async {
    try {
      final resp = await _dio.get(
        'https://push2.eastmoney.com/api/qt/kamt/get',
        queryParameters: {
          'fields1': 'f1,f2,f3,f4',
          'fields2': 'f51,f52,f53,f54,f55,f56',
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
        },
      );
      final d = resp.data?['data'];
      if (d == null) return {};
      return {
        'sh_net': (d['f2'] ?? 0.0).toDouble(),
        'sz_net': (d['f3'] ?? 0.0).toDouble(),
        'total_net': (d['f4'] ?? 0.0).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }
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
