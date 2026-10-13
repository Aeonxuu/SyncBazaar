import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/colors.dart';

/// A one-digit-per-box code entry, e.g. for a 6-digit email verification
/// code. Typing a digit advances focus to the next box; backspace on an
/// empty box steps back to the previous one and clears it.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.length,
    required this.onChanged,
    this.initialValue = '',
    this.autofocus = true,
  });

  final int length;
  final ValueChanged<String> onChanged;

  /// Prefills the boxes, e.g. re-showing a rejected code so the user can fix
  /// a digit instead of retyping all of it.
  final String initialValue;
  final bool autofocus;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (i) {
      final char = i < widget.initialValue.length ? widget.initialValue[i] : '';
      return TextEditingController(text: char);
    });
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _emit() => widget.onChanged(_controllers.map((c) => c.text).join());

  void _handleChanged(int index, String value) {
    // Autofill or a paste can hand a whole code to one box at once.
    if (value.length > 1) {
      final digits = value.split('');
      for (var i = 0; i < digits.length && index + i < widget.length; i++) {
        _controllers[index + i].text = digits[i];
      }
      final nextIndex = (index + digits.length).clamp(0, widget.length - 1);
      _focusNodes[nextIndex].requestFocus();
      _emit();
      return;
    }
    if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _emit();
  }

  void _handleBackspaceOnEmpty(int index) {
    if (index == 0) {
      return;
    }
    _controllers[index - 1].clear();
    _focusNodes[index - 1].requestFocus();
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < widget.length; i++)
          _OtpBox(
            controller: _controllers[i],
            focusNode: _focusNodes[i],
            autofocus: widget.autofocus && i == 0,
            onChanged: (value) => _handleChanged(i, value),
            onBackspaceOnEmpty: () => _handleBackspaceOnEmpty(i),
          ),
      ],
    );
  }
}

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.onChanged,
    required this.onBackspaceOnEmpty,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceOnEmpty;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  // Purple marks focus, same rule as every other field in this flow; a
  // filled box (grey, no border) is how a box says "done" without needing a
  // checkmark of its own.
  static const _restingBorderColor = Color(0x29000000);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final hasDigit = widget.controller.text.isNotEmpty;
    final radius = BorderRadius.circular(10);

    return SizedBox(
      width: 54,
      height: 72,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              widget.controller.text.isEmpty) {
            widget.onBackspaceOnEmpty();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 6, // Wide enough that a full-code paste is not truncated.
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          cursorColor: AppColors.primary,
          // Left at the field's default height, the cursor reaches past the
          // digit glyph's own bounding box -- fine with room to spare in an
          // ordinary text field, but this box has none, so the cursor poked
          // out through the top and bottom edges. Capped to just over the
          // font size instead of the default, plus a little breathing room
          // from `contentPadding` rather than the zero it had.
          cursorHeight: 28,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            counterText: '',
            filled: hasDigit,
            fillColor: AppColors.inputFill,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
