import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/data/repositories/product_repository.dart';
import 'package:syncbazaar/models/product.dart';

/// Covers the path an uploaded photo takes from the product form to every
/// screen that renders one. It's all in-memory, so nothing here needs a
/// browser — but these are exactly the joins where a photo would silently
/// vanish, because each one rebuilds `Product` field by field.
void main() {
  final photo = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

  late ProductRepository repository;

  setUp(() => repository = ProductRepository());

  test('a saved photo survives the read path back out', () async {
    final saved = await repository.saveProduct(
      name: 'Test Sneaker',
      basePrice: 1800,
      imageBytes: photo,
      stockQuantity: 5,
    );
    expect(saved.imageBytes, photo);

    // listProducts() rebuilds every product through _withComputedStock to
    // attach live stock. That rebuild is the one the inventory table, POS grid
    // and POS cart all read from.
    final listed = await repository.listProducts();
    expect(listed.single.imageBytes, photo, reason: 'lost in listProducts');
  });

  test('archiving a product keeps its photo', () async {
    final saved = await repository.saveProduct(
      name: 'Test Sneaker',
      basePrice: 1800,
      imageBytes: photo,
      stockQuantity: 5,
    );

    // updateProductStatus also reconstructs Product by hand, so it can drop
    // fields it forgets to copy.
    await repository.updateProductStatus(
      id: saved.id,
      status: ProductStatus.archived,
    );

    final listed = await repository.listProducts();
    expect(listed.single.status, ProductStatus.archived);
    expect(listed.single.imageBytes, photo, reason: 'lost when archiving');
  });

  test('a product with no photo stays null rather than empty', () async {
    await repository.saveProduct(name: 'No Photo', basePrice: 1500);
    final listed = await repository.listProducts();
    expect(listed.single.imageBytes, isNull);
    expect(listed.single.imagePath, isNull);
  });
}
