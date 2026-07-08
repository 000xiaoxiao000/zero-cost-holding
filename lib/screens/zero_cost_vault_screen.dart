import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/holding_batch.dart';
import '../providers/holding_providers.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class ZeroCostVaultScreen extends ConsumerWidget {
  const ZeroCostVaultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(holdingPositionsProvider);
    final positions = ref
        .read(holdingPositionsProvider.notifier)
        .holdings
        .where((p) => p.isZeroCost)
        .toList();

    final pureQuantity = positions.fold(
      0.0,
      (sum, p) => sum + p.totalRemaining,
    );
    final recovered = positions.fold(0.0, (sum, p) => sum + p.totalRecovered);

    return Scaffold(
      appBar: AppBar(title: const Text('零成本资产库')),
      body: positions.isEmpty
          ? const _EmptyVault()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              children: [
                _VaultHero(
                  count: positions.length,
                  pureQuantity: pureQuantity,
                  recovered: recovered,
                ),
                const SizedBox(height: 16),
                ...positions.map(
                  (position) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _VaultCard(position: position),
                  ),
                ),
              ],
            ),
    );
  }
}

class _VaultHero extends StatelessWidget {
  final int count;
  final double pureQuantity;
  final double recovered;

  const _VaultHero({
    required this.count,
    required this.pureQuantity,
    required this.recovered,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.accentGold.withValues(alpha: 0.18),
            AppTheme.primaryGreen.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '精神股东荣誉墙',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '本金已经收回。仍有仓位的按纯利润资产管理，已清仓的作为回本毕业记录。',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(label: '资产数', value: '$count'),
              ),
              Expanded(
                child: _HeroMetric(
                  label: '剩余数量',
                  value: Formatters.quantity(pureQuantity),
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: '已回收',
                  value: Formatters.largeNumber(recovered),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VaultCard extends StatelessWidget {
  final HoldingPosition position;

  const _VaultCard({required this.position});

  @override
  Widget build(BuildContext context) {
    final hasRemaining = position.totalRemaining > 0;
    final firstDate = position.batches
        .map((b) => b.buyDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final days = DateTime.now().difference(firstDate).inDays + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.stockName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${position.assetTypeLabel} · ${position.stockCode}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (hasRemaining ? AppTheme.accentGold : AppTheme.accent)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasRemaining ? '纯利润持有' : '回本毕业',
                  style: TextStyle(
                    color: hasRemaining ? AppTheme.accentGold : AppTheme.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniMetric(
                  label: '剩余仓位',
                  value:
                      '${Formatters.quantity(position.totalRemaining)}${position.quantityUnit}',
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: '已收本金',
                  value: Formatters.largeNumber(position.totalRecovered),
                ),
              ),
              Expanded(
                child: _MiniMetric(label: '持有天数', value: '$days天'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '仓位回收 ${Formatters.largeNumber(position.totalSellRecovered)}，现金分红/派发 ${Formatters.largeNumber(position.totalCashIncome)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;

  const _HeroMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.accentGold,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '还没有达成零成本的资产。\n当某个股票或基金的本金全部回收后，会自动进入这里；仍有仓位显示纯利润持有，已清仓显示回本毕业。',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
