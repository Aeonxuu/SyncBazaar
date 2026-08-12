import '../../models/company.dart';
import '../repositories/settings_repository.dart';

/// Everything one `GET /api/core/establishment/` gives the settings layer.
class ApiEstablishmentBundle {
  const ApiEstablishmentBundle({
    required this.companies,
    required this.paymentMethodsByCompanyId,
  });

  final List<Company> companies;

  /// Which methods each venue accepts, resolved from ids to names.
  final Map<int, List<PaymentMethodMeta>> paymentMethodsByCompanyId;
}

/// Turns the venue list into the app's `Company` records.
///
/// The two sides use different words for the same thing: an `Establishment`
/// server-side is a `Company` here — the mall or campus hosting a bazaar, not
/// the stall taking the money. Both names are load-bearing in their own
/// codebase, so this is where they meet rather than either being renamed.
///
/// [methodNamesById] comes from `/api/core/mode-of-payment/`, because a venue
/// lists the methods it accepts as ids and the app carries names.
ApiEstablishmentBundle mapEstablishmentsResponse(
  List<dynamic> payload, {
  required Map<int, PaymentMethodMeta> methodsById,
}) {
  final companies = <Company>[];
  final methodsByCompanyId = <int, List<PaymentMethodMeta>>{};

  for (final entry in payload) {
    final map = entry as Map<String, dynamic>;
    final id = (map['id'] as num).toInt();

    companies.add(
      Company(
        id: id,
        name: map['name'] as String? ?? '',
        address: map['address'] as String? ?? '',
        contact: map['contact'] as String? ?? '',
        incentivePercent: (map['incentive_percent'] as num?)?.toDouble() ?? 0,
        bufferPercent: (map['buffer_percent'] as num?)?.toDouble() ?? 0,
        // The server has no field for it. A venue's QR image stays a local
        // convenience until there is somewhere to upload one.
      ),
    );

    final accepted = <PaymentMethodMeta>[];
    for (final raw in (map['accepted_payment_methods'] as List? ?? const [])) {
      final method = methodsById[(raw as num).toInt()];
      if (method != null) {
        accepted.add(method);
      }
    }
    // Never left empty: a venue that accepts nothing gives the POS no way to
    // take money at all, which reads as a broken till rather than a
    // misconfigured venue.
    methodsByCompanyId[id] = accepted.isEmpty
        ? const [PaymentMethodMeta(name: 'CASH')]
        : accepted;
  }

  return ApiEstablishmentBundle(
    companies: companies,
    paymentMethodsByCompanyId: methodsByCompanyId,
  );
}

/// Indexes `/api/core/mode-of-payment/` by id.
///
/// Names are upper-cased because the rest of the app compares them that way —
/// `ReceiptSectionRegistry` resolves "CASH", and two seeders have already
/// disagreed on capitalisation once.
Map<int, PaymentMethodMeta> mapPaymentMethodsById(List<dynamic> payload) {
  final methods = <int, PaymentMethodMeta>{};
  for (final entry in payload) {
    final map = entry as Map<String, dynamic>;
    final id = (map['id'] as num?)?.toInt();
    final name = (map['name'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) {
      continue;
    }
    final label = (map['required_information_name'] as String?)?.trim();
    methods[id] = PaymentMethodMeta(
      name: name.toUpperCase(),
      extraFieldLabel: (label == null || label.isEmpty) ? null : label,
    );
  }
  return methods;
}

/// The body for creating or updating a venue.
Map<String, dynamic> establishmentBody({
  required Company company,
  required List<int> acceptedPaymentMethodIds,
}) => {
  'name': company.name,
  'address': company.address,
  'contact': company.contact,
  // Whole numbers server-side; a fractional cut would be silently truncated,
  // so it is rounded here where that is visible.
  'incentive_percent': company.incentivePercent.round(),
  'buffer_percent': company.bufferPercent.round(),
  'accepted_payment_methods': acceptedPaymentMethodIds,
};
