import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One thing the pod card reports: a warning from the shade, or the alerts the
/// pod itself is beeping about.
class PodWarningLine {
  const PodWarningLine({
    required this.dismissKey,
    required this.icon,
    required this.title,
    required this.message,
    required this.critical,
    required this.onDismiss,
    this.action,
  });

  final String dismissKey;
  final IconData icon;
  final String title;
  final String message;

  /// Delivery has stopped or is about to: drawn in the danger tone, and it turns
  /// the whole card red.
  final bool critical;

  final VoidCallback onDismiss;

  /// A control under the message (silencing the pod's alerts).
  final Widget? action;
}

/// Every standing pod warning in ONE card instead of a stack of grey panels:
/// tinted amber, or red as soon as one of them means insulin is not arriving,
/// with a header that opens the pump page and a close button on every line.
class PodWarningCard extends StatelessWidget {
  const PodWarningCard({super.key, required this.lines, required this.onOpen});

  final List<PodWarningLine> lines;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    final tone = lines.any((line) => line.critical)
        ? context.danger
        : context.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tone.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tone.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, tone),
            for (final line in lines) _PodWarningLineView(line: line),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Color tone) {
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Row(
          children: [
            Icon(PhosphorIconsFill.warningCircle, size: 20, color: tone),
            const SizedBox(width: 8),
            Expanded(
              child: LocaleText(
                'overview.pod_card.title',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
            ),
            LocaleText(
              'overview.pod_card.open',
              style: TextStyle(fontSize: 13, color: tone),
            ),
            Icon(PhosphorIconsBold.caretRight, size: 16, color: tone),
          ],
        ),
      ),
    );
  }
}

/// One line of the card: its own icon, the title and what to do about it, and a
/// close button. A swipe dismisses it too.
class _PodWarningLineView extends StatelessWidget {
  const _PodWarningLineView({required this.line});

  final PodWarningLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = line.critical ? context.danger : context.warning;
    return Dismissible(
      key: ValueKey<String>(line.dismissKey),
      onDismissed: (_) => line.onDismiss(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(line.icon, size: 20, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(child: _text(scheme)),
            IconButton(
              icon: const Icon(PhosphorIconsBold.x, size: 18),
              tooltip: Locales.string(context, 'overview.pod_card.dismiss'),
              visualDensity: VisualDensity.compact,
              onPressed: line.onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  Widget _text(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          line.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          line.message,
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
        ?line.action,
      ],
    );
  }
}
