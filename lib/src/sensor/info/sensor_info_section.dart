import 'package:flutter/material.dart';

import '../../localization/locale_text.dart';
import 'sensor_attributes.dart';

/// Renders a list of [SensorSection]s as stacked [SensorInfoSection] cards, or
/// the "empty" placeholder when there is nothing to show. Shared by the G7
/// ([SensorInfo]) and Libre 3 ([Libre3SensorInfo]) info pages.
class SensorSectionList extends StatelessWidget {
  const SensorSectionList({super.key, required this.sections});

  final List<SensorSection> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return Center(child: LocaleText('sensor.info.empty'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          SensorInfoSection(
            titleKey: sections[index].titleKey,
            items: sections[index].items,
          ),
        ],
      ],
    );
  }
}

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
