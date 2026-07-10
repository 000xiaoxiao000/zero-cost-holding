import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../navigation/app_navigation.dart';
import '../providers/holding_providers.dart';
import '../models/holding_batch.dart';
import '../models/stock.dart';
import '../models/stock_context.dart';
import '../services/stock_api_service.dart';

class AddHoldingBatchScreen extends ConsumerStatefulWidget {
  final StockContext? stockContext;

  const AddHoldingBatchScreen({super.key, this.stockContext});

  @override
  ConsumerState<AddHoldingBatchScreen> createState() =>
      _AddHoldingBatchScreenState();
}

class _AddHoldingBatchScreenState extends ConsumerState<AddHoldingBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController;
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _qtyController;
  late final TextEditingController _amountController;
  final _commissionController = TextEditingController(text: '0');
  final _noteController = TextEditingController();

  DateTime _buyDate = DateTime.now();
  late String _assetType;
  late String _market;
  List<Stock> _searchResults = [];
  bool _isSearching = false;
  bool _syncing = false;

  bool get _isFund => _assetType == 'fund';

  @override
  void initState() {
    super.initState();
    final ctx = widget.stockContext;
    _assetType = ctx?.assetType ?? 'stock';
    _market = ctx?.market ?? 'SH';
    _codeController = TextEditingController(text: ctx?.code ?? '');
    _nameController = TextEditingController(text: ctx?.name ?? '');
    _priceController = TextEditingController(
      text: ctx?.planBuyPrice != null
          ? ctx!.planBuyPrice!.toStringAsFixed(3)
          : ctx?.currentPrice != null
              ? ctx!.currentPrice!.toStringAsFixed(3)
              : '',
    );
    _qtyController = TextEditingController(
      text: ctx?.planQuantity != null
          ? ctx!.planQuantity!.toStringAsFixed(0)
          : '',
    );
    _amountController = TextEditingController();
    _syncAmountFromPriceQty();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _amountController.dispose();
    _commissionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _searchStock(String keyword) async {
    if (_isFund) return;
    if (keyword.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    final results = await StockApiService().searchByName(keyword.trim());
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  void _selectStock(Stock stock) {
    _codeController.text = stock.code;
    _nameController.text = stock.name;
    _market = stock.market;
    setState(() => _searchResults = []);
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _buyDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'CN'),
      helpText: '选择记录日期',
      cancelText: '取消',
      confirmText: '确定',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accent,
            surface: AppTheme.bgCard,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_buyDate),
      helpText: '选择记录时间',
      cancelText: '取消',
      confirmText: '确定',
      hourLabelText: '时',
      minuteLabelText: '分',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.accent,
            surface: AppTheme.bgCard,
          ),
        ),
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (pickedTime == null) return;

    setState(
      () => _buyDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        pickedTime.hour,
        pickedTime.minute,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ctx = widget.stockContext;
    final batch = HoldingBatch(
      assetType: _assetType,
      market: _market,
      stockCode: _codeController.text.trim(),
      stockName: _nameController.text.trim(),
      buyPrice: double.parse(_priceController.text),
      quantity: double.parse(_qtyController.text),
      commission: double.tryParse(_commissionController.text) ?? 0.0,
      buyDate: _buyDate,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      planRecoverPrice: ctx?.planRecoverPrice,
      planRecoverQuantity: ctx?.planRecoverQuantity,
      planCapital: ctx?.planCapital,
      planStartPrice: ctx?.planStartPrice,
      planSeedCount: ctx?.planSeedCount,
      planDropStep: ctx?.planDropStep,
      planRebound: ctx?.planRebound,
      planCommission: ctx?.planCommission,
      planWeightModeKey: ctx?.planWeightModeKey,
    );
    await ref.read(holdingPositionsProvider.notifier).addBatch(batch);
    if (mounted) AppNavigation.goHomeTab(context, HomeTab.holding);
  }

  double get _totalCost {
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final qty = double.tryParse(_qtyController.text) ?? 0;
    final comm = double.tryParse(_commissionController.text) ?? 0.0;
    return price * qty + comm;
  }

  void _syncAmountFromPriceQty() {
    if (_syncing) return;
    final price = double.tryParse(_priceController.text);
    final qty = double.tryParse(_qtyController.text);
    final comm = double.tryParse(_commissionController.text) ?? 0.0;
    if (price == null || qty == null || price <= 0 || qty <= 0) {
      return;
    }
    _syncing = true;
    _amountController.text = (price * qty + comm).toStringAsFixed(2);
    _syncing = false;
  }

  void _syncQtyFromAmount() {
    if (_syncing) return;
    final price = double.tryParse(_priceController.text);
    final amount = double.tryParse(_amountController.text);
    final comm = double.tryParse(_commissionController.text) ?? 0.0;
    if (price == null || amount == null || price <= 0 || amount <= comm) {
      return;
    }
    final rawQty = (amount - comm) / price;
    final qty = (rawQty / 100).floor() * 100;
    if (qty <= 0) return;
    _syncing = true;
    _qtyController.text = qty.toStringAsFixed(0);
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录播种'),
        actions: const [HomeTabMenuButton()],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FormSection(title: '标的信息', children: [
                _AssetTypeSelector(
                  assetType: _assetType,
                  onChanged: (type) {
                    setState(() {
                      _assetType = type;
                      _searchResults = [];
                    });
                  },
                ),
                const SizedBox(height: 12),
                _StockCodeField(
                  controller: _codeController,
                  isSearching: _isSearching,
                  assetType: _assetType,
                  onChanged: _isFund ? (_) {} : _searchStock,
                  onSearch: () => _searchStock(_codeController.text),
                ),
                if (!_isFund && _searchResults.isNotEmpty)
                  _SearchDropdown(
                      results: _searchResults, onSelect: _selectStock),
                const SizedBox(height: 12),
                _LabeledField(
                  label: _isFund ? '基金名称' : '股票名称',
                  controller: _nameController,
                  hint: _isFund ? '例：沪深300ETF联接' : '自动填入或手动输入',
                  validator: (v) => v!.isEmpty ? '请输入名称' : null,
                ),
                if (!_isFund) ...[
                  const SizedBox(height: 12),
                  _MarketSelector(
                      market: _market,
                      onChanged: (m) => setState(() => _market = m)),
                ],
              ]),
              const SizedBox(height: 16),
              _FormSection(title: '播种信息', children: [
                _LabeledField(
                  label: _isFund ? '配置净值' : '配置价格',
                  controller: _priceController,
                  onChanged: (_) {
                    _syncAmountFromPriceQty();
                    setState(() {});
                  },
                  hint: _isFund ? '例：1.2365' : '例：15.36',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    if (_isFund)
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,4}'))
                    else
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,3}'))
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return _isFund ? '请输入配置净值' : '请输入配置价格';
                    }
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) {
                      return _isFund ? '净值必须大于0' : '价格必须大于0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: _isFund ? '配置份额（100份倍数）' : '配置数量（100股倍数）',
                  controller: _qtyController,
                  onChanged: (_) {
                    _syncAmountFromPriceQty();
                    setState(() {});
                  },
                  hint: _isFund ? '例：8123.45' : '例：1000',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return _isFund ? '请输入份额' : '请输入数量';
                    }
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) {
                      return _isFund ? '份额必须大于0' : '数量必须大于0';
                    }
                    if (n % 100 != 0) {
                      return _isFund ? '基金份额须为100份的倍数' : 'A股数量须为100股的倍数';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '播种本金/金额（元）',
                  controller: _amountController,
                  hint: '可自动计算，也可输入后反算数量',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                  ],
                  onChanged: (_) {
                    _syncQtyFromAmount();
                    setState(() {});
                  },
                  validator: null,
                ),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '佣金/手续费（元）',
                  controller: _commissionController,
                  onChanged: (_) {
                    _syncAmountFromPriceQty();
                    setState(() {});
                  },
                  hint: '例：5.00',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,3}'))
                  ],
                  validator: null,
                ),
                const SizedBox(height: 12),
                _DatePickerField(date: _buyDate, onTap: _pickDate),
                const SizedBox(height: 12),
                _LabeledField(
                  label: '备注（可选）',
                  controller: _noteController,
                  hint: _isFund ? '例：定投第一批，宽基低估' : '例：第一批建仓，估值低洼',
                  validator: null,
                ),
              ]),
              const SizedBox(height: 16),
              if (_totalCost > 0) _CostPreview(totalCost: _totalCost),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('确认记录',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _FormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _FormSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: hint),
          validator: validator,
        ),
      ],
    );
  }
}

class _AssetTypeSelector extends StatelessWidget {
  final String assetType;
  final ValueChanged<String> onChanged;

  const _AssetTypeSelector({
    required this.assetType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('资产类型',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            _AssetTypeChip(
              label: '股票',
              icon: Icons.show_chart,
              selected: assetType == 'stock',
              onTap: () => onChanged('stock'),
            ),
            const SizedBox(width: 12),
            _AssetTypeChip(
              label: '基金',
              icon: Icons.pie_chart_outline,
              selected: assetType == 'fund',
              onTap: () => onChanged('fund'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssetTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AssetTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.15)
                : AppTheme.bgCardLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.accent : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockCodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final String assetType;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;

  const _StockCodeField({
    required this.controller,
    required this.isSearching,
    required this.assetType,
    required this.onChanged,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isFund = assetType == 'fund';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isFund ? '基金代码' : '股票代码 / 名称',
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: isFund ? '例：000300' : '代码或名称，如 600519 / 贵州茅台',
            suffixIcon: isFund
                ? null
                : isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.accent),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search,
                            color: AppTheme.textMuted, size: 20),
                        onPressed: onSearch,
                      ),
          ),
          onChanged: onChanged,
          validator: (v) => v!.isEmpty ? '请输入代码或名称' : null,
        ),
      ],
    );
  }
}

class _SearchDropdown extends StatelessWidget {
  final List<Stock> results;
  final ValueChanged<Stock> onSelect;

  const _SearchDropdown({required this.results, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: AppTheme.bgCardLight,
          child: Column(
            children: results
                .take(5)
                .map((s) => ListTile(
                      dense: true,
                      title: Text(s.name,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 14)),
                      subtitle: Text('${s.market} · ${s.code}',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                      onTap: () => onSelect(s),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _MarketSelector extends StatelessWidget {
  final String market;
  final ValueChanged<String> onChanged;

  const _MarketSelector({required this.market, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('市场',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          children: const {
            'SH': '上交所(SH)',
            'SZ': '深交所(SZ)',
            'BJ': '北交所(BJ)',
          }.entries.map((entry) {
            final selected = market == entry.key;
            return GestureDetector(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.accent.withValues(alpha: 0.15)
                      : AppTheme.bgCardLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.borderColor),
                ),
                child: Text(
                  entry.value,
                  style: TextStyle(
                    color: selected ? AppTheme.accent : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerField({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('记录日期',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppTheme.bgCardLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderColor, width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today,
                    color: AppTheme.textMuted, size: 16),
                const SizedBox(width: 10),
                Text(Formatters.dateTimeFull(date),
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 15)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CostPreview extends StatelessWidget {
  final double totalCost;
  const _CostPreview({required this.totalCost});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('本次播种总成本',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          Text(
            '¥ ${Formatters.money(totalCost)}',
            style: const TextStyle(
                color: AppTheme.accentGold,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
