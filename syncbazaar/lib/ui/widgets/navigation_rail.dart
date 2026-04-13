import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/routing/app_router.dart';

class AppNavItem {
  const AppNavItem({
    required this.section,
    required this.label,
    required this.icon,
  });

  final AppSection section;
  final String label;
  final IconData icon;
}

class SideNavigationRail extends StatelessWidget {
  const SideNavigationRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.isCollapsed,
    required this.onToggle,
    required this.onLogout,
  });

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final sidebarWidth = isCollapsed ? 88.0 : 220.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: sidebarWidth,
      color: AppColors.primary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/icons/syncbazaar_icon_with_bg.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (!isCollapsed) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'SyncBazaar',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 40,
                      width: isCollapsed ? 40 : null,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      child: Icon(
                        Icons.menu,
                        color: isCollapsed ? Colors.white : AppColors.accent,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = index == selectedIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onSelect(index),
                        child: Container(
                          height: 40,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Icon(
                                item.icon,
                                size: 18,
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.white.withOpacity(0.8),
                              ),
                              if (!isCollapsed) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.white.withOpacity(0.8),
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onLogout,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          size: 18,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        if (!isCollapsed) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// For future custom nav icons:
// 1) Place files under assets/icons/ (e.g. nav_dashboard.png, nav_pos.png)
// 2) Register them in pubspec.yaml -> flutter -> assets
// 3) Replace Icon(item.icon) with Image.asset('assets/icons/nav_dashboard.png')
