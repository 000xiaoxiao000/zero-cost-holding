import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'watchlist_screen.dart';
import 'holding_tracker_screen.dart';
import 'seed_plan_screen.dart';
import 'harvest_calculator_screen.dart';
import 'seed_screening_screen.dart';
import 'strategy_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 5个底部标签：自选 / 排雷 / 计划 / 持仓 / 策略
  int _currentIndex = 2; // 默认进入「计划」

  // "计划"标签内的子页面 tab（0=播种 1=收割）
  int _planSubIndex = 0;

  Widget get _currentPage {
    switch (_currentIndex) {
      case 0:
        return const WatchlistScreen(key: ValueKey('tab-watchlist'));
      case 1:
        return const SeedScreeningScreen(key: ValueKey('tab-screen'));
      case 2:
        return _PlanTabPage(
          key: const ValueKey('tab-plan'),
          subIndex: _planSubIndex,
          onSubIndexChanged: (i) => setState(() => _planSubIndex = i),
        );
      case 3:
        return const HoldingTrackerScreen(key: ValueKey('tab-holding'));
      case 4:
        return const StrategyScreen(key: ValueKey('tab-strategy'));
      default:
        return _PlanTabPage(
          key: const ValueKey('tab-plan'),
          subIndex: _planSubIndex,
          onSubIndexChanged: (i) => setState(() => _planSubIndex = i),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentPage,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppTheme.borderColor, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark_outline),
              activeIcon: Icon(Icons.bookmark),
              label: '自选',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.health_and_safety_outlined),
              activeIcon: Icon(Icons.health_and_safety),
              label: '排雷',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grass_outlined),
              activeIcon: Icon(Icons.grass),
              label: '计划',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet),
              label: '持仓',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rule_outlined),
              activeIcon: Icon(Icons.rule),
              label: '策略',
            ),
          ],
        ),
      ),
    );
  }
}

/// "计划"标签页：顶部双 Tab 切换播种计划 / 收割计算
class _PlanTabPage extends StatelessWidget {
  final int subIndex;
  final ValueChanged<int> onSubIndexChanged;

  const _PlanTabPage({
    super.key,
    required this.subIndex,
    required this.onSubIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部安全区 + 标签切换条
        Container(
          color: AppTheme.bgCard,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            bottom: 10,
          ),
          child: Row(
            children: [
              Expanded(
                child: _PlanSubTab(
                  icon: Icons.grass_outlined,
                  label: '播种计划',
                  selected: subIndex == 0,
                  onTap: () => onSubIndexChanged(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PlanSubTab(
                  icon: Icons.auto_graph_outlined,
                  label: '收割计算',
                  selected: subIndex == 1,
                  onTap: () => onSubIndexChanged(1),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: subIndex,
            children: const [
              _SeedPlanBody(),
              _HarvestBody(),
            ],
          ),
        ),
      ],
    );
  }
}

/// 用 StatefulWidget 包一层，保持各子页面状态不丢失
class _SeedPlanBody extends StatefulWidget {
  const _SeedPlanBody();
  @override
  State<_SeedPlanBody> createState() => _SeedPlanBodyState();
}

class _SeedPlanBodyState extends State<_SeedPlanBody> {
  @override
  Widget build(BuildContext context) => const SeedPlanScreen();
}

class _HarvestBody extends StatefulWidget {
  const _HarvestBody();
  @override
  State<_HarvestBody> createState() => _HarvestBodyState();
}

class _HarvestBodyState extends State<_HarvestBody> {
  @override
  Widget build(BuildContext context) => const HarvestCalculatorScreen();
}

class _PlanSubTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PlanSubTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : AppTheme.bgCardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected ? AppTheme.accent : AppTheme.borderColor,
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
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
