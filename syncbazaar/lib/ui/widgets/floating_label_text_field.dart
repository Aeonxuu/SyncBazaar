import 'package:flutter/material.dart';

class FloatingLabelTextField extends StatefulWidget {
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
  State<FloatingLabelTextField> createState() => _FloatingLabelTextFieldState();
}

class _FloatingLabelTextFieldState extends State<FloatingLabelTextField> {
  late bool _isObscured;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(8);
    final fillColor = colorScheme.primary.withValues(alpha: 0.08);

    return SizedBox(
      height: 56,
      child: TextFormField(
        controller: widget.controller,
        obscureText: _isObscured,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        cursorColor: colorScheme.primary,
        style: theme.textTheme.bodyLarge?.copyWith(color: colorScheme.primary),
        decoration: InputDecoration(
          labelText: widget.labelText,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          floatingLabelAlignment: FloatingLabelAlignment.start,
          alignLabelWithHint: false,
          filled: true,
          fillColor: fillColor,
          prefixIcon: widget.prefixIcon == null
              ? null
              : Icon(widget.prefixIcon, color: colorScheme.primary),
          suffixIcon: widget.obscureText
              ? IconButton(
                  tooltip: _isObscured ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() {
                      _isObscured = !_isObscured;
                    });
                  },
                  icon: Icon(
                    _isObscured
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: colorScheme.primary,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          labelStyle: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.primary.withValues(alpha: 0.85),
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
