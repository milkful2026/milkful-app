import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_bloc.dart';
import 'package:milkful_app/features/onboarding/bloc/registration_event.dart';
import 'package:milkful_app/features/onboarding/presentation/consent_screen.dart';

import '../../../fakes/fake_draft_storage.dart';
import '../../../fakes/fake_registration_repository.dart';

void main() {
  Future<RegistrationBloc> pumpConsent(WidgetTester tester) async {
    final bloc = RegistrationBloc(
      repository: FakeRegistrationRepository(),
      draftStorage: FakeDraftStorage(),
    );
    addTearDown(() => bloc.close());
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RegistrationBloc>.value(value: bloc, child: const ConsentScreen()),
      ),
    );
    return bloc;
  }

  FilledButton submitButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Complete registration'));

  testWidgets('submit is disabled until both mandatory consents are checked', (tester) async {
    await pumpConsent(tester);

    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('submit stays disabled with only one of the two mandatory consents', (
    tester,
  ) async {
    await pumpConsent(tester);

    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('submit is enabled once both mandatory consents are checked', (tester) async {
    await pumpConsent(tester);

    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent-privacy')));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('the optional push-notifications consent does not gate submit', (tester) async {
    final bloc = await pumpConsent(tester);

    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('consent-privacy')));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNotNull);
    expect(bloc.state.draft.pushConsent, isFalse);
  });

  testWidgets('an unchecked consent can be re-unchecked, disabling submit again', (tester) async {
    final bloc = RegistrationBloc(
      repository: FakeRegistrationRepository(),
      draftStorage: FakeDraftStorage(),
    );
    addTearDown(() => bloc.close());
    bloc.add(
      const ConsentUpdated(termsAccepted: true, privacyAccepted: true, pushConsent: false),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<RegistrationBloc>.value(value: bloc, child: const ConsentScreen()),
      ),
    );
    await tester.pump();

    expect(submitButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('consent-terms')));
    await tester.pump();

    expect(submitButton(tester).onPressed, isNull);
  });
}
