import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';

/// Gewähltes Zeitfenster einer Sport-Detailseite: ein Preset (Tage), „Alle"
/// oder ein eigener Datumsbereich. Reine Werteklasse; die Seiten filtern ihre
/// Daten damit.
class SportRange {
  final int? days;
  final DateTimeRange? custom;

  const SportRange._(this.days, this.custom);
  const SportRange.all() : this._(null, null);
  const SportRange.preset(int presetDays) : this._(presetDays, null);
  const SportRange.custom(DateTimeRange range) : this._(null, range);

  bool get isAll => days == null && custom == null;

  /// Untere Grenze (inklusive) relativ zu [now]; null = keine Grenze (alles).
  DateTime? startFrom(DateTime now) {
    if (custom != null) {
      return custom!.start;
    }
    if (days != null) {
      return now.subtract(Duration(days: days!));
    }
    return null;
  }

  /// Obere Grenze bei eigenem Bereich, sonst null (bis jetzt).
  DateTime? get endTo => custom?.end;
}

/// Zeitraum-Wähler im Statistik-Stil (gleich breite Segmente + Kalender), lokal
/// gesteuert statt an einen Controller gekoppelt — wiederverwendet von der
/// Gewichts- und den Aktivitäts-Detailseiten.
class SportRangeSelector extends StatelessWidget {
  const SportRangeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const _presets = [7, 30, 90, 365];

  final SportRange value;
  final ValueChanged<SportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            for (final days in _presets)
              Expanded(
                child: _segment(
                  context,
                  selected: value.days == days,
                  onTap: () => onChanged(SportRange.preset(days)),
                  child: Text(
                    Locales.string(context, 'sport.range.d$days'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            Expanded(
              child: _segment(
                context,
                selected: value.isAll,
                onTap: () => onChanged(const SportRange.all()),
                child: Text(
                  Locales.string(context, 'sport.range.all'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Expanded(
              child: _segment(
                context,
                selected: value.custom != null,
                onTap: () => _pickCustom(context),
                child: const Icon(Icons.date_range, size: 18),
              ),
            ),
          ],
        ),
        if (value.custom != null) _caption(context, value.custom!),
      ],
    );
  }

  Widget _segment(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? onSurface.withValues(alpha: 0.24) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: onSurface, fontWeight: FontWeight.w500, fontSize: 12),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _caption(BuildContext context, DateTimeRange range) {
    final locale = MaterialLocalizations.of(context);
    final label = '${locale.formatShortDate(range.start)} – '
        '${locale.formatShortDate(range.end)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: value.custom,
    );
    if (picked != null) {
      onChanged(SportRange.custom(picked));
    }
  }
}
