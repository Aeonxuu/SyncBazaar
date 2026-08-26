class Company {
  const Company({
    required this.id,
    required this.name,
    required this.address,
    required this.contact,
    required this.incentivePercent,
    required this.bufferPercent,
  });

  final int id;
  final String name;
  final String address;
  final String contact;
  final double incentivePercent;
  final double bufferPercent;

  Company copyWith({
    int? id,
    String? name,
    String? address,
    String? contact,
    double? incentivePercent,
    double? bufferPercent,
  }) {
    return Company(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      incentivePercent: incentivePercent ?? this.incentivePercent,
      bufferPercent: bufferPercent ?? this.bufferPercent,
    );
  }
}
