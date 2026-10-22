import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/relative_day.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'trash_detail_sheet.dart';
import 'trash_entry.dart';
import 'trash_restorer.dart';
import 'trash_store.dart';

/// The trash in the profile: what was deleted in the last 30 days, newest
/// first, each with a button that puts it back where it came from. A tap on
/// a row shows what the entry held.
class TrashList extends StatefulWidget {
  const TrashList({super.key});

  @override
  State<TrashList> createState() => _TrashListState();
}

class _TrashListState extends State<TrashList> {
  List<TrashEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final entries = await const TrashStore().load();
    if (mounted) {
      setState(() => _entries = entries.reversed.toList());
    }
  }

  /// Restores first and only then empties the slot, so a failed restore
  /// leaves the entry in the trash.
  Future<void> _restore(TrashEntry entry) async {
    await TrashRestorer(context).restore(entry);
    await const TrashStore().take(entry);
    await _reload();
  }

  Future<void> _showDetail(TrashEntry entry) async {
    final restore = await showTrashDetail(context, entry);
    if (restore == true && mounted) {
      await _restore(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries == null) {
      return const SizedBox.shrink();
    }
    if (entries.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.trash,
        titleKey: 'trash.empty',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const LocaleText('trash.intro'),
        InkPanel.list(rows: [for (final entry in entries) _row(entry)]),
      ],
    );
  }

  Widget _row(TrashEntry entry) {
    final day = RelativeDay(entry.time).label(context);
    final summary = entry.summary;
    return ListRow(
      icon: entry.kind.icon,
      title: Locales.string(context, entry.kind.titleKey),
      subtitle: summary == null ? day : '$summary, $day',
      onTap: () => _showDetail(entry),
      trailing: IconButton(
        icon: const Icon(PhosphorIconsBold.arrowCounterClockwise),
        tooltip: Locales.string(context, 'trash.restore'),
        onPressed: () => _restore(entry),
      ),
    );
  }
}
