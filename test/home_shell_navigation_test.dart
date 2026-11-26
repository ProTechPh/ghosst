import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/social_shell.dart';
import 'package:ghosst/theme.dart';

void main() {
  test('social tabs map to four pages', () {
    expect(SocialTab.home.pageIndex, 0);
    expect(SocialTab.shop.pageIndex, 1);
    expect(SocialTab.inbox.pageIndex, 2);
    expect(SocialTab.profile.pageIndex, 3);
    expect(SocialTab.create.pageIndex, -1);
  });

  testWidgets('shell harness changes tabs but Create does not select a page', (
    tester,
  ) async {
    var selected = SocialTab.home;
    var createCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: FiveTabBar(
              selected: selected,
              onSelected: (tab) => setState(() => selected = tab),
              onCreate: () => createCalls++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('social-tab-create')));
    await tester.pump();
    expect(createCalls, 1);
    expect(selected, SocialTab.home);

    await tester.tap(find.byKey(const ValueKey('social-tab-inbox')));
    await tester.pump();
    expect(selected, SocialTab.inbox);
  });

  test('main shell has no legacy navigation code', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(r'\btab\s*=\s*\d+').hasMatch(source),
      isFalse,
      reason: 'Use SocialTab enum values instead of integer tab indexes.',
    );
    for (final residue in [
      '_GlassNavBar',
      '_NavItem',
      'FloatingActionButton',
      'Header entry point for News',
    ]) {
      expect(source.contains(residue), isFalse, reason: residue);
    }
  });
}
