import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/theme/app_theme.dart';
import 'package:syncbazaar/ui/screens/settings/legal_documents.dart';
import 'package:syncbazaar/ui/screens/settings/widgets/info_document_dialog.dart';

/// The reference documents in Settings.
///
/// The privacy notice describes what this app actually does with data. That
/// makes it checkable, and worth checking: a notice that has drifted from the
/// software is worse than none, because someone relies on it.
void main() {
  group('every document is complete', () {
    test('has a title, a summary, a date and sections', () {
      for (final doc in settingsDocuments) {
        expect(doc.title.trim(), isNotEmpty, reason: doc.title);
        expect(doc.summary.trim(), isNotEmpty, reason: doc.title);
        expect(doc.updated.trim(), isNotEmpty, reason: doc.title);
        expect(doc.sections, isNotEmpty, reason: doc.title);
      }
    });

    test('no section is an empty heading', () {
      for (final doc in settingsDocuments) {
        for (final section in doc.sections) {
          expect(section.heading.trim(), isNotEmpty, reason: doc.title);
          expect(section.body, isNotEmpty, reason: section.heading);
          for (final paragraph in section.body) {
            expect(paragraph.trim(), isNotEmpty, reason: section.heading);
          }
        }
      }
    });

    test('there are three, in the order Settings expects', () {
      expect(settingsDocuments, hasLength(3));
      expect(settingsDocuments[0], privacyNotice);
      expect(settingsDocuments[1], termsOfUse);
      expect(settingsDocuments[2], frequentlyAsked);
    });
  });

  group('the privacy notice matches what the app does', () {
    String allText(InfoDocument doc) => doc.sections
        .expand((s) => [s.heading, ...s.body])
        .join(' ')
        .toLowerCase();

    test('names the things actually kept on the device', () {
      final text = allText(privacyNotice);

      // Each of these is real: the session, the queue of unsent sales, the
      // cached responses, and the uploaded QR codes.
      expect(text, contains('sign-in'));
      expect(text, contains('without a connection'));
      expect(text, contains('qr'));
      expect(text, contains('receipt'));
    });

    test('is explicit about what is not collected', () {
      final text = allText(privacyNotice);

      expect(text, contains('location'));
      expect(text, contains('advertising'));
      // The app records a payment method and a reference number, never a card
      // number. Saying so is the point of the section.
      expect(text, contains('card number'));
    });

    test('explains that a blank customer becomes Walk-in', () {
      expect(allText(privacyNotice), contains('walk-in'));
    });
  });

  group('reading one', () {
    testWidgets('opens, shows its content, and closes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showInfoDocument(
                  context: context,
                  document: frequentlyAsked,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text(frequentlyAsked.title), findsOneWidget);
      expect(
        find.text(frequentlyAsked.sections.first.heading),
        findsOneWidget,
      );
      expect(find.textContaining('Last updated'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Close'));
      await tester.pumpAndSettle();

      expect(find.text(frequentlyAsked.title), findsNothing);
    });

    testWidgets('a long document scrolls rather than overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showInfoDocument(
                  context: context,
                  document: privacyNotice,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
