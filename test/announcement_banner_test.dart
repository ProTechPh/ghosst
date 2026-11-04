import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/announcement_banner.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('shows the announcement and dismisses', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: AnnouncementBanner(
          announcement: const Announcement(id: 'a1', title: 'Bagong stock', body: 'Netflix — 1 Month'),
          onDismiss: () => dismissed++,
        ),
      ),
    ));

    expect(find.text('Bagong stock'), findsOneWidget);
    expect(find.text('Netflix — 1 Month'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow on a 320px phone

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(dismissed, 1);
  });
}
