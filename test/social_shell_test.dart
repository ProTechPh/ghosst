import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

Future<void> _pumpBar(WidgetTester tester, {required FiveTabBar bar}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(bottomNavigationBar: bar),
    ),
  );
}

void main() {
  test('SocialTab maps pages and excludes Create', () {
    expect(SocialTab.home.pageIndex, 0);
    expect(SocialTab.shop.pageIndex, 1);
    expect(SocialTab.inbox.pageIndex, 2);
    expect(SocialTab.profile.pageIndex, 3);
    expect(SocialTab.create.pageIndex, -1);
  });

  testWidgets('FiveTabBar renders five ordered labels and selected semantics', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      bar: FiveTabBar(
        selected: SocialTab.home,
        onSelected: (_) {},
        onCreate: () {},
      ),
    );

    const labels = ['Home', 'Shop', 'Create', 'Inbox', 'Profile'];
    double? previousX;
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      final x = tester.getCenter(find.text(label)).dx;
      if (previousX != null) expect(x, greaterThan(previousX));
      previousX = x;
    }

    final home = tester.widget<Semantics>(
      find.byKey(const ValueKey('social-tab-semantics-home')),
    );
    final shop = tester.widget<Semantics>(
      find.byKey(const ValueKey('social-tab-semantics-shop')),
    );
    expect(home.properties.selected, isTrue);
    expect(shop.properties.selected, isFalse);
  });

  testWidgets('FiveTabBar uses 48dp targets and shows Inbox unread', (
    tester,
  ) async {
    await _pumpBar(
      tester,
      bar: FiveTabBar(
        selected: SocialTab.inbox,
        onSelected: (_) {},
        onCreate: () {},
        unread: const {SocialTab.inbox: 3},
      ),
    );

    for (final tab in SocialTab.values) {
      final size = tester.getSize(
        find.byKey(ValueKey('social-tab-${tab.name}')),
      );
      expect(size.width, greaterThanOrEqualTo(kTouchMin));
      expect(size.height, greaterThanOrEqualTo(kTouchMin));
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('social-tab-inbox')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Create calls only onCreate and other tabs call onSelected', (
    tester,
  ) async {
    SocialTab? selected;
    var createCalls = 0;
    await _pumpBar(
      tester,
      bar: FiveTabBar(
        selected: SocialTab.home,
        onSelected: (tab) => selected = tab,
        onCreate: () => createCalls++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-tab-create')));
    expect(createCalls, 1);
    expect(selected, isNull);

    await tester.tap(find.byKey(const ValueKey('social-tab-inbox')));
    expect(selected, SocialTab.inbox);
    expect(createCalls, 1);
  });

  testWidgets('SocialAppBar is black, left-aligned, and toolbar-sized', (
    tester,
  ) async {
    const bar = SocialAppBar(title: 'Wallet');
    expect(bar.preferredSize.height, kToolbarHeight);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(appBar: bar)));

    expect(find.text('Wallet'), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.black);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(appBar.elevation, 0);
    expect(appBar.centerTitle, isFalse);
  });
}
