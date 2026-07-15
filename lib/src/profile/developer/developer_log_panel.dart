import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/cgm/cgm_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/developer/profile_developer_state.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:provider/provider.dart';

/// Scrollable connection log with a copy button. Shown in the developer
/// settings section, and only while developer mode is on.
class DeveloperLogPanel extends StatelessWidget {
  const DeveloperLogPanel({super.key});

  /// Copy the whole log (chronological) to the clipboard and confirm via a
  /// snackbar.
  Future<void> _copyLog(BuildContext context, CgmController controller) async {
    final message = Locales.string(
      context,
      'sensor.log_copied',
      params: ['${controller.log.length}'],
    );
    await Clipboard.setData(ClipboardData(text: controller.logText));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

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
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
        const Spacer(),
        if (controller.log.isNotEmpty) _copyButton(context, controller),
      ],
    );
  }

  Widget _copyButton(BuildContext context, CgmController controller) {
    return TextButton.icon(
      onPressed: () => _copyLog(context, controller),
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
