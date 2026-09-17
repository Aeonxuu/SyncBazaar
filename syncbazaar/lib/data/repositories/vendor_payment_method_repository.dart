import 'dart:typed_data';

import '../remote/api_client.dart';
import '../remote/vendor_payment_method_api_mapper.dart';
import 'auth_repository.dart';

/// A vendor's own list of payment methods, and the shared catalog it draws
/// from.
///
/// Replaces two things that used to live in `SettingsRepository`: the
/// per-venue method lists (a method belonged to a venue, so the same GCash
/// wallet needed re-adding on every one), and the per-venue QR cache backing
/// it. A vendor has one list now, shared by every venue and bazaar it holds.
///
/// Server-backed only. Without a session ([listMethods] returns empty and
/// every write throws) this is the demo build, which has nothing to manage
/// here — creating a product in memory needs no payment method to go with it.
class VendorPaymentMethodRepository {
  VendorPaymentMethodRepository({AuthRepository? auth}) : _auth = auth;

  final AuthRepository? _auth;

  int? _loadedVendorId;
  Future<void>? _load;

  List<VendorPaymentMethod> _methods = const [];

  /// The catalog, by the id a vendor's own row points at. Also what the
  /// add-method suggestion field filters against.
  Map<int, ModeOfPaymentCatalogEntry> _catalogById = const {};

  bool get isRemote => _auth?.vendorId != null;

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
    final load = _loadFromApi(
      auth,
      vendorId,
    ).then((_) => _loadedVendorId = vendorId);
    _load = load.whenComplete(() => _load = null);
    await _load;
  }

  Future<void> _loadFromApi(AuthRepository auth, int vendorId) async {
    final catalogPayload =
        await auth.api.get('/api/core/mode-of-payment/') as List;
    final catalog = mapModeOfPaymentCatalog(catalogPayload);
    _catalogById = {for (final entry in catalog) entry.id: entry};

    final payload =
        await auth.api.get(vendorPaymentMethodsPath(vendorId)) as List;
    _methods = mapVendorPaymentMethods(payload, catalogById: _catalogById);
  }

  /// Re-fetches both the vendor's list and the catalog behind it.
  Future<void> refresh() async {
    if (_auth?.vendorId == null) {
      return;
    }
    _loadedVendorId = null;
    await _ensureLoaded();
  }

  /// The vendor's own methods. Empty with no session, and empty for a real
  /// vendor with nothing added yet — both are told apart by [isRemote], which
  /// is what a caller checks to know whether "empty" means "not signed in" or
  /// "genuinely nothing here yet."
  Future<List<VendorPaymentMethod>> listMethods() async {
    await _ensureLoaded();
    return _methods;
  }

  /// The catalog, for the add-method suggestion field. Loaded as a side
  /// effect of [listMethods]; fetched on its own only when nothing has been
  /// loaded yet this session.
  Future<List<ModeOfPaymentCatalogEntry>> catalog() async {
    await _ensureLoaded();
    return _catalogById.values.toList();
  }

  /// Adds [name] to the vendor's list, reusing a matching catalog entry
  /// rather than creating a duplicate.
  ///
  /// Matched loosely: spacing and punctuation are ignored, so typing "QR PH"
  /// finds an existing "QRPH" instead of minting a second row for the same
  /// wallet. `ModeOfPayment` is shared by every vendor in the system, and a
  /// near-miss here is a mess every one of them sees in their own suggestion
  /// list from then on.
  ///
  /// [label] is only used when creating a genuinely new catalog entry; an
  /// existing entry's label is the catalog's, not this call's, to change.
  Future<void> addMethod({required String name, String? label}) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot add a payment method without a session.');
    }
    // Without this, a fresh repository's catalog is empty and every add
    // would find no match and mint a duplicate -- the exact mistake this
    // whole matching step exists to prevent.
    await _ensureLoaded();
    final catalogId = await _ensureCatalogEntry(auth, name: name, label: label);
    await auth.api.post(
      vendorPaymentMethodsPath(vendorId),
      body: {'mode_of_payment': catalogId},
    );
    await refresh();
  }

  /// The catalog id [name] resolves to, creating a catalog entry if nothing
  /// matches.
  ///
  /// Relocated from the venue-save path, where this same problem showed up
  /// first: a name typed by hand needs somewhere to land whether or not the
  /// catalog already has it, and creating it here is how a method exists at
  /// all for the first vendor to type a new one.
  Future<int> _ensureCatalogEntry(
    AuthRepository auth, {
    required String name,
    String? label,
  }) async {
    final wanted = _squash(name);
    for (final entry in _catalogById.values) {
      if (_squash(entry.name) == wanted) {
        return entry.id;
      }
    }
    final trimmedLabel = label?.trim();
    final created =
        await auth.api.post(
              '/api/core/mode-of-payment/',
              body: {
                'name': name.trim(),
                if (trimmedLabel != null && trimmedLabel.isNotEmpty)
                  'required_information_name': trimmedLabel,
              },
            )
            as Map<String, dynamic>;
    final id = (created['id'] as num?)?.toInt();
    if (id == null) {
      throw const ApiException(
        ApiErrorKind.server,
        'The payment method could not be created.',
      );
    }
    // Recorded so a second add in the same session, or the suggestion field
    // right after this one, sees it without a round trip.
    _catalogById = {
      ..._catalogById,
      id: ModeOfPaymentCatalogEntry(
        id: id,
        name: (created['name'] as String? ?? name).trim(),
        extraFieldLabel: (created['required_information_name'] as String?)
            ?.trim(),
      ),
    };
    return id;
  }

  /// Letters and digits only, upper-cased. "QR Ph", "qr-ph" and "QRPH" all
  /// reduce to one key.
  static String _squash(String name) =>
      name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// Removes [method] from the vendor's list.
  ///
  /// Only this vendor's row goes; the catalog entry it pointed at is left
  /// alone, since other vendors may point at the same one. This is the
  /// vendor's own toggle for "we don't take this" — there is no other one.
  Future<void> removeMethod(VendorPaymentMethod method) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot remove a payment method without a session.');
    }
    await auth.api.delete(vendorPaymentMethodPath(vendorId, method.id));
    await refresh();
  }

  /// Uploads [bytes] as [method]'s QR, replacing whatever was there.
  ///
  /// The server is the QR's only copy now — nothing is cached locally, so a
  /// failed upload leaves the row exactly as it was rather than showing an
  /// image nobody has confirmed.
  Future<void> uploadQr({
    required VendorPaymentMethod method,
    required Uint8List bytes,
  }) async {
    final auth = _auth;
    final vendorId = auth?.vendorId;
    if (auth == null || vendorId == null) {
      throw StateError('Cannot upload a QR without a session.');
    }
    await auth.api.uploadFile(
      vendorPaymentMethodImagePath(vendorId, method.id),
      bytes: bytes,
      field: 'qr_code_image',
      filename: '${method.name.toLowerCase()}_qr.png',
    );
    await refresh();
  }
}
