import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';

/// The search field above a list of bazaars.
///
/// Unlabelled: the placeholder already says what it is for, and a caption
/// above it would repeat the same words. Capped rather than stretched — a
/// field the width of the window is harder to aim at, not easier.
///
/// White on the page's grey with a hairline border, which is the one input in
/// the app that sits *on* a background rather than inside a card, so it reads
/// as raised instead of recessed.
class BazaarSearchField extends StatelessWidget {
  const BazaarSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search bazaars by name, status, or date',
    this.maxWidth = 360,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final String hint;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black38),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.black45),
          // Appears only once there is something to clear, so the field is
          // not permanently offering to undo nothing.
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  splashRadius: 18,
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFEAEAEF)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFEAEAEF)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
