import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:syncbazaar/app.dart';
import 'package:syncbazaar/ui/screens/login/login_screen.dart';

void main() {
  // The app restores any saved session on boot, which reads
  // `shared_preferences`. Without a mock store that plugin call never resolves
  // in a test and `pumpAndSettle` below spins until it times out.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('SyncBazaar boots to the login screen', (tester) async {
    // Seeding is off here on purpose. The dev seeder reads
    // `assets/dev/mock_data.json` through `rootBundle`, which is real I/O and
    // never completes inside the fake-async zone `testWidgets` runs in — with
    // it on, `pumpAndSettle` below spins until it times out. See
    // `SyncBazaarApp.seedMockData`.
    await tester.pumpWidget(const SyncBazaarApp(seedMockData: false));
    await tester.pumpAndSettle();

    // Asserted on the widget rather than on a heading string: this test is
    // here to prove the app boots and lands unauthenticated, and it shouldn't
    // start failing because someone reworded the login copy.
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
