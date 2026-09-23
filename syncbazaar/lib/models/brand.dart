/// A vendor-defined product brand, e.g. "Nike".
///
/// Scoped to one vendor server-side — two vendors can each have their own
/// "Nike" row — so this only ever appears already filtered to the signed-in
/// vendor's own list.
class Brand {
  const Brand({required this.id, required this.name});

  final int id;
  final String name;
}
