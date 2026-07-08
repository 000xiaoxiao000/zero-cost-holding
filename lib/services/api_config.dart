/// 数据源配置
///
/// 运行时数据源优先级：
///   1. 新浪财经（无需 key，15 分钟延迟行情，合规）
///   2. 腾讯财经（无需 key，备用行情/K线）
///   3. 聚合数据 JuHe（需 key，准实时，可选升级）
///
/// 如需启用聚合数据，在 flutter run / build 时传入环境变量：
///   --dart-define=JUHE_STOCK_KEY=your_key_here
///
/// 聚合数据申请地址：https://www.juhe.cn/docs/api/id/21
class ApiConfig {
  ApiConfig._();

  // ── 聚合数据 ──────────────────────────────────────────────────────────────
  static const String juheStockKey =
      String.fromEnvironment('JUHE_STOCK_KEY', defaultValue: '');

  static bool get hasJuheKey => juheStockKey.isNotEmpty;

  // ── 新浪财经行情 ──────────────────────────────────────────────────────────
  /// 实时/延迟行情（15 分钟延迟，免费，合规）
  static const String sinaQuoteBase = 'https://hq.sinajs.cn';

  /// 历史日K（前复权）
  static const String sinaKlineBase =
      'https://quotes.sina.cn/cn/api/json_v2.php/CN_MarketDataService.getKLineData';

  // ── 腾讯财经行情（备用） ──────────────────────────────────────────────────
  static const String qqQuoteBase = 'https://qt.gtimg.cn';
  static const String qqKlineBase =
      'https://web.ifzq.gtimg.cn/appstock/app/fqkline/get';

  // ── 东方财富搜索/数据中心 ─────────────────────────────────────────────────
  static const String emSuggestBase =
      'https://searchapi.eastmoney.com/api/suggest/get';
  static const String emQuoteBase =
      'https://push2.eastmoney.com/api/qt/stock/get';
  static const String emKlineBase =
      'https://push2his.eastmoney.com/api/qt/stock/kline/get';
  static const String emDatacenterBase =
      'https://datacenter-web.eastmoney.com/api/data/v1/get';
  static const String emIndexBase =
      'https://push2.eastmoney.com/api/qt/ulist.np/get';
  static const String emNorthboundBase =
      'https://push2.eastmoney.com/api/qt/kamt/get';

  /// 公共 ut token（东方财富页面通用值，非私密）
  static const String emUtToken = 'b2884a393a59ad64002292a3e90d46a5';

  // ── 聚合数据接口 ──────────────────────────────────────────────────────────
  static const String juheQuoteUrl =
      'https://web.juhe.cn/finance/stock/hs';
  static const String juheDividendUrl =
      'https://web.juhe.cn/finance/stock/stockBonus';
}
