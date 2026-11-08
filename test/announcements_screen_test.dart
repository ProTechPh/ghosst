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

  testWidgets('hidden tab does not fetch until activated', (tester) async {
    var calls = 0;
    Future<List<Announcement>> load() async {
      calls++;
      return const [
        Announcement(id: 'a1', title: 'Bagong stock', body: 'Netflix — 1 Month'),
      ];
    }

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AnnouncementsScreen(load: load, active: false),
    ));
    // Indeterminate spinner never settles — one frame is enough to prove
    // the fetch was not fired.
    await tester.pump();

    expect(calls, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AnnouncementsScreen(load: load, active: true),
    ));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Bagong stock'), findsOneWidget);
  });
}
