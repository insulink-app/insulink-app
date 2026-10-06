import 'package:flutter/material.dart';
import 'package:insulink/src/base/empty_state.dart';

import 'sensor_attributes.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/key_value_row.dart';
import 'package:insulink/src/base/section_header.dart';

/// Renders a list of [SensorSection]s, each as a section title over its
/// key/value rows in one panel, or the "empty" placeholder when there is
/// nothing to show. Shared by the G7 ([SensorInfo]) and Libre 3
/// ([Libre3SensorInfo]) info pages, and by the pump page's pod data.
class SensorSectionList extends StatelessWidget {
  const SensorSectionList({super.key, required this.sections});

  final List<SensorSection> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) {
      return const EmptyState(
        icon: PhosphorIconsBold.broadcast,
        titleKey: 'sensor.info.empty',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(titleKey: section.titleKey),
          ),
          InkPanel.list(
            rows: [
              for (final item in section.items)
                KeyValueRow(label: item.key, value: item.value),
            ],
          ),
        ],
      ],
    );
  }
}
