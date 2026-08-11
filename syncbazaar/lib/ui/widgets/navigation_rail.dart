import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';
import '../../core/routing/app_router.dart';

/// Width of the rail when labels are showing. Sized to the longest label
/// ("Pending Approvals") plus its icon and a count chip.
const double _expandedWidth = 232;

/// Icon-only width: a 40px hit target centred in 18px of gutter either side.
const double _collapsedWidth = 76;

const double _rowHeight = 40;

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

/// A titled run of destinations.
///
/// [label] is null for the opening group — the two entries you land on rather
/// than navigate to, which need no heading to explain them.
class AppNavGroup {
  const AppNavGroup({this.label, required this.items});

  final String? label;
  final List<AppNavItem> items;
}

/// The app's primary navigation.
///
/// Rebuilt around three findings from how sidebars are actually read:
///
/// 1. **Ten identical rows have no hierarchy.** Every destination carried the
///    same weight, size and colour, so the eye had nowhere to land and the
///    whole list had to be re-read on every visit. Destinations are now
///    grouped by *when in the job you need them* — the bazaar lifecycle in
///    the order it happens, then the records it produces, then administration
///    — with a heading over each run. Groups are 2-3 items, inside the span
///    people can take in without counting.
/// 2. **Notifications belong where the work is.** They used to be a bell in a
///    64px top bar that held nothing else. Folding them in as a destination
///    lets that bar go away entirely and puts "what needs me" beside "where
///    do I go", which is the same question.
/// 3. **A count is hierarchy.** Rows that are waiting on the user say so, so
///    attention is drawn by state rather than by position alone.
class SideNavigationRail extends StatelessWidget {
  const SideNavigationRail({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelect,
    required this.isCollapsed,
    required this.onToggle,
    required this.onLogout,
    required this.isSyncing,
    required this.syncMessage,
    required this.onSync,
    this.badges = const {},
  });

  final List<AppNavGroup> groups;
  final AppSection selected;
  final ValueChanged<AppSection> onSelect;
  final bool isCollapsed;
  final VoidCallback onToggle;
  final VoidCallback onLogout;

  /// Live counts keyed by destination. Kept out of [AppNavItem] so the item
  /// list stays a description of the app's structure — built once — while the
  /// numbers on it can change on every rebuild.
  final Map<AppSection, int> badges;

  final bool isSyncing;
  final String syncMessage;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final targetWidth = isCollapsed ? _collapsedWidth : _expandedWidth;

    return AnimatedContainer(
      duration: AppMotion.small,
      curve: AppMotion.easeOut,
      width: targetWidth,
      color: AppColors.primary,
      // While the container animates between the two widths it is briefly
      // narrower than whichever layout is being shown, and the brand row's
      // fixed parts — logo, toggle, padding — cannot compress below about
      // 100px. Laying the content out at its *destination* width and clipping
      // the overhang keeps the transition free of overflow, and reads better
      // besides: the labels slide into view instead of being squeezed.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: targetWidth,
          maxWidth: targetWidth,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Brand(isCollapsed: isCollapsed, onToggle: onToggle),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (var i = 0; i < groups.length; i++)
                        ..._group(groups[i], isFirst: i == 0),
                    ],
                  ),
                ),
                _SyncStatus(
                  isCollapsed: isCollapsed,
                  isSyncing: isSyncing,
                  message: syncMessage,
                  onSync: onSync,
                ),
                _FooterAction(
                  icon: Icons.logout_rounded,
                  label: 'Logout',
                  isCollapsed: isCollapsed,
                  onTap: onLogout,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _group(AppNavGroup group, {required bool isFirst}) {
    // A heading over one row is a label, not a group — and which destinations
    // a role can see decides that at runtime, so it can't be settled in the
    // item list. Below two items the separation carries the grouping on its
    // own.
    final showHeading =
        !isCollapsed && group.label != null && group.items.length > 1;

    return [
      if (!isFirst)
        if (isCollapsed)
          // No room for a heading, so the boundary itself has to carry the
          // grouping. Without this the collapsed rail is one undifferentiated
          // column of icons.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Divider(height: 1, thickness: 1, color: Color(0x24FFFFFF)),
          )
        else
          const SizedBox(height: 16),
      if (showHeading)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
          child: Text(
            group.label!.toUpperCase(),
            style: const TextStyle(
              color: Color(0x73FFFFFF),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ),
      for (final item in group.items)
        _NavRow(
          item: item,
          isSelected: item.section == selected,
          isCollapsed: isCollapsed,
          badgeCount: badges[item.section] ?? 0,
          onTap: () => onSelect(item.section),
        ),
    ];
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.isCollapsed, required this.onToggle});

  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/syncbazaar_icon_with_bg.png',
        width: 28,
        height: 28,
        fit: BoxFit.cover,
      ),
    );

    final toggle = _IconButton(
      icon: isCollapsed
          ? Icons.keyboard_double_arrow_right_rounded
          : Icons.keyboard_double_arrow_left_rounded,
      tooltip: isCollapsed ? 'Expand menu' : 'Collapse menu',
      onTap: onToggle,
    );

    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
        child: Column(children: [logo, const SizedBox(height: 10), toggle]),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
      child: Row(
        children: [
          logo,
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'SyncBazaar',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.1),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.item,
    required this.isSelected,
    required this.isCollapsed,
    required this.badgeCount,
    required this.onTap,
  });

  final AppNavItem item;
  final bool isSelected;
  final bool isCollapsed;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Unselected rows are deliberately dimmer than before (72% against 80%).
    // The selected pill only reads as "you are here" to the degree everything
    // around it recedes.
    final foreground = isSelected
        ? AppColors.primary
        : Colors.white.withValues(alpha: 0.72);

    final row = Material(
      color: isSelected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withValues(alpha: 0.1),
        onTap: onTap,
        child: SizedBox(
          height: _rowHeight,
          child: isCollapsed
              ? Center(
                  child: _IconWithDot(
                    icon: item.icon,
                    color: foreground,
                    showDot: badgeCount > 0,
                    isSelected: isSelected,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 18, color: foreground),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: foreground,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (badgeCount > 0) ...[
                        const SizedBox(width: 8),
                        _CountChip(count: badgeCount, isSelected: isSelected),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCollapsed ? 18 : 10,
        vertical: 2,
      ),
      // Collapsed to icons, the label is the only thing that says where a row
      // goes — so it has to be recoverable on hover rather than remembered.
      child: isCollapsed
          ? Tooltip(
              message: badgeCount > 0
                  ? '${item.label} ($badgeCount)'
                  : item.label,
              child: row,
            )
          : row,
    );
  }
}

/// Count as a pill, in the right-hand column every row shares.
///
/// Pinned to the icon it would sit at an inconsistent x down the list; at the
/// row's trailing edge the counts line up, so "is anything waiting?" is one
/// glance down a column rather than a scan of ten rows.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.isSelected});

  final int count;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

/// The collapsed rail's badge: a dot at the icon's top-right, which is where
/// people already look for one.
class _IconWithDot extends StatelessWidget {
  const _IconWithDot({
    required this.icon,
    required this.color,
    required this.showDot,
    required this.isSelected,
  });

  final IconData icon;
  final Color color;
  final bool showDot;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 18, color: color),
        if (showDot)
          Positioned(
            top: -3,
            right: -4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                shape: BoxShape.circle,
                // A ring so the dot stays legible against both the purple
                // rail and the white selected pill.
                border: Border.all(
                  color: isSelected ? Colors.white : AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Sync state, moved down here from the top bar it used to share with the
/// notification bell — and now the control as well as the readout.
///
/// Settings had a separate "Sync now" button while the status of that same
/// sync lived somewhere else entirely, so you pressed in one place and watched
/// in another. The status line is the obvious thing to press; putting the
/// action on it removes the round trip and the duplicate.
///
/// It sits above Logout because both concern the session rather than where you
/// are in the app.
class _SyncStatus extends StatelessWidget {
  const _SyncStatus({
    required this.isCollapsed,
    required this.isSyncing,
    required this.message,
    required this.onSync,
  });

  final bool isCollapsed;
  final bool isSyncing;
  final String message;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    // Disabled mid-sync rather than queueing a second pass, and the icon spins
    // so the disabled state reads as "already working" instead of "broken".
    final enabled = !isSyncing;
    final tooltip = isSyncing ? message : '$message  ·  Tap to sync now';

    final icon = _SyncIcon(isSyncing: isSyncing);

    final body = isCollapsed
        ? SizedBox(height: 32, child: Center(child: icon))
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 18 : 10),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled ? onSync : null,
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.white.withValues(alpha: 0.1),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Spins for as long as a sync is running.
///
/// A plain swap to a static `sync` glyph left the rail looking identical
/// whether the sync took 50ms or ten seconds; rotation is the only part of
/// this that reports progress.
class _SyncIcon extends StatefulWidget {
  const _SyncIcon({required this.isSyncing});

  final bool isSyncing;

  @override
  State<_SyncIcon> createState() => _SyncIconState();
}

class _SyncIconState extends State<_SyncIcon>
    with SingleTickerProviderStateMixin {
  // Built in initState rather than as a `late final` initialiser: idle, the
  // field would never be touched, so `dispose()` would be the first read and
  // would construct a controller against an already-deactivated element.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isSyncing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _SyncIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSyncing == oldWidget.isSyncing) return;
    if (widget.isSyncing) {
      _controller.repeat();
    } else {
      // Stop where it is rather than snapping back to zero.
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.isSyncing ? Icons.sync_rounded : Icons.cloud_done_outlined,
      size: 15,
      color: Colors.white.withValues(alpha: 0.6),
    );
    if (!widget.isSyncing) return icon;
    return RotationTransition(turns: _controller, child: icon);
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.isCollapsed,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withValues(alpha: 0.1),
        child: SizedBox(
          height: _rowHeight,
          child: isCollapsed
              ? Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: 18,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 18 : 10),
      child: isCollapsed ? Tooltip(message: label, child: content) : content,
    );
  }
}
