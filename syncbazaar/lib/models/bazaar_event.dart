enum BazaarStatus { upcoming, ongoing, ended }

class BazaarPaymentMethod {
  const BazaarPaymentMethod({required this.name, this.extraFieldLabel});

  final String name;
  final String? extraFieldLabel;
}

class BazaarEvent {
  const BazaarEvent({
    required this.id,
    required this.name,
    required this.companyId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.acceptedPaymentMethods = const ['CASH'],
    this.customOtherMethods = const [],
  });

  final int id;
  final String name;
  final int companyId;
  final DateTime startDate;
  final DateTime endDate;
  final BazaarStatus status;
  final List<String> acceptedPaymentMethods;
  final List<BazaarPaymentMethod> customOtherMethods;
}
