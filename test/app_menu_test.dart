import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/app_menu.dart';
import 'package:ghosst/theme.dart';

void main() {
  testWidgets('app menu uses themed icon rows and dispatches selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              AppMenuButton<String>(
                key: const ValueKey('test-menu'),
                items: const [
                  AppMenuItem(
                    value: 'settings',
                    label: 'Settings',
                    icon: Icons.settings_outlined,
                  ),
                  AppMenuItem(
                    value: 'keys',
                    label: 'Keys',
                    icon: Icons.key_outlined,
                  ),
                ],
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('test-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.key_outlined), findsOneWidget);

    await tester.tap(find.text('Keys'));
    await tester.pumpAndSettle();
    expect(selected, 'keys');
  });
}
