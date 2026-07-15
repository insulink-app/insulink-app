import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_metric_list.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:insulink/src/theme/status_colors.dart';

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
            _hintOrFailure(scheme),
          ],
          const SizedBox(height: 16),
          _action(context),
        ],
      ),
    );
  }

  /// The box's own explanatory line: normally what connecting will do, but after
  /// a failed attempt, why it failed.
  ///
  /// The failure belongs here rather than in a passing notice — a denied
  /// permission is a standing condition, not an event, so it stays visible next
  /// to the button that retries it, and it survives leaving and reopening the
  /// page. It replaces the hint instead of joining it: once connecting has
  /// failed, telling the user what connecting would do is no longer the point.
  Widget _hintOrFailure(ColorScheme scheme) {
    final failure = health.connectFailure;
    if (failure == null) {
      return LocaleText(
        'google_health.hint',
        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(PhosphorIconsRegular.warning, size: 15, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: LocaleText(
            failure == GoogleHealthImportResult.denied
                ? 'google_health.denied'
                : 'google_health.unavailable',
            style: TextStyle(fontSize: 13, height: 1.3, color: scheme.error),
          ),
        ),
      ],
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
          foregroundColor: context.danger,
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    // The outcome needs no handling here: connect() records it and notifies, and
    // the box renders it — see _hintOrFailure.
    return FilledButton.tonalIcon(
      onPressed: () => health.connect(),
      icon: const Icon(PhosphorIconsRegular.link, size: 20),
      label: LocaleText('google_health.connect'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
    );
  }

  void _confirmDisconnect(BuildContext context) {
    Alert(
      icon: PhosphorIconsRegular.warning,
      iconColor: context.danger,
      description: 'google_health.disconnect_confirm',
      cancelButton: true,
      confirmButtonText: 'google_health.disconnect',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: health.disconnect,
    ).show(context);
  }
}
