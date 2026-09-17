import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/widgets/confirmation_dialog.dart';

/// A failure the user has to see, with one way out.
///
/// It replaced a SnackBar for a delete the server refused. On a tablet the
/// SnackBar sat at the bottom, easy to miss and gone in four seconds, so a
/// refusal could read as success. The dialog holds until dismissed.
void main() {
  var closed = false;

  Future<void> open(WidgetTester tester) async {
    closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                await showNoticeDialog(
                  context: context,
                  title: 'Not deleted',
                  message:
                      'Nike Air Max SC was not deleted. Cannot delete product '
                      'because one of its variants has recorded sales.',
                  tone: ConfirmationTone.destructive,
                );
                closed = true;
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title and the whole reason', (tester) async {
    await open(tester);

    expect(find.text('Not deleted'), findsOneWidget);
    expect(find.textContaining('recorded sales'), findsOneWidget);
  });

  testWidgets('offers exactly one way out, and no Cancel', (tester) async {
    await open(tester);

    // There is nothing to back out of, only something to read. A Cancel
    // button would imply the delete could still be un-refused.
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('OK closes it', (tester) async {
    await open(tester);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(find.text('Not deleted'), findsNothing);
  });

  testWidgets('a tap outside does not dismiss it silently', (tester) async {
    // Holding until dismissed is the point. If the barrier closed it, a stray
    // tap would swallow the one message the user needed.
    await open(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Not deleted'), findsOneWidget);
  });
}
