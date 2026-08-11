import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';

/// Label above an input, with the spacing used across the whole pre-bazaar
/// form so every field starts on the same rhythm.
class PreBazaarFormField extends StatelessWidget {
  const PreBazaarFormField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
            fontWeight: FontWeight.w600,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Shared input styling for the pre-bazaar form.
///
/// Neutral [AppColors.inputFill] rather than the old purple-tinted fill, and
/// 12/12 padding so text fields, dropdown triggers and the date picker all
/// resolve to the same 44px height and line up in a row.
InputDecoration preBazaarInputDecoration({
  String? hint,
  bool hasError = false,
}) {
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
