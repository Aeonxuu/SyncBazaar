import 'dart:typed_data';

/// Lifecycle state of a product in the master inventory.
///
/// [active] products are sellable and allocatable to bazaars, [draft] ones are
/// still being set up, and [archived] ones are retired but kept for history.
enum ProductStatus { active, draft, archived }

extension ProductStatusLabel on ProductStatus {
  String get label => switch (this) {
    ProductStatus.active => 'Active',
    ProductStatus.draft => 'Draft',
    ProductStatus.archived => 'Archived',
  };
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.description,
    required this.basePrice,
    this.stockQuantity = 0,
    this.imagePath,
    this.imageBytes,
    this.status = ProductStatus.active,
  });

  final int id;
  final String name;
  final String? description;
  final double basePrice;
  final int stockQuantity;

  /// Path to a bundled asset or a remote `http(s)` URL. Used for images that
  /// live somewhere addressable — seeded data today, a CDN once there's a
  /// backend.
  final String? imagePath;

  /// Raw bytes of a photo the user picked on this device.
  ///
  /// Held as bytes rather than a path because a path is not portable: on the
  /// web `XFile.path` is a `blob:` URL that `Image.asset`/`Image.file` cannot
  /// read, and `dart:io`'s `File` does not exist there at all. Bytes render
  /// identically on every platform through `Image.memory`, which is what lets
  /// one code path serve web, desktop and mobile.
  ///
  /// These live in memory only — like the rest of this app's state, an upload
  /// does not survive a restart until there's a backend to POST it to.
  final Uint8List? imageBytes;

  final ProductStatus status;

  // Backward-compatibility getters for legacy UI sections not yet migrated.
  String get variant => '-';
  String get size => '-';
}
