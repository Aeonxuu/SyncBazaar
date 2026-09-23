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
/// The editor is one step now -- name, address, contact, rates -- since
/// payment methods moved to their own screen and there is nothing left for a
/// second step to hold. Still worth an end-to-end check: the editor returns a
/// draft, the screen turns that into a createLocation call, and the list
/// rebuilds off cubit state, which is several places for a new venue to be
/// lost between pressing Save and seeing it.
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

    // One step now: no "Continue" to a payment-methods page, since venues
    // do not carry payment methods any more. Two "Add venue" buttons are on
    // screen at once here -- the header's, behind the dialog, and the
    // dialog's own submit -- so the dialog's is picked out by its footer
    // position rather than by text alone.
    expect(find.text('Add venue'), findsWidgets);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add venue').last);
    await tester.pumpAndSettle();

    expect(
      cubit.state.companies.length,
      before + 1,
      reason: 'the venue never reached the cubit',
    );
    expect(find.text('Robinsons Lipa'), findsOneWidget);
  });

  // The add-a-method row this file used to guard the height of does not
  // exist here any more: payment methods moved to their own screen, added
  // through a plain AlertDialog rather than a hand-laid-out row, so there is
  // no custom row geometry left for a test like this to protect.
}
