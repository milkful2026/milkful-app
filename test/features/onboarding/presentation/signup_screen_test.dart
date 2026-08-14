import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/auth/bloc/auth_bloc.dart';
import 'package:milkful_app/features/onboarding/presentation/signup_screen.dart';

import '../../../fakes/fake_auth_repository.dart';
import '../../../fakes/fake_secure_token_storage.dart';

void main() {
  Future<void> pumpSignup(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => AuthBloc(
            authRepository: FakeAuthRepository(),
            tokenStorage: FakeSecureTokenStorage(),
          ),
          child: const SignupScreen(),
        ),
      ),
    );
  }

  testWidgets('Send OTP is disabled for fewer than 10 digits', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '98765');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send OTP'));
    expect(button.onPressed, isNull);
  });

  testWidgets('Send OTP is enabled once exactly 10 digits are entered', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '9876543210');
    await tester.pump();

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send OTP'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('non-digit characters are filtered out of the mobile field', (tester) async {
    await pumpSignup(tester);

    await tester.enterText(find.bySemanticsLabel('Mobile number'), '98a76!54@321#0');
    await tester.pump();

    expect(find.text('9876543210'), findsOneWidget);
  });
}
