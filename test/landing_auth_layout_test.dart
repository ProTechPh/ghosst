import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/screens/landing_screen.dart';
import 'package:ghosst/sign_in.dart';
import 'package:ghosst/theme.dart';

// The signed-out screens are the first thing a new user sees; a RenderFlex
// overflow on a small phone fails these tests on its own.
void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('landing fits a 320px phone', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: LandingScreen(onSignIn: () {}, onGoogleSignedIn: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Watch ads.'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in with email'), findsOneWidget);
  });

  testWidgets('sign in fits a 320px phone', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SignIn(onSignedIn: () {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Sign in'), findsNWidgets(2)); // header + submit
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Your password'), findsOneWidget);
  });
}
