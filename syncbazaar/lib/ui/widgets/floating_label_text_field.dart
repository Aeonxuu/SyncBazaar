import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';

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

  // Outline-only: purple marks focus, not "this is a text field". Every other
  // input in the app made this same move away from a purple-tinted fill (see
  // DESIGN_GUIDELINES.md's "Input fills are neutral, not purple") because a
  // field that is purple all the time stops telling you anything by being
  // purple. Here there is no fill at all rather than the usual neutral gray,
  // since the card behind it is already white — a filled box would float on
  // top of the card instead of reading as a hole punched in it.
  static const _restingBorderColor = Color(0x29000000);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final radius = BorderRadius.circular(8);

    return SizedBox(
      height: 56,
      child: TextFormField(
        controller: widget.controller,
        obscureText: _isObscured,
        keyboardType: widget.keyboardType,
        validator: widget.validator,
        cursorColor: colorScheme.primary,
        style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.text),
        decoration: InputDecoration(
          labelText: widget.labelText,
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          floatingLabelAlignment: FloatingLabelAlignment.start,
          alignLabelWithHint: false,
          filled: false,
          prefixIcon: widget.prefixIcon == null
              ? null
              : Icon(widget.prefixIcon, color: Colors.black45),
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
                    color: Colors.black45,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 18,
          ),
          labelStyle: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.black54,
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
            borderSide: const BorderSide(color: _restingBorderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: const BorderSide(color: _restingBorderColor),
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
