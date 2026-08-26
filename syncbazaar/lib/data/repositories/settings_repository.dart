import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/company.dart';
import '../remote/establishment_api_mapper.dart';
import 'auth_repository.dart';

class PaymentMethodMeta {
  const PaymentMethodMeta({
    required this.name,
    this.extraFieldLabel,
    this.qrImageBytes,
  });

  final String name;
  final String? extraFieldLabel;

  /// The seller's QR for this method, already cropped to the code itself.
  ///
  /// Bytes rather than a file path, for the reason set out on `Product
  /// .imageBytes`: a path is not portable, and on web it is a `blob:` URL that
  /// no image widget can load. Its presence is also what tells the POS to
  /// present a QR at checkout, so attaching one to a new method needs no code.
  final Uint8List? qrImageBytes;

  PaymentMethodMeta copyWith({
    String? name,
    String? extraFieldLabel,
    Uint8List? qrImageBytes,
    bool clearQr = false,
  }) {
    return PaymentMethodMeta(
      name: name ?? this.name,
      extraFieldLabel: extraFieldLabel ?? this.extraFieldLabel,
      qrImageBytes: clearQr ? null : (qrImageBytes ?? this.qrImageBytes),
    );
  }
}

class SettingsRepository {
  /// Venues come from the API when [auth] is supplied.
  ///
  /// Everything else here — the store name, auto-sync — stays local, because
  /// they are settings for this device rather than facts about the business.
  SettingsRepository({AuthRepository? auth}) : _auth = auth;

  final AuthRepository? _auth;

  int? _loadedVendorId;
  Future<void>? _load;

  /// Payment method id to what it is called, needed both ways: a venue lists
  /// the methods it accepts as ids, and saving one sends ids back.
  Map<int, PaymentMethodMeta> _methodsById = {};

  static const String _storeNameKey = 'settings.storeName';
  static const String _paymentQrKey = 'settings.paymentMethodQr';

  /// Refuses to persist anything larger than this per code. A cropped QR is
  /// tens of kilobytes; something far bigger means the crop went wrong, and
  /// SharedPreferences is the wrong place for a photo.
  static const int _maxQrBytes = 512 * 1024;

  /// QR per venue-and-method, keyed by `<companyId>|<METHOD NAME>`.
  ///
  /// Held apart from the method lists themselves and merged only on read.
  /// Venues and their methods come from the API and are replaced wholesale on
  /// every reload; keeping the QR out of that path means a refresh cannot
  /// discard an upload. It also keeps the API mapper unaware of QR entirely,
  /// which matters while QR is a client-only feature.
  final Map<String, Uint8List> _qrByKey = {};
  bool _qrLoaded = false;

  /// Printed until the seller sets their own name, so a receipt is never
  /// headed by an empty line.
  static const String _defaultStoreName = 'SyncBazaar';

  final List<Company> _companies = [];

  bool _autoSyncOnReconnect = true;
  int _nextCompanyId = 1;

  final Map<int, List<PaymentMethodMeta>> _locationPaymentMethodsByCompanyId =
      {};

  final List<PaymentMethodMeta> _paymentMethods = [
    const PaymentMethodMeta(name: 'CASH'),
  ];

  /// Fetches the venue list once signed in.
  ///
  /// Returns immediately without a session, so the mock-seeded and test paths
  /// keep their in-memory behaviour.
  Future<void> _ensureLoaded() async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null || _loadedVendorId == vendorId) {
      return;
    }

    final existing = _load;
    if (existing != null) {
      await existing;
      return;
    }
    final load = _loadFromApi(auth).then((_) => _loadedVendorId = vendorId);
    _load = load.whenComplete(() => _load = null);
    await _load;
  }

  Future<void> _loadFromApi(AuthRepository auth) async {
    _methodsById = mapPaymentMethodsById(
      await auth.api.get('/api/core/mode-of-payment/') as List,
    );
    final bundle = mapEstablishmentsResponse(
      await auth.api.get('/api/core/establishment/') as List,
      methodsById: _methodsById,
    );

    _companies
      ..clear()
      ..addAll(bundle.companies);
    _locationPaymentMethodsByCompanyId
      ..clear()
      ..addAll(bundle.paymentMethodsByCompanyId);

    // Ids come from the server now, so a locally created venue must not be
    // handed one the server might also issue.
    for (final company in _companies) {
      if (company.id >= _nextCompanyId) {
        _nextCompanyId = company.id + 1;
      }
    }
  }

  /// Re-fetches the venue list, discarding what is held now.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoaded();
  }

  Future<List<Company>> listCompanies() async {
    await _ensureLoaded();
    return _companies;
  }

  Future<void> upsertCompany(Company company) async {
    await _ensureLoaded();
    await _saveCompanyToServer(company);

    final idx = _companies.indexWhere((c) => c.id == company.id);
    if (idx == -1) {
      _companies.add(company);
      _locationPaymentMethodsByCompanyId.putIfAbsent(
        company.id,
        () => const [PaymentMethodMeta(name: 'CASH')],
      );
      return;
    }
    _companies[idx] = company;
  }

  /// Writes an existing venue back.
  ///
  /// Failure is not swallowed: a venue is printed on every receipt from the
  /// bazaars held there, and one that looks saved but is not would go
  /// unnoticed until a receipt came out with the old address on it.
  Future<void> _saveCompanyToServer(Company company) async {
    final auth = _auth;
    if (auth == null || auth.vendorId == null) {
      return;
    }
    // Only for venues the server knows. A locally created one is created
    // through `createCompany`, which is where its id comes from.
    if (!_companies.any((c) => c.id == company.id)) {
      return;
    }
    await auth.api.put(
      '/api/core/establishment/${company.id}/',
      body: establishmentBody(
        company: company,
        acceptedPaymentMethodIds: _methodIdsFor(company.id),
      ),
    );
  }

  /// The ids of the methods a venue accepts, defaulting to everything the
  /// server knows when nothing has been chosen yet.
  List<int> _methodIdsFor(int companyId) {
    final chosen = _locationPaymentMethodsByCompanyId[companyId];
    if (chosen == null || chosen.isEmpty) {
      return _methodsById.keys.toList();
    }
    final wanted = chosen.map((m) => m.name.trim().toUpperCase()).toSet();
    final ids = [
      for (final entry in _methodsById.entries)
        if (wanted.contains(entry.value.name.trim().toUpperCase())) entry.key,
    ];
    // An empty list would leave the venue accepting no payment at all.
    return ids.isEmpty ? _methodsById.keys.toList() : ids;
  }

  Future<Company> createCompany({
    required String name,
    String address = '',
    String contact = '',
    double incentivePercent = 0,
    double bufferPercent = 0,
  }) async {
    await _ensureLoaded();

    var created = Company(
      id: _nextCompanyId++,
      name: name.trim(),
      address: address.trim(),
      contact: contact.trim(),
      incentivePercent: incentivePercent,
      bufferPercent: bufferPercent,
    );

    // Created on the server first so the venue carries the id the server
    // assigned. A locally numbered venue would be referenced by any bazaar
    // held there, and that bazaar's id belongs to the server — so the two
    // would point at different places the moment the app restarted.
    final auth = _auth;
    if (auth != null && auth.vendorId != null) {
      final row =
          await auth.api.post(
                '/api/core/establishment/',
                body: establishmentBody(
                  company: created,
                  // Everything on offer, since a new venue has not been
                  // configured yet and one accepting nothing cannot take money.
                  acceptedPaymentMethodIds: _methodsById.keys.toList(),
                ),
              )
              as Map<String, dynamic>;
      created = created.copyWith(id: (row['id'] as num).toInt());
    }

    _companies.add(created);
    // Mirrors what was actually sent. Recording CASH here while the server was
    // told "everything" would make the venue's payment menu change the first
    // time it was reloaded, with nothing having edited it.
    _locationPaymentMethodsByCompanyId[created.id] = _methodsById.isEmpty
        ? const [PaymentMethodMeta(name: 'CASH')]
        : _methodsById.values.toList();
    return created;
  }

  Future<Map<int, List<PaymentMethodMeta>>> paymentMethodsByCompanyId() async {
    await _ensureLoaded();
    await _ensureQrLoaded();
    return {
      for (final entry in _locationPaymentMethodsByCompanyId.entries)
        entry.key: [
          for (final method in entry.value) _withQr(entry.key, method),
        ],
    };
  }

  /// Attaches the stored QR, if this venue has one for this method.
  PaymentMethodMeta _withQr(int companyId, PaymentMethodMeta method) {
    final bytes = _qrByKey[_qrKey(companyId, method.name)];
    return bytes == null ? method : method.copyWith(qrImageBytes: bytes);
  }

  static String _qrKey(int companyId, String methodName) =>
      '$companyId|${methodName.trim().toUpperCase()}';

  /// Stores, replaces, or clears the QR for one venue's payment method.
  ///
  /// Persisted rather than held in memory like the rest of this repository: a
  /// QR is set up once and needed at every sale, so losing it on restart would
  /// mean re-uploading before each day's trading.
  Future<void> setPaymentMethodQr({
    required int companyId,
    required String methodName,
    required Uint8List? bytes,
  }) async {
    await _ensureQrLoaded();
    final key = _qrKey(companyId, methodName);
    if (bytes == null) {
      _qrByKey.remove(key);
    } else if (bytes.lengthInBytes <= _maxQrBytes) {
      _qrByKey[key] = bytes;
    } else {
      return;
    }
    await _persistQr();
  }

  Future<void> _ensureQrLoaded() async {
    if (_qrLoaded) {
      return;
    }
    _qrLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_paymentQrKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((key, value) {
        if (value is String && value.isNotEmpty) {
          _qrByKey[key] = base64Decode(value);
        }
      });
    } catch (_) {
      // Unreadable stored QRs are dropped rather than allowed to break start-up.
      // Re-uploading one is a few seconds; a till that will not open is not.
      _qrByKey.clear();
    }
  }

  Future<void> _persistQr() async {
    final prefs = await SharedPreferences.getInstance();
    if (_qrByKey.isEmpty) {
      await prefs.remove(_paymentQrKey);
      return;
    }
    await prefs.setString(
      _paymentQrKey,
      jsonEncode({
        for (final entry in _qrByKey.entries) entry.key: base64Encode(entry.value),
      }),
    );
  }

  /// [clearMissingQr] is for the venue editor, which always holds the complete
  /// picture: there, a method arriving without a QR means the seller removed
  /// it. Every other caller leaves stored codes alone, so a partial write, or a
  /// venue list refreshed from the API without QR data, cannot silently delete
  /// a seller's payment code.
  Future<void> upsertCompanyConfiguration({
    required Company company,
    required List<PaymentMethodMeta> paymentMethods,
    bool clearMissingQr = false,
  }) async {
    // Recorded before the write, so the venue is saved with the methods just
    // chosen rather than the ones it had a moment ago.
    final normalized = _normalizePaymentMethods(paymentMethods);
    _locationPaymentMethodsByCompanyId[company.id] = normalized;
    // Persisted here rather than left to the caller, so a QR survives a restart
    // no matter which screen saved the venue. The method lists themselves are
    // replaced wholesale on the next API reload; these do not travel with them.
    for (final method in normalized) {
      if (method.qrImageBytes == null && !clearMissingQr) {
        continue;
      }
      await setPaymentMethodQr(
        companyId: company.id,
        methodName: method.name,
        bytes: method.qrImageBytes,
      );
    }
    await upsertCompany(company);
  }

  Future<List<PaymentMethodMeta>> paymentMethods() async {
    final methods = <PaymentMethodMeta>[..._paymentMethods];
    for (final locationMethods in _locationPaymentMethodsByCompanyId.values) {
      for (final method in locationMethods) {
        final idx = methods.indexWhere(
          (item) =>
              item.name.trim().toUpperCase() ==
              method.name.trim().toUpperCase(),
        );
        if (idx == -1) {
          methods.add(method);
        } else {
          final existing = methods[idx];
          final shouldUpgrade =
              (existing.extraFieldLabel == null ||
                  existing.extraFieldLabel!.trim().isEmpty) &&
              method.extraFieldLabel != null &&
              method.extraFieldLabel!.trim().isNotEmpty;
          if (shouldUpgrade) {
            methods[idx] = method;
          }
        }
      }
    }
    return methods;
  }

  Future<bool> autoSyncEnabled() async => _autoSyncOnReconnect;

  Future<void> setAutoSync(bool enabled) async {
    _autoSyncOnReconnect = enabled;
  }

  /// The seller's own name — the pop-up store, e.g. "SV KICKz".
  ///
  /// Distinct from [Company], which models the venue hosting the bazaar. The
  /// receipt header prints both, because a customer needs to know who sold
  /// them the shoes, not only which mall they were standing in.
  ///
  /// Unlike its in-memory siblings this one is persisted: it is typed once and
  /// then printed on every receipt, so losing it on restart would silently
  /// start producing unbranded receipts. Follows [AuthRepository]'s use of
  /// `shared_preferences`.
  /// The signed-in vendor's name, falling back to the device setting.
  ///
  /// Signed in, the server is the only source. The name is a fact about the
  /// business, not a preference of this tablet: it heads every receipt and is
  /// printed six times on the statement of account, which the *server*
  /// renders. Reading a local copy here let the two drift, so the screen said
  /// one name while the document said another — and a second vendor signing
  /// into this app would have printed the first vendor's name on their
  /// receipts.
  ///
  /// The local value survives only for the no-session build, where there is no
  /// vendor to ask.
  Future<String> storeName() async {
    final vendor = _auth?.vendorName?.trim();
    if (vendor != null && vendor.isNotEmpty) {
      return vendor;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storeNameKey)?.trim();
    return (stored == null || stored.isEmpty) ? _defaultStoreName : stored;
  }

  /// Whether a rename would reach the server rather than staying on this
  /// device. Lets the UI say which of the two it is doing.
  bool get storeNameIsVendor => _auth?.vendorId != null;

  /// Renames the vendor where there is a session, and the device otherwise.
  ///
  /// Throws [ApiException] when the server refuses or cannot be reached, so a
  /// name that was not saved is never shown as though it were.
  Future<void> setStoreName(String name) async {
    final auth = _auth;
    if (auth != null && auth.vendorId != null) {
      await auth.renameVendor(name);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_storeNameKey);
      return;
    }
    await prefs.setString(_storeNameKey, trimmed);
  }

  List<PaymentMethodMeta> _normalizePaymentMethods(
    List<PaymentMethodMeta> input,
  ) {
    final normalized = <PaymentMethodMeta>[];
    for (final item in input) {
      final name = item.name.trim();
      if (name.isEmpty) {
        continue;
      }
      final existing = normalized.indexWhere(
        (method) => method.name.toUpperCase() == name.toUpperCase(),
      );
      final next = PaymentMethodMeta(
        name: name,
        extraFieldLabel: _sanitizeExtraFieldLabel(item.extraFieldLabel),
        // Carried through: normalising a venue's methods on save must not
        // silently detach a QR the seller uploaded moments earlier.
        qrImageBytes: item.qrImageBytes,
      );
      if (existing == -1) {
        normalized.add(next);
      } else {
        normalized[existing] = next;
      }
    }
    return normalized;
  }

  String? _sanitizeExtraFieldLabel(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 28) {
      return trimmed;
    }
    return trimmed.substring(0, 28);
  }
}
