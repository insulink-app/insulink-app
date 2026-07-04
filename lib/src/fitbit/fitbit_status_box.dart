import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/fitbit/fitbit_importer.dart';
import 'package:insulink/src/fitbit/fitbit_metric_list.dart';
import 'package:insulink/src/fitbit/fitbit_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';

/// Connection box for the Fitbit device page, styled like the sensor's status
/// box: an icon badge + status, the latest metrics when connected, and a
/// connect / disconnect button. "Connecting" grants Health Connect access; the
/// Fitbit itself is paired in the Fitbit app.
class FitbitStatusBox extends StatelessWidget {
  const FitbitStatusBox({super.key, required this.fitbit});

  final FitbitState fitbit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          _header(scheme),
          if (fitbit.connected) ...[
            const SizedBox(height: 18),
            FitbitMetricList(fitbit: fitbit),
          ] else ...[
            const SizedBox(height: 14),
            LocaleText(
              'fitbit.hint',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ],
          const SizedBox(height: 16),
          _action(context),
        ],
      ),
    );
  }

  Color _accent(ColorScheme scheme) {
    return scheme.onSurface.withValues(alpha: fitbit.connected ? 0.8 : 0.35);
  }

  Widget _header(ColorScheme scheme) {
    final accent = _accent(scheme);
    return Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.15),
          ),
          child: Icon(
            fitbit.connected ? Icons.watch : Icons.watch_off,
            size: 30,
            color: accent,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocaleText(
                fitbit.connected
                    ? 'fitbit.status.connected'
                    : 'fitbit.status.disconnected',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              LocaleText(
                'fitbit.status.source',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(BuildContext context) {
    if (fitbit.busy) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (fitbit.connected) {
      return OutlinedButton.icon(
        onPressed: () => _confirmDisconnect(context),
        icon: const Icon(Icons.link_off, size: 20),
        label: LocaleText('fitbit.disconnect'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => _connect(context),
      icon: const Icon(Icons.link, size: 20),
      label: LocaleText('fitbit.connect'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    Alert(
      icon: CupertinoIcons.exclamationmark_triangle,
      iconColor: Colors.redAccent,
      description: 'fitbit.disconnect_confirm',
      cancelButton: true,
      confirmButtonText: 'fitbit.disconnect',
      confirmButtonColor: Colors.redAccent,
      callback: fitbit.disconnect,
    ).show(context);
  }

  Future<void> _connect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = Locales.string(context, 'fitbit.denied');
    final unavailable = Locales.string(context, 'fitbit.unavailable');
    final result = await fitbit.connect();
    final message = switch (result) {
      FitbitImportResult.success => null,
      FitbitImportResult.denied => denied,
      FitbitImportResult.unavailable => unavailable,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
