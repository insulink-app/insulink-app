import 'package:flutter/material.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/ink_sheet.dart';
import 'package:insulink/src/base/key_value_row.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

import 'trash_details.dart';
import 'trash_entry.dart';

/// Shows what a trashed [entry] held, read only, with a button that restores
/// it. Resolves to true when the user chose to restore.
Future<bool?> showTrashDetail(BuildContext context, TrashEntry entry) {
  return showInkSheet<bool>(
    context: context,
    builder: (_) => TrashDetailSheet(entry: entry),
  );
}

class TrashDetailSheet extends StatelessWidget {
  const TrashDetailSheet({super.key, required this.entry});

  final TrashEntry entry;

  @override
  Widget build(BuildContext context) {
    final deleted = DateTime.fromMillisecondsSinceEpoch(entry.deletedAtMs);
    return InkSheet(
      titleKey: entry.kind.titleKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          InkPanel.list(
            rows: [
              _row(context, 'trash.detail.time', _moment(context, entry.time)),
              for (final (key, value) in TrashDetails(entry).rows)
                _row(context, key, value),
              _row(context, 'trash.detail.deleted', _moment(context, deleted)),
            ],
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const LocaleText('trash.restore'),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String key, String value) =>
      KeyValueRow(label: Locales.string(context, key), value: value);

  String _moment(BuildContext context, DateTime time) {
    final clock = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
    return '${RelativeDay(time).label(context)}, $clock';
  }
}
