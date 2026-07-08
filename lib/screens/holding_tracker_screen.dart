import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/holding_providers.dart';
import '../models/holding_batch.dart';
import 'add_holding_batch_screen.dart';
import 'zero_cost_vault_screen.dart';

class HoldingTrackerScreen extends ConsumerStatefulWidget {
  const HoldingTrackerScreen({super.key});

  @override
  ConsumerState<HoldingTrackerScreen> createState() =>
      _HoldingTrackerScreenState();
}

class _HoldingTrackerScreenState extends ConsumerState<HoldingTrackerScreen> {
  final _searchController = TextEditingController();
  String _assetFilter = 'all';
  String _statusFilter = 'all';
  String _sortMode = 'progress';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(holdingPositionsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<HoldingPosition> _visibleHoldings(List<HoldingPosition> holdings) {
    final keyword = _searchController.text.trim().toLowerCase();
    final filtered = holdings.where((position) {
      final matchesKeyword = keyword.isEmpty ||
          position.stockCode.toLowerCase().contains(keyword) ||
          position.stockName.toLowerCase().contains(keyword);
      final matchesAsset =
          _assetFilter == 'all' || position.assetType == _assetFilter;
      final matchesStatus = switch (_statusFilter) {
        'zero' => position.isZeroCost && position.totalRemaining > 0,
        'graduated' => position.isZeroCost && position.totalRemaining <= 0,
        'pending' => !position.isZeroCost,
        _ => true,
      };
      return matchesKeyword && matchesAsset && matchesStatus;
    }).toList();

    filtered.sort((a, b) {
      return switch (_sortMode) {
        'gap' => b.effectiveRemainingCost.compareTo(a.effectiveRemainingCost),
        'name' => a.stockName.compareTo(b.stockName),
        'value' => b.totalInvested.compareTo(a.totalInvested),
        _ => b.zeroCostProgress.compareTo(a.zeroCostProgress),
      };
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(holdingPositionsProvider);
    final notifier = ref.read(holdingPositionsProvider.notifier);
    final holdings = notifier.holdings;
    final visibleHoldings = _visibleHoldings(holdings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('播种账本'),
        actions: [
          IconButton(
            tooltip: '截图文字导入',
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => _showImportSheet(context, ref),
          ),
          IconButton(
            tooltip: '生成账单',
            icon: const Icon(Icons.description_outlined),
            onPressed: holdings.isEmpty
                ? null
                : () => _showStatement(context, holdings),
          ),
          IconButton(
            tooltip: '零成本资产库',
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ZeroCostVaultScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddHoldingBatchScreen()),
            ).then((_) => ref.read(holdingPositionsProvider.notifier).load()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: holdings.isEmpty
          ? const _EmptyHolding()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _SummaryCard(notifier: notifier),
                const SizedBox(height: 16),
                _BookkeepingTools(
                  controller: _searchController,
                  assetFilter: _assetFilter,
                  statusFilter: _statusFilter,
                  sortMode: _sortMode,
                  strategyCount: holdings.length,
                  onChanged: () => setState(() {}),
                  onAssetFilterChanged: (value) =>
                      setState(() => _assetFilter = value),
                  onStatusFilterChanged: (value) =>
                      setState(() => _statusFilter = value),
                  onSortChanged: (value) => setState(() => _sortMode = value),
                ),
                const SizedBox(height: 12),
                if (visibleHoldings.isEmpty)
                  const _NoFilteredHolding()
                else
                  ...visibleHoldings.map((h) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _HoldingCard(position: h),
                      )),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Future<void> _showStatement(
    BuildContext context,
    List<HoldingPosition> holdings,
  ) async {
    final text = _buildStatement(holdings);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('播种账单'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('账单已复制')),
              );
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制账单'),
          ),
        ],
      ),
    );
  }

  String _buildStatement(List<HoldingPosition> holdings) {
    final totalInvested = holdings.fold(0.0, (sum, h) => sum + h.totalInvested);
    final totalRecovered =
        holdings.fold(0.0, (sum, h) => sum + h.totalRecovered);
    final totalFree = holdings.fold(0.0, (sum, h) => sum + h.freeQuantity);
    final progress = totalInvested > 0 ? totalRecovered / totalInvested : 0.0;
    final buffer = StringBuffer()
      ..writeln('零成本播种账单')
      ..writeln('生成时间：${Formatters.date(DateTime.now())}')
      ..writeln('标的数量：${holdings.length}')
      ..writeln(
          '本金收回进度：${(progress.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%')
      ..writeln('累计播种本金：${Formatters.largeNumber(totalInvested)}')
      ..writeln('已收回现金：${Formatters.largeNumber(totalRecovered)}')
      ..writeln('免费持有数量：${Formatters.quantity(totalFree)}')
      ..writeln('');
    for (final h in holdings) {
      buffer
        ..writeln('${h.stockName} ${h.stockCode}（${h.assetTypeLabel}）')
        ..writeln('  本金收回进度：${(h.zeroCostProgress * 100).toStringAsFixed(1)}%')
        ..writeln('  播种本金：${Formatters.largeNumber(h.totalInvested)}')
        ..writeln('  已收回：${Formatters.largeNumber(h.totalRecovered)}')
        ..writeln(
            '  剩余数量：${Formatters.quantity(h.totalRemaining)}${h.quantityUnit}')
        ..writeln('  最新成本价：${Formatters.price(h.latestZeroCostPrice)}')
        ..writeln(
            '  状态：${h.isZeroCost ? (h.totalRemaining > 0 ? '零成本持有' : '回本毕业') : '回收中'}')
        ..writeln('');
    }
    return buffer.toString();
  }

  Future<void> _showImportSheet(BuildContext context, WidgetRef ref) async {
    final imported = await showDialog<HoldingBatch>(
      context: context,
      builder: (_) => const _ImportTextDialog(),
    );
    if (imported == null || !context.mounted) return;
    await ref.read(holdingPositionsProvider.notifier).addBatch(imported);
  }
}

class _SummaryCard extends ConsumerWidget {
  final HoldingPositionsNotifier notifier;
  const _SummaryCard({required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(holdingPositionsProvider);
    final totalInvested = notifier.totalInvested;
    final totalRecovered = notifier.totalRecovered;
    final freeQuantity =
        notifier.holdings.fold(0.0, (sum, h) => sum + h.freeQuantity);
    final remainingGap =
        totalInvested > totalRecovered ? totalInvested - totalRecovered : 0.0;
    final overallProgress = totalInvested > 0
        ? (totalRecovered / totalInvested).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accent.withValues(alpha: 0.15),
            AppTheme.accentGold.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.eco, color: AppTheme.accentGold, size: 18),
              SizedBox(width: 8),
              Text('播种机账本',
                  style: TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _StatCol(
                      label: '我的本金收回进度',
                      value: '${(overallProgress * 100).toStringAsFixed(1)}%',
                      color: AppTheme.accentGold)),
              Expanded(
                  child: _StatCol(
                      label: '免费赚到数量',
                      value: Formatters.quantity(freeQuantity),
                      color: AppTheme.primaryGreen)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCol(
                  label: '累计播种本金',
                  value: Formatters.largeNumber(totalInvested),
                  color: AppTheme.textSecondary,
                ),
              ),
              Expanded(
                child: _StatCol(
                  label: '已收回现金',
                  value: Formatters.largeNumber(totalRecovered),
                  color: AppTheme.textSecondary,
                ),
              ),
              Expanded(
                child: _StatCol(
                  label: '待回收缺口',
                  value: Formatters.largeNumber(remainingGap),
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: LinearPercentIndicator(
                  lineHeight: 8,
                  percent: overallProgress,
                  backgroundColor: AppTheme.bgCardLight,
                  progressColor: AppTheme.accentGold,
                  barRadius: const Radius.circular(4),
                  padding: EdgeInsets.zero,
                ),
              ),
              const SizedBox(width: 12),
              Text('${(overallProgress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            overallProgress >= 1.0
                ? '已达成零成本资产口径，剩余数量进入免费持有统计'
                : '还需回收 ${Formatters.largeNumber(remainingGap)} 即可实现零成本',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCol(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BookkeepingTools extends StatelessWidget {
  final TextEditingController controller;
  final String assetFilter;
  final String statusFilter;
  final String sortMode;
  final int strategyCount;
  final VoidCallback onChanged;
  final ValueChanged<String> onAssetFilterChanged;
  final ValueChanged<String> onStatusFilterChanged;
  final ValueChanged<String> onSortChanged;

  const _BookkeepingTools({
    required this.controller,
    required this.assetFilter,
    required this.statusFilter,
    required this.sortMode,
    required this.strategyCount,
    required this.onChanged,
    required this.onAssetFilterChanged,
    required this.onStatusFilterChanged,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final inBasicQuota = strategyCount <= 5;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: '搜索代码或名称',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ToolDropdown(
                  value: assetFilter,
                  items: const {
                    'all': '全部资产',
                    'stock': '股票',
                    'fund': '基金',
                  },
                  onChanged: onAssetFilterChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToolDropdown(
                  value: statusFilter,
                  items: const {
                    'all': '全部状态',
                    'pending': '回收中',
                    'zero': '零成本',
                    'graduated': '回本毕业',
                  },
                  onChanged: onStatusFilterChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ToolDropdown(
            value: sortMode,
            items: const {
              'progress': '按本金收回进度',
              'gap': '按待回收缺口',
              'value': '按播种本金',
              'name': '按名称',
            },
            onChanged: onSortChanged,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  (inBasicQuota ? AppTheme.primaryGreen : AppTheme.accentGold)
                      .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              inBasicQuota
                  ? '基础策略池：$strategyCount / 5。账本不限数量，前5只默认纳入播种策略计算。'
                  : '账本已超过5只。全部记录仍可管理；高级量化策略可按筛选/排序选择重点标的。当前为本地策略建议提示，不触达执行。',
              style: TextStyle(
                color:
                    inBasicQuota ? AppTheme.primaryGreen : AppTheme.accentGold,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDropdown extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const _ToolDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: AppTheme.bgCard,
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
      items: items.entries
          .map(
            (entry) => DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
    );
  }
}

class _NoFilteredHolding extends StatelessWidget {
  const _NoFilteredHolding();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: const Text(
        '当前筛选条件下没有账本记录。',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _HoldingCard extends ConsumerWidget {
  final HoldingPosition position;
  const _HoldingCard({required this.position});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = position.zeroCostProgress;
    final progressColor =
        position.isZeroCost ? AppTheme.accentGold : AppTheme.accent;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: position.isZeroCost
              ? AppTheme.accentGold.withValues(alpha: 0.4)
              : AppTheme.borderColor,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(position.stockName,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          if (position.isZeroCost) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.accentGold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('零成本',
                                  style: TextStyle(
                                      color: AppTheme.accentGold,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('${position.assetTypeLabel} · ${position.stockCode}',
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                        '剩余 ${Formatters.quantity(position.totalRemaining)} ${position.quantityUnit}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text(
                        '最新成本价 ¥${Formatters.price(position.latestZeroCostPrice)}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13)),
                  ],
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
                  color: AppTheme.bgCard,
                  onSelected: (value) async {
                    if (value == 'delete') {
                      await _confirmDeletePosition(context, ref, position);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除该标的账本'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '本金收回 ${Formatters.largeNumber(position.totalRecovered)} / 播种本金 ${Formatters.largeNumber(position.totalInvested)}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11),
                    ),
                    Text('${(progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                            color: progressColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                LinearPercentIndicator(
                  lineHeight: 6,
                  percent: progress,
                  backgroundColor: AppTheme.bgCardLight,
                  progressColor: progressColor,
                  barRadius: const Radius.circular(3),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 20, indent: 16, endIndent: 16),
          ...position.batches.map((b) => _BatchRow(batch: b)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmDeletePosition(
    BuildContext context,
    WidgetRef ref,
    HoldingPosition position,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('删除账本'),
        content: Text(
          '将删除 ${position.stockName} 的全部播种、回收和现金派发记录，并重新计算零成本资产库。此操作无法恢复。',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(holdingPositionsProvider.notifier).deletePosition(
          assetType: position.assetType,
          stockCode: position.stockCode,
        );
  }
}

class _BatchRow extends ConsumerWidget {
  final HoldingBatch batch;
  const _BatchRow({required this.batch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dotColor = batch.isZeroCost
        ? AppTheme.accentGold
        : batch.isFullySold
            ? AppTheme.textMuted
            : AppTheme.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${Formatters.date(batch.buyDate)} 播种 ${Formatters.quantity(batch.quantity)}${batch.quantityUnit} @ ¥${Formatters.price(batch.buyPrice)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
                if (batch.sellPrice != null)
                  Text(
                    '已回收 ${Formatters.quantity(batch.sellQuantity ?? 0)}${batch.quantityUnit} @ ¥${Formatters.price(batch.sellPrice!)}，现金 ¥${Formatters.largeNumber(batch.recoveredAmount)}',
                    style: const TextStyle(
                        color: AppTheme.primaryGreen, fontSize: 11),
                  ),
                if (batch.cashIncome > 0)
                  Text(
                    '现金分红/派发 ¥${Formatters.largeNumber(batch.cashIncome)}',
                    style: const TextStyle(
                        color: AppTheme.accentGold, fontSize: 11),
                  ),
              ],
            ),
          ),
          _BatchProgressBadge(progress: batch.zeroCostProgress),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: '记录回收',
            onPressed: batch.id == null || batch.isFullySold
                ? null
                : () => _showRecoverDialog(context, ref, batch),
            icon: const Icon(Icons.receipt_long_outlined),
            color: AppTheme.accentGold,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: '记录现金派发',
            onPressed: batch.id == null
                ? null
                : () => _showCashIncomeDialog(context, ref, batch),
            icon: const Icon(Icons.water_drop_outlined),
            color: AppTheme.primaryGreen,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: '删除记录',
            onPressed: batch.id == null
                ? null
                : () => _confirmDeleteBatch(context, ref, batch),
            icon: const Icon(Icons.delete_outline),
            color: AppTheme.riskRed,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteBatch(
    BuildContext context,
    WidgetRef ref,
    HoldingBatch batch,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('删除播种记录'),
        content: Text(
          '将删除 ${batch.stockName} ${Formatters.date(batch.buyDate)} 的这条记录，并重新计算本金收回进度。此操作无法恢复。',
          style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.riskRed),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || batch.id == null || !context.mounted) return;
    await ref.read(holdingPositionsProvider.notifier).deleteBatch(batch.id!);
  }

  Future<void> _showCashIncomeDialog(
    BuildContext context,
    WidgetRef ref,
    HoldingBatch batch,
  ) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _CashIncomeDialog(batch: batch),
    );

    if (amount == null || batch.id == null || !context.mounted) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    await ref
        .read(holdingPositionsProvider.notifier)
        .recordCashIncome(batch.id!, amount);
  }

  Future<void> _showRecoverDialog(
    BuildContext context,
    WidgetRef ref,
    HoldingBatch batch,
  ) async {
    final recovered = await showDialog<({double price, double quantity})>(
      context: context,
      builder: (_) => _RecoverDialog(batch: batch),
    );

    if (recovered == null || batch.id == null || !context.mounted) {
      return;
    }

    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    await ref.read(holdingPositionsProvider.notifier).recordSell(
        batch.id!, batch.stockCode, recovered.price, recovered.quantity);
  }
}

class _CashIncomeDialog extends StatefulWidget {
  final HoldingBatch batch;

  const _CashIncomeDialog({required this.batch});

  @override
  State<_CashIncomeDialog> createState() => _CashIncomeDialogState();
}

class _CashIncomeDialogState extends State<_CashIncomeDialog> {
  late final TextEditingController _amountController;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.batch.cashIncome > 0
          ? widget.batch.cashIncome.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_amountController.text);
    if (parsed == null || parsed < 0) {
      setState(() => _amountError = '请输入有效金额');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('记录现金回收'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${batch.assetTypeLabel} · ${batch.stockName} ${batch.stockCode}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: '累计现金分红/派发',
              helperText: '填累计金额，会计入本金回收进度',
              errorText: _amountError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _RecoverDialog extends StatefulWidget {
  final HoldingBatch batch;

  const _RecoverDialog({required this.batch});

  @override
  State<_RecoverDialog> createState() => _RecoverDialogState();
}

class _RecoverDialogState extends State<_RecoverDialog> {
  late final TextEditingController _priceController;
  late final TextEditingController _qtyController;
  String? _priceError;
  String? _quantityError;

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _priceController =
        TextEditingController(text: batch.sellPrice?.toStringAsFixed(2) ?? '');
    _qtyController = TextEditingController(
      text: (batch.sellQuantity ?? batch.remainingQuantity).toString(),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  void _submit() {
    final batch = widget.batch;
    final price = double.tryParse(_priceController.text);
    final quantity = double.tryParse(_qtyController.text);
    String? nextPriceError;
    String? nextQuantityError;

    if (price == null || price <= 0) {
      nextPriceError = batch.isFund ? '请输入有效净值' : '请输入有效价格';
    }
    if (quantity == null || quantity <= 0) {
      nextQuantityError = batch.isFund ? '请输入有效份额' : '请输入有效股数';
    } else if (quantity > batch.quantity) {
      nextQuantityError = '不能超过本批播种${batch.quantityUnit}数';
    }

    if (nextPriceError != null || nextQuantityError != null) {
      setState(() {
        _priceError = nextPriceError;
        _quantityError = nextQuantityError;
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, (
      price: price!,
      quantity: quantity!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('记录回收'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${batch.assetTypeLabel} · ${batch.stockName} ${batch.stockCode}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              if (batch.isFund)
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,4}'))
              else
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: batch.isFund ? '回收确认净值' : '回收参考价格',
              errorText: _priceError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              if (batch.isFund)
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,4}'))
              else
                FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: batch.isFund ? '累计回收份额' : '累计回收股数',
              helperText:
                  '最多 ${Formatters.quantity(batch.quantity)} ${batch.quantityUnit}，当前剩余 ${Formatters.quantity(batch.remainingQuantity)} ${batch.quantityUnit}',
              errorText: _quantityError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _ImportTextDialog extends StatefulWidget {
  const _ImportTextDialog();

  @override
  State<_ImportTextDialog> createState() => _ImportTextDialogState();
}

class _ImportTextDialogState extends State<_ImportTextDialog> {
  final _rawController = TextEditingController();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();
  final _feeController = TextEditingController(text: '0');
  String _assetType = 'stock';
  String? _error;

  @override
  void dispose() {
    _rawController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _pasteAndParse() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.isEmpty) {
      setState(() => _error = '剪贴板没有可解析文字');
      return;
    }
    _rawController.text = text;
    _parseText(text);
  }

  void _parseText(String text) {
    final code = RegExp(r'\b\d{6}\b').firstMatch(text)?.group(0);
    final numbers = RegExp(r'\d+(?:\.\d+)?')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(0)!))
        .whereType<double>()
        .toList();
    final compactLines = text
        .split(RegExp(r'[\n\r]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final nameLine = compactLines.firstWhere(
      (line) =>
          !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(line) && !line.contains('代码'),
      orElse: () => '',
    );

    setState(() {
      if (code != null) _codeController.text = code;
      if (nameLine.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = nameLine.replaceAll(code ?? '', '').trim();
      }
      if (numbers.isNotEmpty && _priceController.text.trim().isEmpty) {
        final price = numbers.firstWhere(
          (n) => n > 0 && n < 10000 && n.toStringAsFixed(0) != code,
          orElse: () => numbers.first,
        );
        _priceController.text = price.toStringAsFixed(2);
      }
      if (numbers.length > 1 && _qtyController.text.trim().isEmpty) {
        final quantity = numbers.firstWhere(
          (n) => n >= 1 && n != double.tryParse(_priceController.text),
          orElse: () => numbers.last,
        );
        _qtyController.text = _assetType == 'fund'
            ? quantity.toStringAsFixed(4)
            : quantity.toStringAsFixed(0);
      }
      _error = null;
    });
  }

  void _submit() {
    final code = _codeController.text.trim();
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text);
    final quantity = double.tryParse(_qtyController.text);
    final fee = double.tryParse(_feeController.text) ?? 0.0;
    if (code.isEmpty ||
        name.isEmpty ||
        price == null ||
        price <= 0 ||
        quantity == null ||
        quantity <= 0) {
      setState(() => _error = '请确认代码、名称、价格/净值和数量/份额都有效');
      return;
    }
    if (_assetType == 'stock' && quantity % 100 != 0) {
      setState(() => _error = 'A股数量建议按100股整数倍记录');
      return;
    }
    Navigator.pop(
      context,
      HoldingBatch(
        assetType: _assetType,
        stockCode: code,
        stockName: name,
        buyPrice: price,
        quantity: quantity,
        commission: fee,
        buyDate: DateTime.now(),
        note: '截图文字导入草稿',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFund = _assetType == 'fund';
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('截图文字导入'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '先用手机系统 OCR 复制截图文字，再粘贴解析；保存前请人工确认。',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _DialogChoiceChip(
                  label: '股票',
                  selected: _assetType == 'stock',
                  onTap: () => setState(() => _assetType = 'stock'),
                ),
                const SizedBox(width: 8),
                _DialogChoiceChip(
                  label: '基金',
                  selected: _assetType == 'fund',
                  onTap: () => setState(() => _assetType = 'fund'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _rawController,
              minLines: 3,
              maxLines: 5,
              onChanged: _parseText,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
              decoration: const InputDecoration(hintText: '粘贴截图识别文字'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pasteAndParse,
              icon: const Icon(Icons.content_paste, size: 16),
              label: const Text('从剪贴板粘贴解析'),
            ),
            const SizedBox(height: 12),
            _DialogField(label: '代码', controller: _codeController),
            const SizedBox(height: 10),
            _DialogField(label: '名称', controller: _nameController),
            const SizedBox(height: 10),
            _DialogField(
              label: isFund ? '配置净值' : '配置价格',
              controller: _priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            _DialogField(
              label: isFund ? '配置份额' : '配置数量',
              controller: _qtyController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 10),
            _DialogField(
              label: '费用',
              controller: _feeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: AppTheme.riskRed, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('确认入账'),
        ),
      ],
    );
  }
}

class _DialogChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DialogChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.16)
                : AppTheme.bgCardLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.borderColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.accent : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _DialogField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _BatchProgressBadge extends StatelessWidget {
  final double progress;
  const _BatchProgressBadge({required this.progress});

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).toStringAsFixed(0);
    final color = progress >= 1.0
        ? AppTheme.accentGold
        : progress > 0
            ? AppTheme.primaryGreen
            : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$pct%',
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyHolding extends ConsumerWidget {
  const _EmptyHolding();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco_outlined, color: AppTheme.textMuted, size: 56),
          const SizedBox(height: 16),
          const Text('还没有持仓记录',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('点击右上角 + 记录第一次播种',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddHoldingBatchScreen()),
            ).then((_) => ref.read(holdingPositionsProvider.notifier).load()),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加播种记录'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accentGold,
              side: const BorderSide(color: AppTheme.accentGold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}
