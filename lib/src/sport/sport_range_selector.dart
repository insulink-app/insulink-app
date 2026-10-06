import 'package:flutter/material.dart';
import 'package:insulink/src/base/header_icon_button.dart';
import 'package:insulink/src/base/segmented_toggle.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Selected time window of a sport detail page: a preset (days), "All" or a
/// custom date range. Pure value class; the pages filter their data with it.
class SportRange {
  final int? days;
  final DateTimeRange? custom;

  const SportRange._(this.days, this.custom);
  const SportRange.all() : this._(null, null);
  const SportRange.preset(int presetDays) : this._(presetDays, null);
  const SportRange.custom(DateTimeRange range) : this._(null, range);

  bool get isAll => days == null && custom == null;

  /// Lower bound (inclusive) relative to [now]; null = no bound (everything).
  DateTime? startFrom(DateTime now) {
    if (custom != null) {
      return custom!.start;
    }
    if (days != null) {
      return now.subtract(Duration(days: days!));
    }
    return null;
  }

  /// Upper bound for a custom range, otherwise null (up to now).
  DateTime? get endTo => custom?.end;
}

/// Range picker: a pill track with the presets and "All", and beside it a round
/// calendar button for a custom range. Controlled locally instead of coupled to
/// a controller; reused by the weight, activity and sleep detail pages.
class SportRangeSelector extends StatelessWidget {
  const SportRangeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const _presets = [7, 30, 90, 365];

  /// The track's value for "All"; a custom range lights no option at all.
  static const int _allKey = 0;
  static const int _customKey = -1;

  final SportRange value;
  final ValueChanged<SportRange> onChanged;

  int get _selectedKey {
    if (value.custom != null) {
      return _customKey;
    }
    return value.days ?? _allKey;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(child: _track(context)),
            HeaderIconButton(
              icon: PhosphorIconsRegular.calendarBlank,
              labelKey: 'sport.range.pick',
              statusColor: value.custom != null ? context.ink.accent : null,
              onTap: () => _pickCustom(context),
            ),
          ],
        ),
        if (value.custom != null) _caption(context, value.custom!),
      ],
    );
  }

  Widget _track(BuildContext context) {
    return SegmentedToggle<int>.page(
      expand: true,
      selected: _selectedKey,
      onChanged: (key) => onChanged(
        key == _allKey ? const SportRange.all() : SportRange.preset(key),
      ),
      options: [
        for (final days in _presets)
          (value: days, label: Locales.string(context, 'sport.range.d$days')),
        (value: _allKey, label: Locales.string(context, 'sport.range.all')),
      ],
    );
  }

  Widget _caption(BuildContext context, DateTimeRange range) {
    final locale = MaterialLocalizations.of(context);
    final label =
        '${locale.formatShortDate(range.start)} – '
        '${locale.formatShortDate(range.end)}';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        label,
        style: InkText.caption.copyWith(color: context.ink.muted),
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
