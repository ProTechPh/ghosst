import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/announcements_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('lists past announcements and opens one', (tester) async {
    final items = [
      const Announcement(id: 'a2', title: 'Bagong stock', body: 'Netflix — 1 Month'),
      const Announcement(id: 'a1', title: 'Maintenance', body: 'Maya-maya lang babalik.'),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AnnouncementsScreen(load: () async => items),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bagong stock'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);

    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();

    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Maya-maya lang babalik.'), findsWidgets);
  });

  testWidgets('an empty history says so', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AnnouncementsScreen(load: () async => const []),
    ));
    await tester.pumpAndSettle();

    expect(find.text("There's no announcement yet."), findsOneWidget);
  });
}
