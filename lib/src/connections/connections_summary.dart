import 'package:flutter/material.dart';
import 'package:insulink/src/connections/device_links.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// The overall state above the connection cards, on the page without a card:
/// a check (or a warning) in a tinted disc, "Alles verbunden" or how many
/// connections need the user, and "x von y Verbindungen aktiv" under it.
class ConnectionsSummary extends StatelessWidget {
  const ConnectionsSummary({super.key, required this.links});

  final DeviceLinks links;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final problems = links.attentionCount;
    final tone = problems == 0 ? colors.range : colors.low;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.14),
            ),
            child: Icon(
              problems == 0
                  ? PhosphorIconsBold.check
                  : PhosphorIconsBold.warning,
              size: 20,
              color: tone,
            ),
          ),
          Expanded(child: _texts(context, colors, problems)),
        ],
      ),
    );
  }

  Widget _texts(BuildContext context, InsulinkColors colors, int problems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(
          _headline(context, problems),
          style: InkText.section.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          Locales.string(
            context,
            'connections.active_count',
            params: ['${links.activeCount}', '${links.countedCount}'],
          ),
          style: InkText.label.copyWith(color: colors.muted),
        ),
      ],
    );
  }

  String _headline(BuildContext context, int problems) {
    if (problems == 0) {
      return Locales.string(context, 'connections.all_connected');
    }
    if (problems == 1) {
      return Locales.string(context, 'connections.attention_one');
    }
    return Locales.string(
      context,
      'connections.attention_many',
      params: ['$problems'],
    );
  }
}
