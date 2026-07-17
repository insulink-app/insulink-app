import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Scrollable connection log with a copy button. Shown in the developer
/// settings section, and only while developer mode is on.
class DeveloperLogPanel extends StatelessWidget {
  const DeveloperLogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<ProfileDeveloperState>().enabled) {
      return const SizedBox.shrink();
    }
    final controller = context.watch<CgmController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _header(context, controller),
        const SizedBox(height: 4),
        _logBox(controller),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _header(BuildContext context, CgmController controller) {
    return Row(
      children: [
        LocaleText(
          'sensor.log',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        if (controller.log.isNotEmpty) _CopyLogButton(controller: controller),
      ],
    );
  }

  /// SelectableText so individual lines can also be hand-selected; the copy
  /// button grabs the whole log. Wrapped in a scroll view because SelectableText
  /// won't scroll on its own.
  Widget _logBox(CgmController controller) {
    return Container(
      width: double.infinity,
      height: 300,
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

/// The log's copy action, which confirms itself: on tap it swaps its own icon
/// and label for a checkmark and the copied-line count, then reverts.
///
/// The confirmation belongs ON the control because that is where the user is
/// looking and what they just touched — nothing has to be read or dismissed, and
/// the panel underneath stays uncovered.
class _CopyLogButton extends StatefulWidget {
  const _CopyLogButton({required this.controller});

  final CgmController controller;

  @override
  State<_CopyLogButton> createState() => _CopyLogButtonState();
}

class _CopyLogButtonState extends State<_CopyLogButton> {
  static const _confirmFor = Duration(seconds: 2);

  Timer? _revert;
  int? _copied;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final lines = widget.controller.log.length;
    await Clipboard.setData(ClipboardData(text: widget.controller.logText));
    if (!mounted) {
      return;
    }
    setState(() => _copied = lines);
    _revert?.cancel();
    _revert = Timer(_confirmFor, () {
      if (mounted) {
        setState(() => _copied = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _copied != null;
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(
        done ? PhosphorIconsBold.check : PhosphorIconsBold.copy,
        size: 16,
      ),
      label: done
          ? LocaleText('sensor.log_copied', params: ['$_copied'])
          : LocaleText('sensor.copy'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
