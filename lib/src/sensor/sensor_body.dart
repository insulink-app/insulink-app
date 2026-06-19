import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/g7/g7_controller.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/profile/profile_developer_state.dart';
import 'package:insulink/src/sensor/sensor_info.dart';
import 'package:provider/provider.dart';

class SensorBody extends ProductPageBody {
  SensorBody({super.key})
    : super(
        name: "sensor.label",
        unselectedIcon: CupertinoIcons.drop,
        selectedIcon: CupertinoIcons.drop_fill,
      );

  @override
  Widget content(BuildContext context) {
    return const SensorBodyContent();
  }
}

class SensorBodyContent extends StatelessWidget {
  const SensorBodyContent({super.key});

  /// Copy the whole log (chronological) to the clipboard and confirm via a
  /// snackbar.
  Future<void> _copyLog(BuildContext context, G7Controller g7) async {
    final message = Locales.string(
      context,
      'sensor.log_copied',
      params: ['${g7.log.length}'],
    );
    await Clipboard.setData(ClipboardData(text: g7.logText));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g7 = context.watch<G7Controller>();
    final showLog = context.watch<ProfileDeveloperState>().enabled;
    return Scaffold(
      appBar: AppBar(
        title: LocaleText('sensor.label'),
        actions: [
          if (g7.connected)
            IconButton(
              onPressed: g7.disconnect,
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: Locales.string(context, 'sensor.disconnect'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: SensorInfo(
                  info: g7.info,
                  sensorStart: g7.sensorStart,
                  state: g7.latest?.state,
                  age: g7.latest?.secsSinceStart,
                  lastUpdate: g7.lastUpdate,
                ),
              ),
            ),
            // Connection log — developer mode only.
            if (showLog) _LogPanel(g7: g7, onCopy: () => _copyLog(context, g7)),
          ],
        ),
      ),
    );
  }
}

/// Scrollable connection log with a copy button. Shown only in developer mode.
class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.g7, required this.onCopy});

  final G7Controller g7;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            LocaleText(
              'sensor.log',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const Spacer(),
            if (g7.log.isNotEmpty)
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: LocaleText('sensor.copy'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          height: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          // SelectableText so individual lines can also be selected by hand;
          // the Kopieren button grabs the whole log at once. Scrollable
          // because SelectableText won't scroll on its own.
          child: SingleChildScrollView(
            child: SelectableText(
              g7.log.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}
