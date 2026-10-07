import 'package:flutter/material.dart';
import 'package:insulink/src/alert/alert.dart';
import 'package:insulink/src/base/ink_panel.dart';
import 'package:insulink/src/base/key_value_row.dart';
import 'package:insulink/src/base/list_row.dart';
import 'package:insulink/src/base/notice_banner.dart';
import 'package:insulink/src/base/section_header.dart';
import 'package:insulink/src/google_health/google_health_importer.dart';
import 'package:insulink/src/google_health/google_health_models.dart';
import 'package:insulink/src/google_health/google_health_state.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:insulink/src/theme/status_colors.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Everything under the Google Health device head. Connected: "Letzte Werte"
/// as key/value rows in one panel, then "Verbindung trennen" as a red row in
/// a panel of its own. Not connected: what connecting does, or why it failed,
/// and the primary button that connects.
class GoogleHealthStatusBox extends StatelessWidget {
  const GoogleHealthStatusBox({super.key, required this.health});

  final GoogleHealthState health;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: health.connected ? _connected(context) : _disconnected(context),
    );
  }

  List<Widget> _connected(BuildContext context) {
    return [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SectionHeader(titleKey: 'google_health.latest'),
      ),
      InkPanel.list(
        rows: [
          _row(
            context,
            'google_health.resting_hr',
            _bpm(health.todayRestingHr),
          ),
          _row(context, 'google_health.heart_rate', _bpm(health.latestHr)),
          _row(
            context,
            'google_health.respiratory_rate',
            _unit(health.latestRespiratoryRate, 'rpm'),
          ),
          _row(
            context,
            'google_health.sleep',
            formatSleepMinutes(health.lastSleepMinutes),
          ),
        ],
      ),
      const SizedBox(height: InkSpace.tileGap * 2),
      InkPanel.list(
        rows: [
          ListRow(
            icon: PhosphorIconsBold.linkBreak,
            title: Locales.string(context, 'google_health.disconnect_row'),
            tone: ListRowTone.danger,
            onTap: health.busy ? null : () => _confirmDisconnect(context),
          ),
        ],
      ),
    ];
  }

  /// The hint, or after a failed attempt why it failed: a denied permission is
  /// a standing condition, so it stays next to the button that retries it and
  /// survives leaving the page. It replaces the hint instead of joining it.
  List<Widget> _disconnected(BuildContext context) {
    final failure = health.connectFailure;
    final textStyle = InkText.label.copyWith(color: context.ink.text);
    return [
      const SizedBox(height: 24),
      if (failure == null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LocaleText(
            'google_health.hint',
            style: InkText.label.copyWith(color: context.ink.muted),
          ),
        )
      else
        NoticeBanner(
          icon: PhosphorIconsFill.warningCircle,
          tone: NoticeTone.danger,
          child: LocaleText(
            failure == GoogleHealthImportResult.denied
                ? 'google_health.denied'
                : 'google_health.unavailable',
            style: textStyle,
          ),
        ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: health.busy ? null : () => health.connect(),
        icon: const Icon(PhosphorIconsBold.link, size: 20),
        label: LocaleText('google_health.connect'),
      ),
    ];
  }

  Widget _row(BuildContext context, String labelKey, String value) =>
      KeyValueRow(label: Locales.string(context, labelKey), value: value);

  String _bpm(int? value) => _unit(value, 'bpm');

  String _unit(int? value, String unit) => value == null ? '–' : '$value $unit';

  void _confirmDisconnect(BuildContext context) {
    Alert(
      icon: PhosphorIconsBold.warning,
      iconColor: context.danger,
      description: 'google_health.disconnect_confirm',
      cancelButton: true,
      confirmButtonText: 'google_health.disconnect',
      confirmButtonColor: Theme.of(context).colorScheme.error,
      callback: health.disconnect,
    ).show(context);
  }
}
