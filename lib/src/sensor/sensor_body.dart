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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ControlBox(g7: g7),
            const SizedBox(height: 12),
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

/// Top-of-page controls: end the current reading session, or fully forget the
/// sensor. Both are guarded by a confirmation dialog so they can't fire by
/// accident.
class _ControlBox extends StatelessWidget {
  const _ControlBox({required this.g7});

  final G7Controller g7;

  Future<bool> _confirm(
    BuildContext context, {
    required String titleKey,
    required String bodyKey,
    required String confirmKey,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Locales.string(ctx, titleKey)),
        content: Text(Locales.string(ctx, bodyKey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(Locales.string(ctx, 'alert.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.redAccent)
                : null,
            child: Text(Locales.string(ctx, confirmKey)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = g7.connected;
    final accent = connected ? Colors.tealAccent.shade700 : Colors.grey;

    final String subtitle;
    if (connected) {
      subtitle = g7.currentMgdl != null ? '${g7.currentMgdl} mg/dL' : '…';
    } else {
      subtitle = Locales.string(
        context,
        g7.hasSensor ? 'sensor.status.paired' : 'sensor.status.unpaired',
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Larger status display icon.
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.15),
                ),
                child: Icon(
                  connected
                      ? CupertinoIcons.dot_radiowaves_left_right
                      : CupertinoIcons.drop,
                  size: 32,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocaleText(
                      connected
                          ? 'sensor.status.connected'
                          : 'sensor.status.disconnected',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: connected
                ? () async {
                    if (await _confirm(
                      context,
                      titleKey: 'sensor.control.end_session_title',
                      bodyKey: 'sensor.control.end_session_body',
                      confirmKey: 'sensor.control.end_session',
                    )) {
                      await g7.disconnect();
                    }
                  }
                : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: LocaleText('sensor.control.end_session'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: (connected || g7.hasSensor)
                ? () async {
                    if (await _confirm(
                      context,
                      titleKey: 'sensor.control.stop_sensor_title',
                      bodyKey: 'sensor.control.stop_sensor_body',
                      confirmKey: 'sensor.control.stop_sensor',
                      destructive: true,
                    )) {
                      await g7.forgetSensor();
                    }
                  }
                : null,
            icon: const Icon(Icons.link_off, size: 20),
            label: LocaleText('sensor.control.stop_sensor'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(46),
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
          ),
        ],
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
