import 'package:flutter/material.dart';

import '../../localization/locale_text.dart';

/// A titled card listing one [_SensorInfoRow] per value.
class SensorInfoSection extends StatelessWidget {
  const SensorInfoSection({
    super.key,
    required this.titleKey,
    required this.items,
  });

  final String titleKey;
  final List<MapEntry<String, String>> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_title(scheme), const SizedBox(height: 6), ..._rows(scheme)],
      ),
    );
  }

  Widget _title(ColorScheme scheme) {
    return LocaleText(
      titleKey,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
        color: scheme.onSurface,
      ),
    );
  }

  List<Widget> _rows(ColorScheme scheme) {
    final widgets = <Widget>[];
    for (var index = 0; index < items.length; index++) {
      if (index > 0) {
        widgets.add(
          Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.06)),
        );
      }
      widgets.add(
        _SensorInfoRow(label: items[index].key, value: items[index].value),
      );
    }
    return widgets;
  }
}

/// One label/value line: label muted on the left, value emphasised on the right.
class _SensorInfoRow extends StatelessWidget {
  const _SensorInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
