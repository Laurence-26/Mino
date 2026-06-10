import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pesa_tools/110n/app_translations.dart';
import 'package:pesa_tools/screens/analytics/analytics_screen.dart';

import 'dashboard/dashboard_screen.dart';
import 'transactions/transactions_screen.dart';
import 'reports/reports_screen.dart';
import 'groups/groups_screen.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  int _selectedIndex = 0;

  // Remove AnalyticsScreen
  static const List<Widget> _screens = [
    DashboardScreen(),
    TransactionsScreen(),
    ReportsScreen(),
    AnalysisScreen(),
    GroupsScreen(),
  ];

  // Remove analytics item from navItems
  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'dashboard'),
    _NavItem(icon: Icons.list_alt_outlined, selectedIcon: Icons.list_alt, label: 'transactions'),
    _NavItem(icon: Icons.pie_chart_outline, selectedIcon: Icons.pie_chart, label: 'reports'),
    _NavItem(icon: Icons.analytics_outlined, selectedIcon: Icons.analytics_rounded, label: 'analysis'),
    _NavItem(icon: Icons.group_outlined, selectedIcon: Icons.group, label: 'groups'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final inactiveColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              // Generate 4 items now
              children: List.generate(5, (index) {
                final item = _navItems[index];
                final isSelected = _selectedIndex == index;

                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!isSelected) {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedIndex = index);
                      }
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Modern top indicator
                        SizedBox(
                          height: 4,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              width: isSelected ? 26 : 0,
                              height: 3.5,
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Icon with lift + scale
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          transform: Matrix4.translationValues(0, isSelected ? -6 : 0, 0),
                          child: AnimatedScale(
                            scale: isSelected ? 1.25 : 1.0,
                            duration: const Duration(milliseconds: 350),
                            child: Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              color: isSelected ? primary : inactiveColor,
                              size: 29,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Label appears only on selected tab
                        SizedBox(
                          height: 18,
                          child: AnimatedOpacity(
                            opacity: isSelected ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              AppTranslations.of(context, item.label),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: primary,
                                letterSpacing: 0.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}