class Company {
  const Company({
    required this.id,
    required this.name,
    required this.address,
    required this.contact,
    required this.incentivePercent,
    required this.bufferPercent,
    this.qrImagePath,
  });

  final int id;
  final String name;
  final String address;
  final String contact;
  final double incentivePercent;
  final double bufferPercent;
  final String? qrImagePath;
}
