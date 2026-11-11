import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/tutorials_screen.dart';
import 'package:ghosst/services/models.dart';
import 'package:ghosst/theme.dart';

Tutorial _t({String title = 'How to deposit', String video = 'https://youtu.be/x'}) =>
    Tutorial(
      id: 1,
      title: title,
      slug: 'deposit',
      category: 'General',
      videoUrl: video,
      content: 'Step one\r\nStep two',
      views: 12,
      createdAt: '2026-01-01 00:00:00',
    );

void main() {
  testWidgets('lists the website tutorials and opens one', (tester) async {
    // Tall enough that the poster, button and body are all built.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: TutorialsScreen(load: () async => [_t()]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('How to deposit'), findsOneWidget);
    expect(find.text('12 reads'), findsOneWidget);
    expect(find.text('GENERAL'), findsOneWidget);

    await tester.tap(find.text('How to deposit'));
    await tester.pumpAndSettle();

    expect(find.text('Watch tutorial'), findsOneWidget);
    expect(find.text('Step one\nStep two'), findsOneWidget);
  });

  testWidgets('a text-only tutorial has no video button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: TutorialDetailScreen(tutorial: _t(video: '')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Watch tutorial'), findsNothing);
    expect(find.text('Step one\nStep two'), findsOneWidget);
  });
}
