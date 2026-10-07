import 'package:flutter/material.dart';
import 'package:insulink/src/base/status_icon.dart';
import 'package:insulink/src/connections/device_links.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// One connection as a plain card: the device glyph in a [StatusIcon] whose
/// dot carries the state, the name over the paired device, and a chevron.
/// Tapping opens [page] as a [ConnectionSubPage].
class ConnectionRow extends StatelessWidget {
  final IconData icon;
  final String labelKey;
  final Widget page;
  final DeviceLink link;

  /// Header controls the opened page should carry, e.g. the pump's delivery log.
  final List<Widget> actions;

  const ConnectionRow({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.page,
    required this.link,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    final label = Locales.string(context, labelKey);
    return Material(
      color: colors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(InkRadius.tile),
        side: BorderSide(color: colors.border),
      ),
      child: InkWell(
        onTap: () => _open(context, label),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            spacing: 14,
            children: [
              StatusIcon(icon: icon, statusColor: _dotColor(colors)),
              Expanded(child: _texts(context, label)),
              Icon(PhosphorIconsBold.caretRight, size: 18, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, String label) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ConnectionSubPage(title: label, body: page, actions: actions),
      ),
    );
  }

  Color _dotColor(InsulinkColors colors) => switch (link.state) {
    LinkState.active => colors.range,
    LinkState.attention => colors.low,
    LinkState.idle => colors.muted,
  };

  Widget _texts(BuildContext context, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 2,
      children: [
        Text(label, style: InkText.rowTitle.copyWith(fontSize: 17)),
        LocaleText(
          link.detailKey,
          style: InkText.label.copyWith(color: context.ink.muted),
        ),
      ],
    );
  }
}

/// A device page shown on top of the Devices tab, with a back button.
class ConnectionSubPage extends StatelessWidget {
  final String title;
  final Widget body;

  /// Controls in the header that belong to this device rather than to the page
  /// body — the pump's delivery log is one.
  final List<Widget> actions;

  const ConnectionSubPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        actions: actions,
      ),
      body: body,
    );
  }
}
