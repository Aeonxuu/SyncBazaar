import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/constants/motion.dart';
import '../legal_documents.dart';

/// Reads one of the Settings reference documents.
///
/// A dialog rather than a pushed screen: these are looked at once, usually to
/// settle a question, and a dialog returns you to where you were without a
/// navigation step to undo. It follows the shell every other modal here uses so
/// it does not read as a different app.
Future<void> showInfoDocument({
  required BuildContext context,
  required InfoDocument document,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _InfoDocumentDialog(document: document),
  );
}

class _InfoDocumentDialog extends StatelessWidget {
  const _InfoDocumentDialog({required this.document});

  final InfoDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.97, end: 1),
        duration: AppMotion.entrance,
        curve: AppMotion.easeOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: ConstrainedBox(
          // Wider than a confirm dialog and capped in height: this is reading
          // matter, and a line much longer than this is hard to track back to
          // the start of the next one.
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context, theme),
              const Divider(height: 1, color: AppColors.border),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final section in document.sections) ...[
                        Text(
                          section.heading,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final paragraph in section.body)
                          _Paragraph(text: paragraph),
                        const SizedBox(height: 18),
                      ],
                      Text(
                        'Last updated ${document.updated}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  document.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            icon: const Icon(Icons.close_rounded, size: 17, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

/// One paragraph, or one bullet when the line starts with "- ".
class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.black87,
      height: 1.5,
    );
    final isBullet = text.startsWith('- ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: isBullet
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 10, left: 2),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: Text(text.substring(2), style: style)),
              ],
            )
          : Text(text, style: style),
    );
  }
}
