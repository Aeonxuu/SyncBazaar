import 'package:flutter/material.dart';

import '../../core/constants/colors.dart';
import '../../core/constants/motion.dart';

/// A small icon that explains something when hovered or tapped.
///
/// For help that most people do not need most of the time. Printing it under
/// every label makes the whole dialog read as instructions; here it is one
/// glyph, and the sentence appears only for someone who asks. Hover works with
/// a mouse and a tap with a finger, which is why both are wired: a tablet has
/// no hover.
///
/// An icon that opens nothing would be a lie, so this is only used where there
/// is a message to show. The message is also its accessibility label, so a
/// screen reader gets the sentence without having to trigger a tooltip.
class InfoHint extends StatefulWidget {
  const InfoHint({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.semanticLabel,
  });

  /// What to say.
  final String message;

  /// The glyph: an "i" by default, a padlock where the thing is locked.
  final IconData icon;

  /// Overrides the spoken form, which is [message] by default.
  final String? semanticLabel;

  @override
  State<InfoHint> createState() => _InfoHintState();
}

class _InfoHintState extends State<InfoHint> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? widget.message,
      child: ExcludeSemantics(
        child: Tooltip(
          message: widget.message,
          triggerMode: TooltipTriggerMode.tap,
          showDuration: const Duration(seconds: 5),
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: MouseRegion(
            cursor: SystemMouseCursors.help,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            // A 32px target around a 16px glyph: the icon is quiet, the thing
            // to hit is not.
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: AnimatedSwitcher(
                  duration: AppMotion.feedback,
                  child: Icon(
                    widget.icon,
                    key: ValueKey(_hovered),
                    size: 16,
                    color: _hovered ? AppColors.primary : Colors.black38,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
