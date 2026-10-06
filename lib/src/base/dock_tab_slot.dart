import 'package:flutter/material.dart';
import 'package:insulink/src/base/nav_badge.dart';
import 'package:insulink/src/base/page_body.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:insulink/src/theme/insulink_colors.dart';

/// One tab in the dock: its icon always, its label fading in as the gliding
/// pill arrives ([closeness] 1 = the pill is on it), and its badge.
class DockTabSlot extends StatelessWidget {
  const DockTabSlot({
    super.key,
    required this.body,
    required this.closeness,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final AppPageBody body;
  final double closeness;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;

  /// Below this closeness the slot is too narrow for its label.
  static const double _labelFrom = 0.35;

  @override
  Widget build(BuildContext context) {
    final label = Locales.string(context, body.name);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _content(context, label),
              if (badge != null && badge != 0) NavBadge(count: badge!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, String label) {
    final colors = context.insulinkColors;
    final tone = Color.lerp(colors.muted, colors.accentText, closeness)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(body.unselectedIcon, size: 22, color: tone),
        if (closeness > _labelFrom) ...[
          const SizedBox(width: 8),
          Flexible(child: _label(label, tone)),
        ],
      ],
    );
  }

  Widget _label(String label, Color tone) {
    return Opacity(
      opacity: ((closeness - _labelFrom) / (1 - _labelFrom)).clamp(0.0, 1.0),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }
}
