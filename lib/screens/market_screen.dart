import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../providers/stock_providers.dart';
import '../models/stock.dart';
import 'search_screen.dart';

class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicesAsync = ref.watch(marketIndicesProvider);
    final northAsync = ref.watch(northboundProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('市场概览'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(marketIndicesProvider);
          ref.invalidate(northboundProvider);
        },
        color: AppTheme.accent,
        backgroundColor: AppTheme.bgCard,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 指数区
            indicesAsync.when(
              data: (indices) => _IndexGrid(indices: indices),
              loading: () => const _IndexGridSkeleton(),
              error: (_, __) => _ErrorCard(
                message: '指数数据加载失败',
                onRetry: () => ref.invalidate(marketIndicesProvider),
              ),
            ),
            const SizedBox(height: 20),

            // 北向资金
            _SectionTitle(title: '北向资金', subtitle: '陆股通资金流'),
            const SizedBox(height: 10),
            northAsync.when(
              data: (data) => _NorthboundCard(data: data),
              loading: () => const _ShimmerCard(height: 80),
              error: (_, __) => _ErrorCard(
                message: '北向资金数据加载失败',
                onRetry: () => ref.invalidate(northboundProvider),
              ),
            ),
            const SizedBox(height: 20),

            // 建仓信号说明
            const _EntrySignalTips(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _IndexGrid extends StatelessWidget {
  final List<MarketIndex> indices;
  const _IndexGrid({required this.indices});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.8,
      ),
      itemCount: indices.length,
      itemBuilder: (_, i) => _IndexCard(index: indices[i]),
    );
  }
}

class _IndexCard extends StatelessWidget {
  final MarketIndex index;
  const _IndexCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final color =
        index.changePercent >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            index.name,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            index.price > 0 ? Formatters.price(index.price) : '--',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          Row(
            children: [
              Text(
                Formatters.change(index.change),
                style: TextStyle(color: color, fontSize: 11),
              ),
              const SizedBox(width: 6),
              Text(
                Formatters.percent(index.changePercent),
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IndexGridSkeleton extends StatelessWidget {
  const _IndexGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.8,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => const _ShimmerCard(height: double.infinity),
    );
  }
}

class _NorthboundCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _NorthboundCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = (data['total_net'] ?? 0.0) as double;
    final sh = (data['sh_net'] ?? 0.0) as double;
    final sz = (data['sz_net'] ?? 0.0) as double;
    final color = total >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DataCell(
              label: '今日净流入',
              value: Formatters.largeNumber(total),
              color: color,
              large: true,
            ),
          ),
          Container(
            width: 0.5,
            height: 40,
            color: AppTheme.borderColor,
          ),
          Expanded(
            child: _DataCell(
              label: '沪股通',
              value: Formatters.largeNumber(sh),
              color: sh >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen,
            ),
          ),
          Container(
            width: 0.5,
            height: 40,
            color: AppTheme.borderColor,
          ),
          Expanded(
            child: _DataCell(
              label: '深股通',
              value: Formatters.largeNumber(sz),
              color: sz >= 0 ? AppTheme.accentGold : AppTheme.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool large;

  const _DataCell({
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: large ? 16 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EntrySignalTips extends StatelessWidget {
  const _EntrySignalTips();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.eco, color: AppTheme.accentGold, size: 16),
              const SizedBox(width: 8),
              Text(
                '建仓策略提示',
                style: TextStyle(
                  color: AppTheme.accentGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _TipRow(
            icon: Icons.arrow_downward,
            text: '指数跌幅 >2% 时，考虑第一批建仓',
          ),
          const SizedBox(height: 8),
          const _TipRow(icon: Icons.trending_down, text: '连续3日下跌，RSI<30 时可加仓'),
          const SizedBox(height: 8),
          const _TipRow(
            icon: Icons.check_circle_outline,
            text: '本金收回进度达50%时，复核一次回收计划',
          ),
          const SizedBox(height: 8),
          const _TipRow(icon: Icons.eco_outlined, text: '回收资金 ≥ 总成本 = 零成本持股达成'),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionTitle({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(subtitle!,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ],
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double height;
  const _ShimmerCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height == double.infinity ? null : height,
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.textMuted, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('重试',
                style: TextStyle(color: AppTheme.accent, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
