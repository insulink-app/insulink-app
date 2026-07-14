import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locales.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// A large, card-styled device row: tinted icon badge, bold label, an attention
/// dot when needed, and a chevron. Tapping opens [page] as a [ConnectionSubPage].
class ConnectionRow extends StatelessWidget {
  final IconData icon;
  final String labelKey;
  final Widget page;
  final bool notify;

  const ConnectionRow({
    super.key,
    required this.icon,
    required this.labelKey,
    required this.page,
    this.notify = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = Locales.string(context, labelKey);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConnectionSubPage(title: label, body: page),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.07)),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (notify) ...[
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A device page shown on top of the Devices tab, with a back button.
class ConnectionSubPage extends StatelessWidget {
  final String title;
  final Widget body;

  const ConnectionSubPage({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(surfaceTintColor: Colors.transparent, title: Text(title)),
      body: body,
    );
  }
}
