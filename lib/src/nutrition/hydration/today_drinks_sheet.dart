import 'package:flutter/material.dart';
import 'package:insulink/src/base/grab_handle.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_models.dart';
import 'package:insulink/src/nutrition/hydration/nutrition_state.dart';
import 'package:provider/provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Bottom sheet listing today's logged drinks (newest first, with their time),
/// each removable — so the box itself stays clean.
Future<void> showTodayDrinksSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider<NutritionState>.value(
      value: context.read<NutritionState>(),
      child: const _TodayDrinksSheet(),
    ),
  );
}

class _TodayDrinksSheet extends StatelessWidget {
  const _TodayDrinksSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<NutritionState>();
    final entries = state.todayEntries.reversed.toList();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        8,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: GrabHandle(),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: LocaleText(
              'nutrition.hydration.log',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            _empty(context)
          else
            Flexible(child: _list(theme, state, entries)),
        ],
      ),
    );
  }

  Widget _list(
    ThemeData theme,
    NutritionState state,
    List<DrinkEntry> entries,
  ) {
    final accent = theme.colorScheme.primary;
    return ListView.separated(
      shrinkWrap: true,
      itemCount: entries.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
      itemBuilder: (_, index) {
        final entry = entries[index];
        return ListTile(
          contentPadding: const EdgeInsets.only(right: 4),
          leading: Icon(iconForKind(entry.kind), color: accent),
          title: Text('${entry.ml} ml'),
          subtitle: Text(_time(entry.atEpochMs)),
          trailing: IconButton(
            icon: Icon(
              PhosphorIconsRegular.trash,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => state.removeEntry(entry),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      child: LocaleText(
        'nutrition.hydration.log_empty',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Local wall-clock time (HH:mm) a drink was logged.
  String _time(int atEpochMs) {
    final at = DateTime.fromMillisecondsSinceEpoch(atEpochMs);
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
