/// A vendor-defined product category, e.g. "Shoes" or "Accessories".
///
/// Scoped to one vendor server-side — two vendors can each have their own
/// "Shoes" — so this only ever appears already filtered to the signed-in
/// vendor's own list.
class Category {
  const Category({required this.id, required this.name});

  final int id;
  final String name;
}
