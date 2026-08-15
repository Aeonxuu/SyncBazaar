import 'package:flutter_test/flutter_test.dart';
import 'package:syncbazaar/core/config/api_config.dart';
import 'package:syncbazaar/data/remote/product_api_mapper.dart';

/// Which picture a product shows, now that photos can be uploaded.
///
/// The catalogue shipped with bundled placeholder art in `image_link`, and the
/// mapper read that field directly. Once a real photograph could be uploaded,
/// reading it directly meant the stock art kept winning -- the product would
/// still show a generic shoe after someone had photographed the actual one.
/// The server resolves the two into `image_url`, and that is what to read.
void main() {
  Map<String, dynamic> variant({
    String? imageLink,
    String? image,
    String? imageUrl,
  }) => {
    'id': 1,
    'product': 1,
    'price': '1900.00',
    'stock_quantity': 5,
    'attribute_values': <Map<String, dynamic>>[],
    'image_link': imageLink,
    'image': image,
    'image_url': imageUrl,
  };

  ApiProductBundle mapOne(List<Map<String, dynamic>> variants) =>
      mapProductsResponse([
        {
          'id': 1,
          'name': 'Nike Air Max SC',
          'vendor': 1,
          'category': null,
          'attributes': <Map<String, dynamic>>[],
          'variants': variants,
        },
      ]);

  String? imageOf(List<Map<String, dynamic>> variants) =>
      mapOne(variants).products.single.imagePath;

  test('a bundled asset path is used as-is', () {
    // Not a server path, so nothing should be prepended to it.
    expect(
      imageOf([
        variant(
          imageLink: 'assets/images/default_shoes/airmaxsc.png',
          imageUrl: 'assets/images/default_shoes/airmaxsc.png',
        ),
      ]),
      'assets/images/default_shoes/airmaxsc.png',
    );
  });

  test('an uploaded photo beats the art the product shipped with', () {
    // The upload is on the second variant on purpose: whoever photographed
    // the shoe did not necessarily photograph the first colourway.
    expect(
      imageOf([
        variant(
          imageLink: 'assets/images/default_shoes/airmaxsc.png',
          imageUrl: 'assets/images/default_shoes/airmaxsc.png',
        ),
        variant(
          image: 'products/real-photo.jpg',
          imageUrl: 'https://cdn.example.test/products/real-photo.jpg',
        ),
      ]),
      'https://cdn.example.test/products/real-photo.jpg',
    );
  });

  test('a host-relative path is made absolute', () {
    // Django serves its own media this way when photos are not in the object
    // store. The thumbnail treats anything that is not http(s) as a bundled
    // asset, so a bare /media path would render the placeholder.
    expect(
      imageOf([
        variant(image: 'products/x.jpg', imageUrl: '/media/products/x.jpg'),
      ]),
      '${ApiConfig.baseUrl}/media/products/x.jpg',
    );
  });

  test('falls back to image_link on a server without image_url', () {
    expect(
      imageOf([variant(imageLink: 'assets/images/a.png')]),
      'assets/images/a.png',
    );
  });

  test('a variant with no picture is skipped, not returned blank', () {
    expect(
      imageOf([
        variant(),
        variant(imageLink: '   '),
        variant(imageUrl: 'assets/images/b.png'),
      ]),
      'assets/images/b.png',
    );
  });

  test('a product with no pictures anywhere has none', () {
    expect(imageOf([variant(), variant(imageLink: '')]), isNull);
  });
}
