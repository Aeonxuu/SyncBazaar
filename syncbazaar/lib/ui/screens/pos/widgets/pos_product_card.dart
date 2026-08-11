import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../models/product.dart';
import '../../../widgets/product_thumbnail.dart';
import '../../../../core/utils/formatters.dart';

/// Nested corner radii for the product tile.
///
/// The rule for concentric corners is `inner = outer − gap`: an element inset
/// by `gap` inside a container of radius `outer` needs a radius that much
/// smaller, so the two arcs stay parallel and the space around the corner
/// keeps a constant width. Give the inner element the *same or a larger*
/// radius and its curve tightens against the container's, pinching the gap
/// exactly where the eye is most sensitive to it.
///
/// So only two of these three numbers are free. The gutter is picked first —
/// it is what the name and price row need to breathe on a 150-190px tile —
/// and the button's radius falls out of it.
const double _cardRadius = 10;
const double _contentInset = 6;
const double _buttonRadius = _cardRadius - _contentInset;

/// A compact rounded badge for a count, e.g. remaining stock.
class StockPill extends StatelessWidget {
  const StockPill({super.key, required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$quantity Items',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.black54,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class PosProductCard extends StatefulWidget {
  const PosProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.isEnabled = true,
  });

  final Product product;
  final VoidCallback onTap;
  final bool isEnabled;

  @override
  State<PosProductCard> createState() => _PosProductCardState();
}

class _PosProductCardState extends State<PosProductCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    return Opacity(
      opacity: widget.isEnabled ? 1 : 0.55,
      child: AnimatedScale(
        // Press feedback: confirms the tap landed before the variant
        // sheet has a chance to open. Frequent (tens/shift), so kept
        // subtle and fast rather than a showy effect.
        scale: _pressed ? 0.97 : 1,
        duration: AppMotion.feedback,
        curve: AppMotion.easeOut,
        child: InkWell(
          onTap: widget.isEnabled ? widget.onTap : null,
          onHighlightChanged: widget.isEnabled
              ? (value) => setState(() => _pressed = value)
              : null,
          borderRadius: BorderRadius.circular(_cardRadius),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(_cardRadius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x11000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: ProductThumbnail(
                    imagePath: product.imagePath,
                    imageBytes: product.imageBytes,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(_cardRadius),
                      topRight: Radius.circular(_cardRadius),
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    // Sides and bottom are the gap the corner rule is
                    // measured against, so they have to match each other.
                    // The top borders the photo rather than the card's edge,
                    // so it is free to stay a little larger.
                    padding: const EdgeInsets.fromLTRB(
                      _contentInset,
                      8,
                      _contentInset,
                      _contentInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                formatPeso(product.basePrice),
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            StockPill(quantity: product.stockQuantity),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: OutlinedButton.icon(
                            onPressed: widget.isEnabled ? widget.onTap : null,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                              side: BorderSide(
                                color: widget.isEnabled
                                    ? AppColors.primary
                                    : Colors.black26,
                              ),
                              foregroundColor: AppColors.primary,
                              disabledForegroundColor: Colors.black38,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  _buttonRadius,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 15),
                            label: Text(
                              widget.isEnabled ? 'Add to cart' : 'Out of stock',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
