import 'package:flutter/material.dart';
import 'package:insulink/src/analysis/compression/night_compression_state.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:provider/provider.dart';

/// Under the window picker: how many compression lows the window holds, and
/// the switch between the filtered and the raw readings. Only there while the
/// window has any, since otherwise the switch would change nothing.
class NightCompressionNote extends StatelessWidget {
  const NightCompressionNote({super.key});

  @override
  Widget build(BuildContext context) {
    final compression = context.watch<NightCompressionState>();
    if (compression.dipCount == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        InkSpace.panelMargin + 4,
        4,
        InkSpace.panelMargin,
        0,
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              _text(context, compression),
              style: InkText.caption.copyWith(color: context.ink.muted),
            ),
          ),
          Semantics(
            label: Locales.string(
              context,
              NightCompressionState.hideSetting.labelKey,
            ),
            child: Switch(
              value: compression.hidden,
              onChanged: compression.setHidden,
            ),
          ),
        ],
      ),
    );
  }

  String _text(BuildContext context, NightCompressionState compression) {
    return Locales.string(
      context,
      compression.hidden
          ? 'analysis.compression.hidden'
          : 'analysis.compression.shown',
      params: ['${compression.dipCount}'],
    );
  }
}
