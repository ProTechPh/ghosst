import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghosst/premium.dart';
import 'package:ghosst/screens/splash_screen.dart';
import 'package:ghosst/sign_in.dart';
import 'package:ghosst/sign_up.dart';
import 'package:ghosst/theme.dart';
import 'package:ghosst/validation.dart';

void main() {
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

  testWidgets('splash plays its timeline then completes', (tester) async {
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SplashScreen(onDone: () => done = true),
      ),
    );

    // Run the full intro; outro is still in flight when the finish timer fires.
    await tester.pump(const Duration(milliseconds: 2600));
    expect(done, isFalse);

    await tester.pump(const Duration(milliseconds: 600));
    expect(done, isTrue);

    await tester.pumpWidget(const SizedBox()); // detach before teardown
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
    await tester.pump(); // first ticker frame — starts the outro clock
    await tester.pump(const Duration(milliseconds: 600)); // > 480ms outro
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
        find.widgetWithText(IslandButton, 'Create account'));
    await tester.pump(); // let the scroll offset hit layout
    await tester.tap(find.widgetWithText(IslandButton, 'Create account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Email is required'), findsNothing);
    expect(find.text('Minimum 8 characters'), findsNothing); // hint swapped out
  });

  testWidgets('sign-in rejects a password below the Appwrite minimum',
      (tester) async {
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
      friendlyAuthError('A user with the same id already exists',
          fallback: 'Sign up failed'),
      'An account with this email already exists',
    );
    expect(
      friendlyAuthError('Invalid credentials',
          fallback: 'Sign in failed'),
      'Incorrect email or password',
    );
    expect(friendlyAuthError('', fallback: 'Sign in failed'),
        'Sign in failed');
    expect(
      friendlyAuthError('something new from the server',
          fallback: 'Sign in failed'),
      'something new from the server', // unmapped messages pass through
    );
  });
}
