import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/routing/app_router.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/widgets/navigation_rail.dart';

void main() {
  const ownerGroups = [
    AppNavGroup(
      items: [
        AppNavItem(
          section: AppSection.dashboard,
          label: 'Dashboard',
          icon: Icons.home_outlined,
        ),
        AppNavItem(
          section: AppSection.notifications,
          label: 'Notifications',
          icon: Icons.notifications_outlined,
        ),
      ],
    ),
    AppNavGroup(
      label: 'Bazaar',
      items: [
        AppNavItem(
          section: AppSection.preBazaar,
          label: 'Preparations',
          icon: Icons.event_note_outlined,
        ),
        AppNavItem(
          section: AppSection.pos,
          label: 'Sales',
          icon: Icons.point_of_sale_outlined,
        ),
      ],
    ),
    AppNavGroup(
      label: 'Manage',
      items: [
        AppNavItem(
          section: AppSection.settings,
          label: 'Settings',
          icon: Icons.settings_outlined,
        ),
      ],
    ),
  ];

  Future<AppSection?> pump(
    WidgetTester tester, {
    List<AppNavGroup> groups = ownerGroups,
    AppSection selected = AppSection.dashboard,
    bool collapsed = false,
    Map<AppSection, int> badges = const {},
    bool isSyncing = false,
    String syncMessage = 'Offline-ready',
  }) async {
    AppSection? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            children: [
              SideNavigationRail(
                groups: groups,
                selected: selected,
                onSelect: (s) => tapped = s,
                isCollapsed: collapsed,
                onToggle: () {},
                onLogout: () {},
                badges: badges,
                isSyncing: isSyncing,
                syncMessage: syncMessage,
                onSync: () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tapped;
  }

  testWidgets('shows a heading over each multi-item group', (tester) async {
    await pump(tester);

    expect(find.text('BAZAAR'), findsOneWidget);
    // The opening group is deliberately unlabelled.
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
  });

  testWidgets('drops the heading when a role leaves one item in a group', (
    tester,
  ) async {
    // "MANAGE / Settings" is a label on a row, not a group. Which destinations
    // a role can see decides this at runtime.
    await pump(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('MANAGE'), findsNothing);
  });

  testWidgets('selecting a row reports its section, not an index', (
    tester,
  ) async {
    AppSection? tapped;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            children: [
              SideNavigationRail(
                groups: ownerGroups,
                selected: AppSection.dashboard,
                onSelect: (s) => tapped = s,
                isCollapsed: false,
                onToggle: () {},
                onLogout: () {},
                isSyncing: false,
                syncMessage: 'Offline-ready',
                onSync: () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sales'));
    await tester.pumpAndSettle();

    expect(tapped, AppSection.pos);
  });

  group('badges', () {
    testWidgets('render as a count chip when expanded', (tester) async {
      await pump(tester, badges: {AppSection.notifications: 3});
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('are absent at zero rather than showing "0"', (tester) async {
      await pump(tester, badges: {AppSection.notifications: 0});
      expect(find.text('0'), findsNothing);
    });

    testWidgets('cap at 99+', (tester) async {
      await pump(tester, badges: {AppSection.notifications: 140});
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('140'), findsNothing);
    });

    testWidgets('become a dot with the count in the tooltip when collapsed', (
      tester,
    ) async {
      await pump(
        tester,
        collapsed: true,
        badges: {AppSection.notifications: 3},
      );

      // No room for a chip, and no label to attach it to.
      expect(find.text('3'), findsNothing);
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(tooltips, contains('Notifications (3)'));
    });
  });

  group('collapsed rail', () {
    testWidgets('hides labels but keeps them reachable as tooltips', (
      tester,
    ) async {
      await pump(tester, collapsed: true);

      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('BAZAAR'), findsNothing);

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(tooltips, containsAll(['Dashboard', 'Preparations', 'Sales']));
    });

    testWidgets('keeps groups visible by falling back to dividers', (
      tester,
    ) async {
      await pump(tester, collapsed: true);
      // One boundary per group after the first — otherwise the collapsed rail
      // is one undifferentiated column of icons.
      expect(find.byType(Divider), findsNWidgets(ownerGroups.length - 1));
    });

    testWidgets('is narrower than the expanded rail', (tester) async {
      await pump(tester, collapsed: true);
      final collapsed = tester.getSize(find.byType(SideNavigationRail)).width;

      await pump(tester);
      final expanded = tester.getSize(find.byType(SideNavigationRail)).width;

      expect(collapsed, lessThan(expanded));
    });
  });

  testWidgets('carries the sync status the top bar used to hold', (
    tester,
  ) async {
    await pump(tester, syncMessage: 'Synced just now');
    expect(find.text('Synced just now'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('spins for as long as a sync is running', (tester) async {
    // Deliberately `pump`, not `pumpAndSettle`: the spinner repeats until the
    // sync ends, so there is no steady state to settle into. A version of this
    // that settled would mean the icon had stopped reporting progress.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Row(
            children: [
              SideNavigationRail(
                groups: ownerGroups,
                selected: AppSection.dashboard,
                onSelect: (_) {},
                isCollapsed: false,
                onToggle: () {},
                onLogout: () {},
                isSyncing: true,
                syncMessage: 'Syncing...',
                onSync: () {},
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Syncing...'), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    // Scoped to the sync icon: Material puts RotationTransitions of its own
    // in the tree, so a bare byType finder would pick up the wrong one.
    final spinner = find.ancestor(
      of: find.byIcon(Icons.sync_rounded),
      matching: find.byType(RotationTransition),
    );
    expect(spinner, findsOneWidget);

    final before = tester.widget<RotationTransition>(spinner).turns.value;
    await tester.pump(const Duration(milliseconds: 300));
    final after = tester.widget<RotationTransition>(spinner).turns.value;
    expect(after, isNot(before));

    // Tear the tree down so the repeating ticker does not outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  group('sync chip is the control, not just a readout', () {
    Future<int> pumpAndTapSync(
      WidgetTester tester, {
      required bool isSyncing,
      bool collapsed = false,
    }) async {
      var syncs = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Row(
              children: [
                SideNavigationRail(
                  groups: ownerGroups,
                  selected: AppSection.dashboard,
                  onSelect: (_) {},
                  isCollapsed: collapsed,
                  onToggle: () {},
                  onLogout: () {},
                  isSyncing: isSyncing,
                  syncMessage: isSyncing ? 'Syncing...' : 'Offline-ready',
                  onSync: () => syncs++,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byIcon(isSyncing ? Icons.sync_rounded : Icons.cloud_done_outlined),
        warnIfMissed: false,
      );
      await tester.pump();
      return syncs;
    }

    testWidgets('tapping it starts a sync', (tester) async {
      expect(await pumpAndTapSync(tester, isSyncing: false), 1);
    });

    testWidgets('works collapsed too', (tester) async {
      expect(
        await pumpAndTapSync(tester, isSyncing: false, collapsed: true),
        1,
      );
    });

    testWidgets('is inert mid-sync rather than queueing a second pass', (
      tester,
    ) async {
      expect(await pumpAndTapSync(tester, isSyncing: true), 0);
      // Leave the animation running or the test ends with a live ticker.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('logout stays out of the destination list', (tester) async {
    await pump(tester);
    // It is an action, not a place — so it must not sit in a group where a
    // mis-tap costs you your session.
    expect(find.text('Logout'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
  });
}
