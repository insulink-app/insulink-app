import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// How loudly a notice speaks: something went wrong, or something merely needs
/// knowing (a temporary basal rate, silent mode).
enum NoticeTone { danger, warning }

/// A tinted strip that stays until something replaces it: the tone's soft fill
/// without a rim, its icon in the tone colour, and optionally a small pill on
/// the right that ends what the banner reports ("Beenden").
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.icon,
    required this.tone,
    required this.child,
    this.actionLabelKey,
    this.onAction,
    this.onTap,
  });

  final IconData icon;
  final NoticeTone tone;
  final Widget child;

  /// Label of the pill on the right; no pill without it.
  final String? actionLabelKey;
  final VoidCallback? onAction;

  /// A tap on the whole strip.
  final VoidCallback? onTap;

  Color _toneColor(InsulinkColors colors) =>
      tone == NoticeTone.danger ? colors.low : colors.high;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final toneColor = _toneColor(colors);
    return Material(
      color: tone == NoticeTone.danger ? colors.lowSoft : colors.highSoft,
      borderRadius: BorderRadius.circular(InkRadius.panel),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              actionLabelKey == null ? 16 : 8,
              8,
            ),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 18, color: toneColor),
                Expanded(child: child),
                if (actionLabelKey != null) _pill(toneColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(Color toneColor) {
    return TextButton(
      onPressed: onAction,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: toneColor.withValues(alpha: 0.16),
        foregroundColor: toneColor,
        textStyle: InkText.label.copyWith(fontWeight: FontWeight.w700),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: LocaleText(actionLabelKey!),
    );
  }
}
