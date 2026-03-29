import 'package:flutter/material.dart';

class FloatingLabelTextField extends StatelessWidget {
  const FloatingLabelTextField({
    super.key,
    required this.labelText,
    required this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.prefixIcon,
  });

  final String labelText;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final FormFieldValidator<String>? validator;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(8);
    final fillColor = colorScheme.primary.withOpacity(0.08);

    return SizedBox(
      height: 56,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        cursorColor: colorScheme.primary,
        style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.primary),
        decoration: InputDecoration(
          labelText: labelText,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          floatingLabelAlignment: FloatingLabelAlignment.start,
          alignLabelWithHint: false,
          filled: true,
          fillColor: fillColor,
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, color: colorScheme.primary),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          labelStyle: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.primary.withOpacity(0.85),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          floatingLabelStyle: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colorScheme.error, width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: colorScheme.error, width: 1.6),
          ),
        ),
      ),
    );
  }
}
