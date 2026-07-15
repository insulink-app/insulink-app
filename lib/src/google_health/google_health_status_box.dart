import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_metric_list.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Connection box for the Google Health device page, styled like the sensor's status
/// box: an icon badge + status, the latest metrics when connected, and a
/// connect / disconnect button. "Connecting" grants Health Connect access; the
/// Google Health itself is paired in the Google Health app.
class GoogleHealthStatusBox extends StatelessWidget {
  const GoogleHealthStatusBox({super.key, required this.health});

  final GoogleHealthState health;

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
          if (health.connected) ...[
            const SizedBox(height: 18),
            GoogleHealthMetricList(health: health),
          ] else ...[
            const SizedBox(height: 14),
            LocaleText(
              'google_health.hint',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 16),
          _action(context),
        ],
      ),
    );
  }

  Color _accent(ColorScheme scheme) {
    return scheme.onSurface.withValues(alpha: health.connected ? 0.8 : 0.35);
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
            health.connected
                ? PhosphorIconsRegular.watch
                : PhosphorIconsRegular.watch,
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
                health.connected
                    ? 'google_health.status.connected'
                    : 'google_health.status.disconnected',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              LocaleText(
                'google_health.status.source',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _action(BuildContext context) {
    if (health.busy) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (health.connected) {
      return OutlinedButton.icon(
        onPressed: () => _confirmDisconnect(context),
        icon: const Icon(PhosphorIconsRegular.linkBreak, size: 20),
        label: LocaleText('google_health.disconnect'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.redAccent,
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: () => _connect(context),
      icon: const Icon(PhosphorIconsRegular.link, size: 20),
      label: LocaleText('google_health.connect'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    Alert(
      icon: PhosphorIconsRegular.warning,
      iconColor: Colors.redAccent,
      description: 'google_health.disconnect_confirm',
      cancelButton: true,
      confirmButtonText: 'google_health.disconnect',
      confirmButtonColor: Colors.redAccent,
      callback: health.disconnect,
    ).show(context);
  }

  Future<void> _connect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final denied = Locales.string(context, 'google_health.denied');
    final unavailable = Locales.string(context, 'google_health.unavailable');
    final result = await health.connect();
    final message = switch (result) {
      GoogleHealthImportResult.success => null,
      GoogleHealthImportResult.denied => denied,
      GoogleHealthImportResult.unavailable => unavailable,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
