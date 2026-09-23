import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/settings/catalog_cubit.dart';
import '../../../core/constants/colors.dart';
import '../../../core/constants/motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/brand.dart';
import '../../../models/category.dart';
import '../../../models/user.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/custom_card.dart';

/// The vendor's own product categories and brands.
///
/// Pulled out of the product form, which only ever needs to *pick* one of
/// these — creating, renaming and deleting them is a separate task with its
/// own moment, not something to ask of someone who is mid-way through adding
/// a product. This screen is that moment's home, the same way Payment
/// Methods is for the vendor's payment list.
///
/// Header / hairline / rows / hairline / inline create field, one panel per
/// list. Renaming happens in the row itself rather than behind a second
/// dialog, and creating happens in an always-visible field rather than
/// behind an "Add" dialog — recognition over recall, and the fewer surfaces
/// stacked on this screen the better (Section 10 of the design guidelines:
/// a modal-on-modal costs an extra open/close round trip for no reason).
/// The one dialog left is the delete confirmation, which is destructive and
/// earns the extra step.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = widget.user.isAdminOrOwner;

    if (!canManage) {
      return const Center(child: Text('Access denied'));
    }

    return BlocBuilder<CatalogCubit, CatalogState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Catalog',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Categories and brands products can be filed under',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.black45,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _body(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, CatalogState state) {
    if (!state.isRemote) {
      // The demo build has no vendor to hold a list for — nothing wrong
      // here, just nothing to manage until there is a server.
      return const Center(
        child: Text(
          'Categories and brands are managed on the server, once you are '
          'signed in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black45),
        ),
      );
    }
    if (!state.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CatalogPanel<Category>(
            title: 'Categories',
            emptyIcon: Icons.sell_outlined,
            addHint: 'New category',
            entries: state.categories,
            nameOf: (category) => category.name,
            productCountOf: (category) =>
                state.productCountByCategoryId[category.id] ?? 0,
            error: state.categoryError,
            onAdd: (name) => context.read<CatalogCubit>().addCategory(name),
            onRename: (category, name) =>
                context.read<CatalogCubit>().renameCategory(category, name),
            onRemove: (category) => _confirmRemove(
              context,
              name: category.name,
              noun: 'category',
              onConfirm: () =>
                  context.read<CatalogCubit>().removeCategory(category),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _CatalogPanel<Brand>(
            title: 'Brands',
            emptyIcon: Icons.local_offer_outlined,
            addHint: 'New brand',
            entries: state.brands,
            nameOf: (brand) => brand.name,
            productCountOf: (brand) =>
                state.productCountByBrandId[brand.id] ?? 0,
            error: state.brandError,
            onAdd: (name) => context.read<CatalogCubit>().addBrand(name),
            onRename: (brand, name) =>
                context.read<CatalogCubit>().renameBrand(brand, name),
            onRemove: (brand) => _confirmRemove(
              context,
              name: brand.name,
              noun: 'brand',
              onConfirm: () => context.read<CatalogCubit>().removeBrand(brand),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context, {
    required String name,
    required String noun,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete $name?',
      message:
          'Products filed under this $noun will show none — nothing else '
          'about them changes. This cannot be undone.',
      confirmLabel: 'Delete',
      tone: ConfirmationTone.destructive,
    );
    if (!confirmed) {
      return;
    }
    await onConfirm();
  }
}

/// One flat card: header with a quiet count, a hairline-separated list of
/// rows, and an always-visible create field at the foot. Generic over
/// [Category]/[Brand] since the two are structurally identical — a name and
/// a server-scoped CRUD endpoint — so one widget serves both.
class _CatalogPanel<T> extends StatefulWidget {
  const _CatalogPanel({
    required this.title,
    required this.emptyIcon,
    required this.addHint,
    required this.entries,
    required this.nameOf,
    required this.productCountOf,
    required this.error,
    required this.onAdd,
    required this.onRename,
    required this.onRemove,
  });

  final String title;
  final IconData emptyIcon;
  final String addHint;
  final List<T> entries;
  final String Function(T) nameOf;
  final int Function(T) productCountOf;
  final String? error;
  final Future<void> Function(String name) onAdd;
  final Future<void> Function(T entry, String name) onRename;
  final ValueChanged<T> onRemove;

  @override
  State<_CatalogPanel<T>> createState() => _CatalogPanelState<T>();
}

class _CatalogPanelState<T> extends State<_CatalogPanel<T>> {
  late final TextEditingController _addController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _addController = TextEditingController();
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _submitAdd() async {
    final name = _addController.text.trim();
    if (name.isEmpty || _submitting) {
      return;
    }
    setState(() => _submitting = true);
    await widget.onAdd(name);
    if (!mounted) return;
    setState(() => _submitting = false);
    // Only clears on success — [widget.error] tells us that indirectly: a
    // fresh build after a failed add still shows what was typed, so the
    // vendor can fix it rather than retype it.
    if (widget.error == null) {
      _addController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${formatCount(widget.entries.length)})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black38,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: widget.entries.isEmpty
                ? _emptyState(theme)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: widget.entries.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (context, index) {
                      final entry = widget.entries[index];
                      return _CatalogRow<T>(
                        key: ValueKey((T, widget.nameOf(entry), index)),
                        entry: entry,
                        name: widget.nameOf(entry),
                        productCount: widget.productCountOf(entry),
                        onRename: (name) => widget.onRename(entry, name),
                        onRemove: () => widget.onRemove(entry),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addController,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.words,
                        style: theme.textTheme.bodyMedium,
                        onSubmitted: (_) => _submitAdd(),
                        decoration: _catalogFieldDecoration(
                          hint: widget.addHint,
                          hasError: widget.error != null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AddButton(
                      onPressed: _submitting ? null : _submitAdd,
                      busy: _submitting,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: AppMotion.small,
                  curve: AppMotion.easeOut,
                  alignment: Alignment.topLeft,
                  child: widget.error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            widget.error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.emptyIcon, size: 30, color: Colors.black26),
          const SizedBox(height: 8),
          Text(
            'None yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}

/// One row: a name and its product count, or — mid-rename — a text field in
/// the same place. A [StatefulWidget] purely for that local edit toggle,
/// which must survive the panel rebuilding out from under it every time any
/// row's rename/delete reloads the whole list.
class _CatalogRow<T> extends StatefulWidget {
  const _CatalogRow({
    super.key,
    required this.entry,
    required this.name,
    required this.productCount,
    required this.onRename,
    required this.onRemove,
  });

  final T entry;
  final String name;
  final int productCount;
  final ValueChanged<String> onRename;
  final VoidCallback onRemove;

  @override
  State<_CatalogRow<T>> createState() => _CatalogRowState<T>();
}

class _CatalogRowState<T> extends State<_CatalogRow<T>> {
  bool _editing = false;
  TextEditingController? _controller;

  void _startEditing() {
    setState(() {
      _editing = true;
      _controller = TextEditingController(text: widget.name);
    });
  }

  void _cancelEditing() {
    setState(() {
      _editing = false;
      _controller?.dispose();
      _controller = null;
    });
  }

  void _confirmEditing() {
    final name = _controller?.text.trim() ?? '';
    if (name.isNotEmpty && name != widget.name) {
      widget.onRename(name);
    }
    _cancelEditing();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    style: theme.textTheme.bodyMedium,
                    onSubmitted: (_) => _confirmEditing(),
                    decoration: _catalogFieldDecoration(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.name, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 2),
                      Text(
                        widget.productCount == 0
                            ? 'No products'
                            : '${formatCount(widget.productCount)} '
                                  'product${widget.productCount == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_editing) ...[
            _QuietRowIcon(
              icon: Icons.check_rounded,
              tooltip: 'Save',
              hoverColor: AppColors.primary,
              onPressed: _confirmEditing,
            ),
            _QuietRowIcon(
              icon: Icons.close_rounded,
              tooltip: 'Cancel',
              hoverColor: AppColors.error,
              onPressed: _cancelEditing,
            ),
          ] else ...[
            _QuietRowIcon(
              icon: Icons.edit_outlined,
              tooltip: 'Rename',
              hoverColor: AppColors.primary,
              onPressed: _startEditing,
            ),
            _QuietRowIcon(
              icon: Icons.delete_outline,
              tooltip: 'Delete',
              hoverColor: AppColors.error,
              onPressed: widget.onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

const double _rowActionSize = 34;
const double _actionIconSize = 17;

/// Rests at `Colors.black38`, animates to its semantic colour on hover — the
/// same recipe used for row actions across the app (inventory's product
/// rows), so a list of rows doesn't look hazardous until the moment someone
/// actually means to act on one.
class _QuietRowIcon extends StatefulWidget {
  const _QuietRowIcon({
    required this.icon,
    required this.tooltip,
    required this.hoverColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color hoverColor;
  final VoidCallback? onPressed;

  @override
  State<_QuietRowIcon> createState() => _QuietRowIconState();
}

class _QuietRowIconState extends State<_QuietRowIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: IconButton(
        onPressed: widget.onPressed,
        splashRadius: 18,
        tooltip: widget.tooltip,
        constraints: const BoxConstraints(
          minWidth: _rowActionSize,
          minHeight: _rowActionSize,
        ),
        padding: EdgeInsets.zero,
        icon: TweenAnimationBuilder<Color?>(
          duration: AppMotion.feedback,
          curve: AppMotion.easeOut,
          tween: ColorTween(
            begin: Colors.black38,
            end: widget.onPressed == null
                ? Colors.black26
                : _hovered
                ? widget.hoverColor
                : Colors.black38,
          ),
          builder: (context, color, _) =>
              Icon(widget.icon, size: _actionIconSize, color: color),
        ),
      ),
    );
  }
}

/// The panel's one primary action, sized to the "secondary action button"
/// tier (Section 4) — it commits a create, but it's not the page's CTA.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Text('Add'),
    );
  }
}

InputDecoration _catalogFieldDecoration({String? hint, bool hasError = false}) {
  const radius = BorderRadius.all(Radius.circular(8));
  OutlineInputBorder border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: radius,
      borderSide: color == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.black38),
    isDense: true,
    filled: true,
    fillColor: AppColors.inputFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(hasError ? AppColors.error : Colors.transparent, 1),
    enabledBorder: border(hasError ? AppColors.error : Colors.transparent, 1),
    focusedBorder: border(hasError ? AppColors.error : AppColors.primary, 1.5),
  );
}
