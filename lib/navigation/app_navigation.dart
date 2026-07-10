import 'package:flutter/material.dart';

enum HomeTab {
  watchlist(0, '选股', Icons.bookmark_outline),
  screening(1, '排雷', Icons.health_and_safety_outlined),
  plan(2, '计划', Icons.grass_outlined),
  holding(3, '持仓', Icons.account_balance_wallet_outlined),
  strategy(4, '策略', Icons.rule_outlined);

  final int tabIndex;
  final String label;
  final IconData icon;

  const HomeTab(this.tabIndex, this.label, this.icon);
}

class AppNavigation {
  static final tabRequests = ValueNotifier<HomeTab?>(null);

  static void goHomeTab(BuildContext context, HomeTab tab) {
    tabRequests.value = tab;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class HomeTabMenuButton extends StatelessWidget {
  const HomeTabMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HomeTab>(
      tooltip: '跳转',
      icon: const Icon(Icons.apps_outlined),
      onSelected: (tab) => AppNavigation.goHomeTab(context, tab),
      itemBuilder: (_) => HomeTab.values
          .map(
            (tab) => PopupMenuItem<HomeTab>(
              value: tab,
              child: Row(
                children: [
                  Icon(tab.icon, size: 18),
                  const SizedBox(width: 10),
                  Text(tab.label),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
