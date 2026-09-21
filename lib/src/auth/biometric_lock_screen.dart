import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// What a locked app shows: what it is, and the way back in. No way past it,
/// which is the point.
class BiometricLockScreen extends StatelessWidget {
  const BiometricLockScreen({super.key, required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsBold.fingerprint,
                  size: 64,
                  color: scheme.primary,
                ),
                const SizedBox(height: 20),
                LocaleText(
                  'profile.security.lock.title',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(PhosphorIconsBold.lockKeyOpen),
                  label: LocaleText('profile.security.lock.unlock'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(220, 52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
