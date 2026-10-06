import 'package:flutter/material.dart';
import 'package:insulink/src/theme/insulink_theme.dart';

/// The top of a device page, open on the page without a card: a 56 px accent
/// disc with the device glyph, the device's name large, and under it one
/// status line led by a dot (range = fine, high = needs a look, low = fault).
class DeviceHead extends StatelessWidget {
  const DeviceHead({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.statusColor,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String status;
  final Color statusColor;

  /// Replaces the glyph with a spinner while the device is being searched for.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.ink;
    return Row(
      spacing: 14,
      children: [
        _disc(colors),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Text(
                title,
                style: InkText.deviceTitle.copyWith(color: colors.text),
              ),
              _status(colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _disc(InsulinkColors colors) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.accent.withValues(alpha: 0.14),
      ),
      child: busy
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.accent,
              ),
            )
          : Icon(icon, size: 26, color: colors.accent),
    );
  }

  Widget _status(InsulinkColors colors) {
    return Row(
      spacing: 7,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
        ),
        Flexible(
          child: Text(
            status,
            style: InkText.body.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.muted,
            ),
          ),
        ),
      ],
    );
  }
}
