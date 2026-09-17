import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../bloc/inventory/inventory_cubit.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/remote/api_client.dart';
import '../../../../models/product.dart';

/// Corrects a price or a stock count without opening the full product form.
///
/// The full form walks three steps and resubmits everything, and nothing it
/// saves reaches the server yet. This does one thing over the wire: a booth
/// operator is far more likely to fix a price than to add a product, and that
/// is the edit worth making real first.
///
/// The two fields reach different distances, and the labels say so before
/// anything is typed. Price is the product's: the server prices each variant,
/// but this app shows one price per product and that is how the operator
/// thinks of it, so every variant is set together. Stock is this variant's
/// alone.
///
/// Online-only by decision. Nothing is changed locally until the server has
/// confirmed it, so the table never shows a number that exists only on this
/// tablet. On failure the typed values stay put and the reason is shown here,
/// beside the field, not in a SnackBar under the dialog.
///
/// Returns a short message for the caller to show once it has closed, or null
/// if nothing was changed.
Future<String?> showQuickEditDialog({
  required BuildContext context,
  required InventoryCubit cubit,
  required Product product,
  required String allocationKey,
  required String variantLabel,
  required int currentStock,
  required Map<String, double> variantPrices,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuickEditDialog(
      cubit: cubit,
      product: product,
      allocationKey: allocationKey,
      variantLabel: variantLabel,
      currentStock: currentStock,
      variantPrices: variantPrices,
    ),
  );
}

class _QuickEditDialog extends StatefulWidget {
  const _QuickEditDialog({
    required this.cubit,
    required this.product,
    required this.allocationKey,
    required this.variantLabel,
    required this.currentStock,
    required this.variantPrices,
  });

  final InventoryCubit cubit;
  final Product product;
  final String allocationKey;

  /// "Black · 42", or empty for a product that is its own single SKU.
  final String variantLabel;
  final int currentStock;

  /// Every variant's current price. More than one distinct value means a
  /// product-wide change flattens a real difference, and the dialog says so.
  final Map<String, double> variantPrices;

  @override
  State<_QuickEditDialog> createState() => _QuickEditDialogState();
}

class _QuickEditDialogState extends State<_QuickEditDialog> {
  late final TextEditingController _price;
  late final TextEditingController _stock;

  String? _priceError;
  String? _stockError;

  /// A failure the server reported, shown above the buttons.
  String? _saveError;

  bool _saving = false;

  /// True after the first Save when a product-wide change would flatten
  /// differing prices. The second Save is the one that writes.
  bool _confirmingFlatten = false;

  /// The server's own ceiling: DecimalField(max_digits=8, decimal_places=2).
  static const double _maxPrice = 999999.99;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: _plain(widget.product.basePrice));
    _stock = TextEditingController(text: widget.currentStock.toString());
  }

  @override
  void dispose() {
    _price.dispose();
    _stock.dispose();
    super.dispose();
  }

  int get _variantCount => widget.variantPrices.length;

  bool get _pricesDiffer => widget.variantPrices.values.toSet().length > 1;

  double? get _typedPrice => double.tryParse(_price.text.trim());
  int? get _typedStock => int.tryParse(_stock.text.trim());

  bool get _priceChanged =>
      _typedPrice != null && _typedPrice != widget.product.basePrice;
  bool get _stockChanged =>
      _typedStock != null && _typedStock != widget.currentStock;

  /// Save has something to do and nothing wrong to do it with.
  bool get _canSave =>
      !_saving &&
      (_priceChanged || _stockChanged) &&
      _validatePrice() == null &&
      _validateStock() == null;

  String? _validatePrice() {
    final raw = _price.text.trim();
    if (raw.isEmpty) {
      return 'Enter a price.';
    }
    final value = double.tryParse(raw);
    if (value == null) {
      return 'Enter a number.';
    }
    if (value <= 0) {
      return 'The price has to be above zero.';
    }
    if (value > _maxPrice) {
      return 'The price cannot exceed ${formatPeso(_maxPrice)}.';
    }
    return null;
  }

  String? _validateStock() {
    final raw = _stock.text.trim();
    if (raw.isEmpty) {
      return 'Enter a stock count.';
    }
    final value = int.tryParse(raw);
    if (value == null) {
      return 'Enter a whole number.';
    }
    if (value < 0) {
      return 'Stock cannot be negative.';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _priceError = _validatePrice();
      _stockError = _validateStock();
      _saveError = null;
    });
    if (_priceError != null || _stockError != null) return;

    // A product-wide price change over differing prices erases information
    // that cannot be recovered from this side. Ask once, plainly, then do it.
    if (_priceChanged && _pricesDiffer && !_confirmingFlatten) {
      setState(() => _confirmingFlatten = true);
      return;
    }

    setState(() => _saving = true);
    final messages = <String>[];

    if (_stockChanged) {
      try {
        await widget.cubit.updateVariantStock(
          allocationKey: widget.allocationKey,
          stock: _typedStock!,
        );
        messages.add('Stock updated.');
      } on ApiException catch (error) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _saveError = error.isOffline
              ? 'Cannot reach the server, so nothing was changed.'
              : 'Stock was not saved. ${error.message}';
        });
        return;
      }
    }

    if (_priceChanged) {
      final outcome = await widget.cubit.updateProductPrice(
        productId: widget.product.id,
        price: _typedPrice!,
      );
      if (!mounted) return;
      if (!outcome.isComplete) {
        final failure = outcome.failure;
        final reason = failure == null
            ? ''
            : failure.isOffline
            ? ' The connection was lost.'
            : ' ${failure.message}';
        setState(() {
          _saving = false;
          _confirmingFlatten = false;
          // Honest about the half-done state: the table already shows it.
          _saveError = outcome.updated == 0
              ? 'The price was not changed.$reason'
              : 'Price set on ${outcome.updated} of ${outcome.total} '
                    'variants before it stopped.$reason The rest still show '
                    'the old price.';
        });
        return;
      }
      messages.add(
        _variantCount > 1
            ? 'Price set for all $_variantCount variants.'
            : 'Price updated.',
      );
    }

    if (!mounted) return;
    Navigator.pop(context, messages.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasVariants = widget.variantLabel.isNotEmpty;
    final priceLabel = _variantCount > 1
        ? 'Price · all $_variantCount variants'
        : 'Price';
    final stockLabel = hasVariants ? 'Stock · ${widget.variantLabel}' : 'Stock';

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The product, not the variant: the title covers both fields
              // and only one of them is variant-scoped.
              Text(
                widget.product.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              _Field(
                label: priceLabel,
                error: _priceError,
                child: TextField(
                  controller: _price,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {
                    _priceError = null;
                    _confirmingFlatten = false;
                  }),
                  decoration: _decoration(prefix: 'PHP '),
                ),
              ),
              if (_pricesDiffer) ...[
                const SizedBox(height: 10),
                _FlattenWarning(
                  prices: widget.variantPrices,
                  confirming: _confirmingFlatten,
                  newPrice: _typedPrice,
                ),
              ],
              const SizedBox(height: 16),
              _Field(
                label: stockLabel,
                error: _stockError,
                child: TextField(
                  controller: _stock,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _stockError = null),
                  decoration: _decoration(),
                ),
              ),
              AnimatedSize(
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                alignment: Alignment.topLeft,
                child: _saveError == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _ErrorBanner(message: _saveError!),
                      ),
              ),
              const SizedBox(height: 18),
              // Wrapped rather than a Row: the Save label grows to "Set all
              // 18 to PHP 3,200.00" when confirming, and beside Cancel that
              // overflowed a 420pt dialog by 177px. The QR dialog learned the
              // same lesson; see section 10 of DESIGN_GUIDELINES.md.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, null),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.primary.withValues(
                        alpha: 0.35,
                      ),
                      disabledForegroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _confirmingFlatten && _priceChanged
                                ? 'Set all $_variantCount to '
                                      '${formatPeso(_typedPrice ?? 0)}'
                                : 'Save',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration({String? prefix}) => InputDecoration(
    isDense: true,
    filled: true,
    fillColor: AppColors.inputFill,
    prefixText: prefix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
    ),
  );

  /// "3200" rather than "3200.0", so the field opens looking typed by a
  /// person.
  static String _plain(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

/// Says what a product-wide price would erase, before it does.
class _FlattenWarning extends StatelessWidget {
  const _FlattenWarning({
    required this.prices,
    required this.confirming,
    required this.newPrice,
  });

  final Map<String, double> prices;
  final bool confirming;
  final double? newPrice;

  @override
  Widget build(BuildContext context) {
    final sorted = prices.values.toList()..sort();
    final low = formatPeso(sorted.first);
    final high = formatPeso(sorted.last);
    final count = prices.length;
    final tail = confirming && newPrice != null
        ? ' Saving sets all $count to ${formatPeso(newPrice!)}.'
        : ' Changing the price here sets all $count to the same amount.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.statusUpcoming.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.statusUpcoming,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Prices differ across this product\'s $count variants, '
              'from $low to $high.$tail',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.statusUpcoming,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.error});

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
        AnimatedSize(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          alignment: Alignment.topLeft,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 2),
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontSize: 12,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.error,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
