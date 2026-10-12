import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../../../../models/user.dart';

/// Who is ringing up the sale, as a compact filled button.
///
/// Sized to its label rather than stretched to a field's width: it sits beside
/// the "Current order" heading and only has to say one name. Tapping opens a
/// short menu of the people who can be chosen, with a tick on the current one.
class SellerButton extends StatefulWidget {
  const SellerButton({
    super.key,
    required this.sellers,
    required this.selected,
    required this.onSelected,
  });

  final List<AppUser> sellers;
  final AppUser selected;
  final ValueChanged<AppUser> onSelected;

  @override
  State<SellerButton> createState() => _SellerButtonState();
}

class _SellerButtonState extends State<SellerButton> {
  bool _open = false;

  Future<void> _showMenu() async {
    final button = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (button == null || overlay == null) return;

    // Anchored under the button and right-aligned with it, since the button
    // sits against the panel's right edge and a menu opening rightwards would
    // run off it.
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx + button.size.width - 200,
      topLeft.dy + button.size.height + 6,
      overlay.size.width - (topLeft.dx + button.size.width),
      0,
    );

    setState(() => _open = true);
    final picked = await showMenu<AppUser>(
      context: context,
      position: position,
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      items: [
        for (final person in widget.sellers)
          PopupMenuItem<AppUser>(
            value: person,
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: person.id == widget.selected.id
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: person.id == widget.selected.id
                          ? AppColors.primary
                          : AppColors.text,
                    ),
                  ),
                ),
                if (person.id == widget.selected.id)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
      ],
    );
    if (mounted) setState(() => _open = false);
    if (picked != null) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _showMenu,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline_rounded, size: 18),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              widget.selected.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          AnimatedRotation(
            turns: _open ? 0.5 : 0,
            duration: AppMotion.feedback,
            curve: AppMotion.easeOut,
            child: const Icon(Icons.expand_more_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
