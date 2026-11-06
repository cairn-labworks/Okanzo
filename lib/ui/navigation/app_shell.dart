import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../asset/asset_edit_screen.dart';
import '../home/home_screen.dart';
import '../liability/liability_edit_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../settings/settings_screen.dart';
import '../statistics/statistics_screen.dart';

/// Top-level destinations shown in the bottom bar / navigation rail.
enum TopLevelDestination {
  home('Home', Icons.home, Icons.home_outlined),
  statistics('Statistics', Icons.pie_chart, Icons.pie_chart_outline),
  portfolios(
    'Portfolios',
    Icons.account_balance_wallet,
    Icons.account_balance_wallet_outlined,
  );

  const TopLevelDestination(this.label, this.selectedIcon, this.unselectedIcon);

  final String label;
  final IconData selectedIcon;
  final IconData unselectedIcon;
}

/// Adaptive shell: a navigation bar on compact widths and a navigation rail
/// from medium widths up, hosting the three top-level destinations.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  void _openAssetEditor(int portfolioId, int assetId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AssetEditScreen(portfolioId: portfolioId, assetId: assetId),
      ),
    );
  }

  void _openLiabilityEditor(int portfolioId, int liabilityId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiabilityEditScreen(
          portfolioId: portfolioId,
          liabilityId: liabilityId,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            SettingsScreen(onClose: () => Navigator.of(context).pop()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool useRail = MediaQuery.sizeOf(context).width >= 600;
    final Widget body = IndexedStack(
      index: _index,
      children: <Widget>[
        HomeScreen(
          onOpenAssetEditor: _openAssetEditor,
          onOpenLiabilityEditor: _openLiabilityEditor,
          onManagePortfolios: () =>
              _select(TopLevelDestination.portfolios.index),
          onOpenSettings: _openSettings,
        ),
        const StatisticsScreen(),
        const PortfolioScreen(),
      ],
    );

    if (!useRail) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: <Widget>[
            for (final TopLevelDestination destination
                in TopLevelDestination.values)
              NavigationDestination(
                icon: Icon(destination.unselectedIcon),
                selectedIcon: Icon(destination.selectedIcon),
                label: destination.label.tr(context),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: <NavigationRailDestination>[
              for (final TopLevelDestination destination
                  in TopLevelDestination.values)
                NavigationRailDestination(
                  icon: Icon(destination.unselectedIcon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label.tr(context)),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
