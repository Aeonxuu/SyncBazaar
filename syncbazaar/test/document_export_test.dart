import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncbazaar/data/repositories/auth_repository.dart';
import 'package:syncbazaar/services/document_saver.dart';
import 'package:syncbazaar/services/orders_workbook.dart';
import 'package:syncbazaar/services/report_service.dart';

/// What an export reports back, including when it was not saved at all.
///
/// On Android the plain save writes to `Android/data/<package>/files/`, which
/// is private to the app and hidden by most file managers, so an export
/// announced "Saved to Downloads" and then existed nowhere the owner could
/// reach. Android now goes through the system save sheet instead, and that
/// sheet can be dismissed. A dismissal is not a failure and must not be
/// reported as a saved file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<OrderLine> lines() => [
    OrderLine(
      date: DateTime(2026, 9, 9, 14, 30),
      customerName: 'Walk-in',
      product: 'Nike Air Force 1 (Size 42)',
      paymentMethod: 'CASH',
      reference: '',
      quantity: 2,
      total: 7000,
      returned: false,
    ),
  ];

  ReportService serviceWith(DocumentSaver saver) =>
      ReportService(auth: AuthRepository(), saver: saver);

  test('a saved export reports where it went', () async {
    final result = await serviceWith(
      _StubSaver('Saved to Downloads as ListOfOrders_Test.xlsx'),
    ).exportOrdersWorkbook(
      eventName: 'Test Bazaar',
      lines: lines(),
      extraFieldLabelByMethod: const {},
    );

    expect(result, contains('ListOfOrders_Test.xlsx'));
  });

  test('a dismissed save sheet reports nothing rather than success', () async {
    final result = await serviceWith(_StubSaver(null)).exportOrdersWorkbook(
      eventName: 'Test Bazaar',
      lines: lines(),
      extraFieldLabelByMethod: const {},
    );

    // Null travels all the way up so the button stays quiet. Turning this into
    // a message would tell someone a file exists that they will never find.
    expect(result, isNull);
  });

  test('the bytes still reach the saver', () async {
    final saver = _StubSaver('saved');
    await serviceWith(saver).exportOrdersWorkbook(
      eventName: 'Test Bazaar',
      lines: lines(),
      extraFieldLabelByMethod: const {},
    );

    expect(saver.receivedBytes, isNotEmpty);
    expect(saver.receivedFormat, DocumentFormat.xlsx);
    expect(saver.receivedName, contains('ListOfOrders'));
  });

  group('where a document is sent', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android is routed through the system save sheet', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(DocumentSaver.usesSaveSheet, isTrue);
    });

    test('macOS writes straight to Downloads', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(
        DocumentSaver.usesSaveSheet,
        isFalse,
        reason: 'desktop already lands somewhere the user can find',
      );
    });
  });
}

class _StubSaver implements DocumentSaver {
  _StubSaver(this._result);

  final String? _result;
  Uint8List? receivedBytes;
  String? receivedName;
  DocumentFormat? receivedFormat;

  @override
  Future<String?> save({
    required Uint8List bytes,
    required String fileName,
    required DocumentFormat format,
  }) async {
    receivedBytes = bytes;
    receivedName = fileName;
    receivedFormat = format;
    return _result;
  }
}
