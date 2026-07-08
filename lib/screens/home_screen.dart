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
  int _currentIndex = 0;

  Widget get _currentPage {
    late final Widget page;
    switch (_currentIndex) {
      case 0:
        page = const SeedPlanScreen();
        break;
      case 1:
        page = const HarvestCalculatorScreen();
        break;
      case 2:
        page = const WatchlistScreen();
        break;
      case 3:
        page = const HoldingTrackerScreen();
        break;
      case 4:
        page = const SeedScreeningScreen();
        break;
      case 5:
        page = const StrategyScreen();
        break;
      default:
        page = const SeedPlanScreen();
    }
    return KeyedSubtree(
      key: ValueKey('tab-$_currentIndex'),
      child: page,
    );
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
              icon: Icon(Icons.grass_outlined),
              label: '播种',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_graph_outlined),
              label: '收割',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bookmark_outline),
              label: '自选',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              label: '持仓',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.health_and_safety_outlined),
              label: '排雷',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rule_outlined),
              label: '策略',
            ),
          ],
        ),
      ),
    );
  }
}
