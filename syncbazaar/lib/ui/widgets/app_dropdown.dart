import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// The app's form dropdown.
///
/// One implementation so every dropdown in SyncBazaar behaves identically
/// (Jakob's law, applied inward): the menu is pinned to the trigger's exact
/// width, the current value is check-marked *inside* the open menu, the
/// chevron rotates to report open/closed, and the trigger takes a purple
/// border while open.
///
/// Preferred over `DropdownButtonFormField`, which can't mark the current
/// value in its menu, can't react to being open, and sizes its menu
/// independently of the field it belongs to — so two of them on one screen
/// never quite line up.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    required this.hint,
    this.leadingIcon,
    this.enabled = true,
    this.hasError = false,
    this.menuMaxHeight = 260,
  });

  final List<T> options;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  /// Shown when nothing is selected — or, when [options] is empty, when there
  /// is nothing *to* select. Say what to do about it rather than showing a
  /// blank field.
  final String hint;

  final IconData? leadingIcon;
  final bool enabled;
  final bool hasError;

  /// Caps the open menu so a long list scrolls inside itself instead of
  /// covering the form it belongs to.
  final double menuMaxHeight;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  bool _isOpen = false;

  /// Opens the menu with a position and height worked out from the space
  /// actually available around the trigger.
  ///
  /// `PopupMenuButton` can't do this. Its layout runs `_fitInsideScreen`,
  /// which — when the menu doesn't fit below — slides it *up* until it does,
  /// straight over the field that opened it. Near the bottom of a form that's
  /// almost always, so the control you just tapped disappears behind its own
  /// options. Driving `showMenu` directly lets the menu cap its height to the
  /// gap below (scrolling inside it instead of growing), and flip above only
  /// when below is genuinely too tight.
  Future<void> _open() async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    const gap = 6.0;
    const screenPadding = 12.0;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final triggerBottom = topLeft.dy + box.size.height;

    final spaceBelow =
        overlay.size.height - triggerBottom - gap - screenPadding;
    final spaceAbove = topLeft.dy - gap - screenPadding;
    // Only flip when below can't show a couple of rows; a short menu that
    // fits should always drop downward, which is what people expect.
    final openUpward = spaceBelow < 120 && spaceAbove > spaceBelow;
    final available = openUpward ? spaceAbove : spaceBelow;
    final maxHeight = available.clamp(96.0, widget.menuMaxHeight);

    setState(() => _isOpen = true);
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        openUpward ? topLeft.dy - gap - maxHeight : triggerBottom + gap,
        overlay.size.width - topLeft.dx - box.size.width,
        0,
      ),
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
        maxHeight: maxHeight,
      ),
      initialValue: widget.selected,
      color: AppColors.surface,
      elevation: 3,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      items: [
        for (final option in widget.options)
          PopupMenuItem<T>(
            value: option,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // The closed field already shows the current value, but once
                // the menu covers it you shouldn't have to remember what it
                // said.
                SizedBox(
                  width: 22,
                  child: option == widget.selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.primary,
                        )
                      : null,
                ),
                Expanded(
                  child: Text(
                    widget.labelOf(option),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: option == widget.selected
                          ? AppColors.primary
                          : AppColors.text,
                      fontWeight: option == widget.selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (!mounted) return;
    setState(() => _isOpen = false);
    if (selected != null) widget.onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final isEnabled = widget.enabled && widget.options.isNotEmpty;

    return Semantics(
      button: true,
      enabled: isEnabled,
      child: InkWell(
        onTap: isEnabled ? _open : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: AppMotion.small,
          curve: AppMotion.easeOut,
          // 12/12 padding gives the same 44px height as the text fields it
          // sits beside, so a column of mixed inputs lines up.
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.inputFill,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.hasError
                  ? AppColors.error
                  : _isOpen
                  ? AppColors.primary
                  : Colors.transparent,
              width: _isOpen ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (widget.leadingIcon != null) ...[
                Icon(widget.leadingIcon, size: 17, color: Colors.black45),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  selected == null ? widget.hint : widget.labelOf(selected),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: selected == null || !isEnabled
                        ? Colors.black38
                        : AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: AppMotion.small,
                curve: AppMotion.easeOut,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: isEnabled ? Colors.black45 : Colors.black26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
