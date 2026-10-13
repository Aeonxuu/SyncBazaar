import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.onChanged,
    this.enabled = true,
    this.errorText,
    this.helperText,
    this.inputFormatters,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final String labelText;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final FormFieldValidator<String>? validator;
  final IconData? prefixIcon;
  final ValueChanged<String>? onChanged;

  /// False greys the field and stops input, for while a request that uses its
  /// value is in flight.
  final bool enabled;

  /// A message under the field, drawn in the error colour with the error
  /// border. Inline, next to the input, rather than in a SnackBar.
  final String? errorText;

  /// Quiet guidance under the field. Replaced by [errorText] when there is one.
  final String? helperText;

  /// For limiting what can be typed, e.g. a length the server will accept.
  final List<TextInputFormatter>? inputFormatters;

  /// Takes focus when it first appears, bringing up the keyboard.
  final bool autofocus;

  /// What Enter does on a soft keyboard, and the hint for the key's label:
  /// [TextInputAction.next] for a field with another one below it,
  /// [TextInputAction.done] for the last.
  final TextInputAction? textInputAction;

  /// Called when Enter is pressed. Left null, Enter does nothing.
  final ValueChanged<String>? onSubmitted;

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

    final hasNote = widget.errorText != null || widget.helperText != null;
    final field = TextFormField(
      controller: widget.controller,
      obscureText: _isObscured,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      cursorColor: colorScheme.primary,
      style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.text),
      decoration: InputDecoration(
        labelText: widget.labelText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        // Quiet guidance, not content: the theme's default is as dark as the
        // value being typed.
        helperStyle: theme.textTheme.bodySmall?.copyWith(color: Colors.black45),
        helperMaxLines: 2,
        errorMaxLines: 2,
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
    );

    // Pinned to 56 only while there is nothing under it; a note needs the
    // room, and a fixed height would clip it. The same SizedBox either way, so
    // a note appearing does not rebuild the field and drop its focus.
    return SizedBox(height: hasNote ? null : 56, child: field);
  }
}
