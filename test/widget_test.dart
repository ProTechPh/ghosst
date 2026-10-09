import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/screens/splash_screen.dart';
import 'package:ghosst/sign_in.dart';
import 'package:ghosst/sign_up.dart';
import 'package:ghosst/theme.dart';
import 'package:ghosst/validation.dart';

void main() {
  /// Opacity of the "TAP TO SKIP" hint — its ramp is the easiest read on
  /// whether the intro timeline is actually advancing.
  double skipHintOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find.ancestor(
          of: find.text('TAP TO SKIP'),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.child is Text,
          ),
        ),
      )
      .opacity;

  testWidgets('premium primitives render', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const Eyebrow(text: 'Hello'),
                DoubleBezel(child: const Text('inner core')),
                IslandButton(label: 'Claim', onPressed: () {}),
                const AnimatedCounter(value: 1234),
                const ScrollReveal(child: Text('revealed')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('HELLO'), findsOneWidget);
    expect(find.text('inner core'), findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('revealed'), findsOneWidget);

    // Counter settles on the formatted end value.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('1,234'), findsOneWidget);
  });

  testWidgets('splash plays its full timeline before lifting', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SplashScreen(onDone: () => done = true),
      ),
    );

    // Early intro: the skip hint is still hidden — the timeline has begun.
    await tester.pump(const Duration(milliseconds: 500));
    expect(skipHintOpacity(tester), 0);
    expect(done, isFalse);

    // Late intro: it fades in as the timeline advances frame by frame. (It
    // used to stay pinned at 0 — nothing listened to the controllers, so the
    // splash froze on frame 0 and then got cut.)
    await tester.pump(const Duration(milliseconds: 2000)); // t = 2500ms
    expect(skipHintOpacity(tester), greaterThan(0.5));
    expect(done, isFalse);

    // Intro completes on this frame → the hold beat starts (900ms).
    await tester.pump(const Duration(milliseconds: 150)); // t = 2650ms
    expect(done, isFalse);

    // Hold ends, exit begins — the finished frame was never cut short.
    await tester.pump(const Duration(milliseconds: 900)); // t = 3550ms
    expect(done, isFalse);

    // Exit (720ms) completes.
    await tester.pump(const Duration(milliseconds: 900)); // t = 4450ms
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox()); // detach before teardown
  });

  testWidgets('splash waits for onReady before lifting', (tester) async {
    var done = false;
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SplashScreen(
          onReady: () => gate.future,
          onDone: () => done = true,
        ),
      ),
    );

    // Intro + hold are over, but the app underneath is not ready: the
    // finished frame is HELD instead of the splash being torn away.
    await tester.pump(const Duration(milliseconds: 2650)); // hold running
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 900)); // exit waits
    expect(done, isFalse);

    gate.complete();
    await tester.pump(); // resume the exit
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900)); // > 720ms outro
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tap bails out of a slow onReady wait', (tester) async {
    var done = false;
    final gate = Completer<void>(); // never completed — a stalled check
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SplashScreen(
          onReady: () => gate.future,
          onDone: () => done = true,
        ),
      ),
    );

    // Intro + hold are over and the exit is parked on the gate.
    await tester.pump(const Duration(milliseconds: 2650));
    await tester.pump(const Duration(milliseconds: 900));
    expect(done, isFalse);

    // A tap releases it instead of hanging on a frozen screen.
    await tester.tap(find.byType(SplashScreen));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900)); // > 720ms outro
    expect(done, isTrue);
    expect(gate.isCompleted, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tap skips the splash early', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SplashScreen(onDone: () => done = true),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(SplashScreen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900)); // > 720ms outro
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sign-in flags empty fields on submit', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SignIn(onSignedIn: () {}, onGoToSignUp: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500)); // reveals settle

    await tester.ensureVisible(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump(); // let the scroll offset hit layout
    await tester.tap(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // field-error anim

    expect(find.text('Email is required'), findsOneWidget);
    expect(find.text('Password is required'), findsOneWidget);
  });

  testWidgets('sign-in rejects a malformed email', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SignIn(onSignedIn: () {}, onGoToSignUp: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextField).at(1), 'hunter2');
    await tester.ensureVisible(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump(); // let the scroll offset hit layout
    await tester.tap(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password is required'), findsNothing);
  });

  testWidgets('sign-up enforces the password minimum', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SignUp(onSignedUp: () {}, onGoToSignIn: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.enterText(find.byType(TextField).at(1), 'user@test.com');
    await tester.enterText(find.byType(TextField).at(2), 'short');
    await tester.ensureVisible(
      find.widgetWithText(IslandButton, 'Create account'),
    );
    await tester.pump(); // let the scroll offset hit layout
    await tester.tap(find.widgetWithText(IslandButton, 'Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Email is required'), findsNothing);
    expect(find.text('Minimum 8 characters'), findsNothing); // hint swapped out
  });

  testWidgets('sign-in rejects a password below the Appwrite minimum', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SignIn(onSignedIn: () {}, onGoToSignUp: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.enterText(find.byType(TextField).at(0), 'user@test.com');
    await tester.enterText(find.byType(TextField).at(1), 'hunter2'); // 7 chars
    await tester.ensureVisible(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump(); // let the scroll offset hit layout
    await tester.tap(find.widgetWithText(IslandButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsNothing);
  });

  test('auth errors are rewritten into friendly copy', () {
    // The exact raw message Appwrite returns for out-of-range passwords.
    expect(
      friendlyAuthError(
        'invalid password param must be between 8 and 256 char',
        fallback: 'Sign in failed',
      ),
      'Password must be between 8 and 256 characters',
    );
    expect(
      friendlyAuthError(
        'A user with the same id already exists',
        fallback: 'Sign up failed',
      ),
      'An account with this email already exists',
    );
    expect(
      friendlyAuthError('Invalid credentials', fallback: 'Sign in failed'),
      'Incorrect email or password',
    );
    expect(friendlyAuthError('', fallback: 'Sign in failed'), 'Sign in failed');
    expect(
      friendlyAuthError(
        'something new from the server',
        fallback: 'Sign in failed',
      ),
      'something new from the server', // unmapped messages pass through
    );
  });
}
