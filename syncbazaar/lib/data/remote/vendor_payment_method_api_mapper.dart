/// Where a vendor's own payment methods live.
///
/// A method used to be chosen per venue, with its own QR uploaded per venue.
/// That model is gone: `ModeOfPayment` stays as the shared catalog of names
/// (so two vendors both calling something "GCash" share one row instead of
/// each minting a duplicate), and `VendorPaymentMethod` is one vendor's own
/// list of which catalog entries it actually accepts, each with its own QR.
/// A venue no longer has payment methods of its own at all.
library;

String vendorPaymentMethodsPath(int vendorId) =>
    '/api/core/vendor/$vendorId/payment-method/';

/// One row of [vendorId]'s own list, for removing or attaching a QR to.
String vendorPaymentMethodPath(int vendorId, int rowId) =>
    '/api/core/vendor/$vendorId/payment-method/$rowId/';

String vendorPaymentMethodImagePath(int vendorId, int rowId) =>
    '/api/core/vendor/$vendorId/payment-method/$rowId/image/';

/// One entry in the shared catalog every vendor's list points into.
///
/// [extraFieldLabel] is read from here rather than from the vendor's own
/// list, because the vendor-scoped response does not echo it — only the
/// catalog knows a GCash-shaped method wants a "Reference Number".
class ModeOfPaymentCatalogEntry {
  const ModeOfPaymentCatalogEntry({
    required this.id,
    required this.name,
    this.extraFieldLabel,
  });

  final int id;
  final String name;
  final String? extraFieldLabel;
}

/// One row of a vendor's own payment-method list.
class VendorPaymentMethod {
  const VendorPaymentMethod({
    required this.id,
    required this.modeOfPaymentId,
    required this.name,
    this.extraFieldLabel,
    this.qrImageUrl,
  });

  /// This row's own id — what a removal or a QR upload addresses, never the
  /// catalog id.
  final int id;

  /// The catalog entry this row points at. Kept so adding a second method
  /// pointed at the same catalog entry can be refused before the request
  /// goes out, matching the server's own uniqueness rule.
  final int modeOfPaymentId;

  final String name;
  final String? extraFieldLabel;

  /// A URL, not bytes. The QR now lives on the server as the row's only
  /// copy — there is no local cache to fall back on, and none is kept.
  final String? qrImageUrl;
}

/// Turns `GET /api/core/mode-of-payment/` into the shared catalog.
///
/// A blank name is dropped rather than kept: it cannot be matched against by
/// the suggestion field, and showing it as a choice would offer something
/// with nothing to select.
List<ModeOfPaymentCatalogEntry> mapModeOfPaymentCatalog(List<dynamic> payload) {
  final entries = <ModeOfPaymentCatalogEntry>[];
  for (final raw in payload) {
    final map = raw as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt();
    final name = (map['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) {
      continue;
    }
    final label = (map['required_information_name'] as String?)?.trim();
    entries.add(
      ModeOfPaymentCatalogEntry(
        id: id,
        name: name,
        extraFieldLabel: (label == null || label.isEmpty) ? null : label,
      ),
    );
  }
  return entries;
}

/// Turns `GET /api/core/vendor/<id>/payment-method/` into the vendor's list.
///
/// [catalogById] supplies the extra-field label, which this response does not
/// carry on its own — joined by [ModeOfPaymentCatalogEntry.id] against the
/// catalog entry each row points at.
List<VendorPaymentMethod> mapVendorPaymentMethods(
  List<dynamic> payload, {
  required Map<int, ModeOfPaymentCatalogEntry> catalogById,
}) {
  final methods = <VendorPaymentMethod>[];
  for (final raw in payload) {
    final map = raw as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt();
    final modeOfPaymentId = (map['mode_of_payment'] as num?)?.toInt();
    if (id == null || modeOfPaymentId == null) {
      continue;
    }
    final catalogEntry = catalogById[modeOfPaymentId];
    final name =
        (map['mode_of_payment_name'] as String?)?.trim() ??
        catalogEntry?.name ??
        '';
    if (name.isEmpty) {
      continue;
    }
    methods.add(
      VendorPaymentMethod(
        id: id,
        modeOfPaymentId: modeOfPaymentId,
        name: name.toUpperCase(),
        extraFieldLabel: catalogEntry?.extraFieldLabel,
        qrImageUrl: map['qr_code_image_url'] as String?,
      ),
    );
  }
  return methods;
}
