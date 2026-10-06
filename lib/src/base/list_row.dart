import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// What a [ListRow]'s icon disc says: an entry (accent), a neutral action, or
/// one that throws something away (danger, title in the danger colour too).
enum ListRowTone { accent, neutral, danger }

/// One entry of a list that sits in an [InkPanel.list]: a 40 px icon disc, a
/// title over an optional subtitle, and an optional trailing part (a
/// [ListRowMeta], a value, a remove button). At least 68 px high.
///
/// Dangerous actions (stop the sensor, forget the pod) are rows like this at
/// the bottom of a page, never outlined buttons at its top.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.tone = ListRowTone.accent,
    this.onTap,
    this.glyphColor,
    this.subtitleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final ListRowTone tone;
  final VoidCallback? onTap;

  /// Overrides the tone's colour for the disc, e.g. a glucose zone colour.
  final Color? glyphColor;

  /// Overrides the muted subtitle, e.g. a value in its zone colour.
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          child: Row(
            spacing: 14,
            children: [
              _disc(colors),
              Expanded(child: _texts(colors)),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  Color _glyphColor(InsulinkColors colors) =>
      glyphColor ??
      switch (tone) {
        ListRowTone.accent => colors.accent,
        ListRowTone.neutral => colors.text,
        ListRowTone.danger => colors.low,
      };

  /// The disc is the glyph's own colour at 12 %, or the text colour at 6 % for
  /// a neutral row, so a red row is red all through.
  Widget _disc(InsulinkColors colors) {
    final glyph = _glyphColor(colors);
    final alpha = tone == ListRowTone.neutral ? 0.06 : 0.12;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: glyph.withValues(alpha: alpha),
      ),
      child: Icon(icon, size: 20, color: glyph),
    );
  }

  Widget _texts(InsulinkColors colors) {
    final titleColor = tone == ListRowTone.danger ? colors.low : colors.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: InkText.rowTitle.copyWith(color: titleColor),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: subtitleColor == null
                ? InkText.label.copyWith(color: colors.muted)
                : InkText.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: subtitleColor,
                  ),
          ),
      ],
    );
  }
}

/// The right end of a dated [ListRow]: the day (Heute, Gestern, So., 4. Okt.)
/// small and muted over the time of day in bold.
class ListRowMeta extends StatelessWidget {
  const ListRowMeta({super.key, required this.date, required this.time});

  final String date;
  final String time;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        Text(date, style: InkText.caption.copyWith(color: colors.muted)),
        Text(time, style: InkText.row.copyWith(color: colors.text)),
      ],
    );
  }
}
