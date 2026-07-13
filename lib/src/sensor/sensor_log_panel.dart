import 'package:flutter/material.dart';

import '../cgm/cgm_controller.dart';
import '../localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Scrollable connection log with a copy button. Shown only in developer mode.
class SensorLogPanel extends StatelessWidget {
  const SensorLogPanel({
    super.key,
    required this.controller,
    required this.onCopy,
  });

  final CgmController controller;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _header(),
        const SizedBox(height: 4),
        _logBox(),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        LocaleText(
          'sensor.log',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        const Spacer(),
        if (controller.log.isNotEmpty) _copyButton(),
      ],
    );
  }

  Widget _copyButton() {
    return TextButton.icon(
      onPressed: onCopy,
      icon: const Icon(PhosphorIconsRegular.copy, size: 16),
      label: LocaleText('sensor.copy'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// SelectableText so individual lines can also be hand-selected; the copy
  /// button grabs the whole log. Wrapped in a scroll view because SelectableText
  /// won't scroll on its own.
  Widget _logBox() {
    return Container(
      width: double.infinity,
      height: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          controller.log.join('\n'),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        ),
      ),
    );
  }
}
