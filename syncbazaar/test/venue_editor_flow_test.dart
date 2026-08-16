import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/bloc/settings/settings_cubit.dart';
import 'package:syncbazaar/data/repositories/settings_repository.dart';
import 'package:syncbazaar/models/user.dart';
import 'package:syncbazaar/ui/screens/venues/venues_screen.dart';

/// Adding a venue, end to end through the screen.
///
/// The editor is two steps and returns a draft; the screen turns that into a
/// createLocation call and the list rebuilds off cubit state. Several places
/// for a new venue to be lost between pressing Save and seeing it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const owner = AppUser(
    id: 2,
    name: 'Lalaine',
    email: 'owner@syncbazaar.com',
    role: UserRole.owner,
  );

  testWidgets('a venue added through the editor appears in the list', (
    tester,
  ) async {
    final cubit = SettingsCubit(SettingsRepository());
    await cubit.load();

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(body: VenuesScreen(user: owner)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = cubit.state.companies.length;

    await tester.tap(find.text('Add venue'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. SM City Lucena'),
      'Robinsons Lipa',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Step two: cash is there by default, so this can be saved as-is.
    expect(find.text('Save venue'), findsOneWidget);
    await tester.tap(find.text('Save venue'));
    await tester.pumpAndSettle();

    expect(
      cubit.state.companies.length,
      before + 1,
      reason: 'the venue never reached the cubit',
    );
    expect(find.text('Robinsons Lipa'), findsOneWidget);
  });
}
