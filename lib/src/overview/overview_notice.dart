import 'package:flutter/material.dart';

/// The quiet panel the overview reports something that has already happened in:
/// a bolus that stopped short, insulin given from a notification, a pod warning
/// raised while the app was closed.
///
/// Deliberately not the amber [OverviewBanner]: that one says a mode is holding
/// something back and ends when tapped, while this one is a fact told once and
/// taken in once.
///
/// Dismissed by a swipe as well as by a tap, because a swipe is what a phone
/// user reaches for on a card they have read, and these notices sit above the
/// glucose reading until they are gone.
class OverviewNotice extends StatelessWidget {
  const OverviewNotice({
    super.key,
    required this.dismissKey,
    required this.icon,
    required this.message,
    required this.onDismiss,
    this.title,
    this.onTap,
    this.action,
  });

  /// What tells this notice apart from its neighbours, for [Dismissible].
  final String dismissKey;

  final IconData icon;

  /// The headline, for a notice whose first line carries its own information.
  final String? title;

  final String message;

  final VoidCallback onDismiss;

  /// What a tap does when there is somewhere worth going. Defaults to
  /// dismissing, which is all a notice with nowhere to go can offer.
  final VoidCallback? onTap;

  /// A control under the message, for a notice that asks for more than being
  /// read (the pod's alerts, acknowledged right here).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(dismissKey),
      onDismissed: (_) => onDismiss(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _panel(context),
      ),
    );
  }

  Widget _panel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? onDismiss,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(child: _text(scheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(ColorScheme scheme) {
    final headline = title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (headline != null) ...[
          Text(
            headline,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
        ],
        Text(
          message,
          style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurface),
        ),
        ?action,
      ],
    );
  }
}
