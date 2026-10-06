import 'package:flutter/material.dart';
import 'package:insulink/src/auth/permissions/permission_onboarding.dart';
import 'package:insulink/src/localization/locale_text.dart';
import 'package:insulink/src/base/button_loader.dart';

/// A single explained-permission page: icon, title, rationale and an allow
/// button. Pure presentation — the parent owns the request and navigation.
class PermissionStep extends StatelessWidget {
  const PermissionStep({
    super.key,
    required this.permission,
    required this.isLast,
    required this.position,
    required this.count,
    required this.busy,
    required this.onAllow,
  });

  final PermissionRequest permission;
  final bool isLast;
  final int position;
  final int count;
  final bool busy;
  final Future<void> Function() onAllow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          _icon(scheme),
          const SizedBox(height: 32),
          LocaleText(
            permission.titleKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LocaleText(
            permission.bodyKey,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const Spacer(),
          _dots(scheme),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : onAllow,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: busy
                ? const ButtonLoader(size: 22)
                : LocaleText(
                    isLast ? 'permission.continue' : 'permission.next',
                  ),
          ),
        ],
      ),
    );
  }

  Widget _icon(ColorScheme scheme) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.surfaceContainerHighest,
        ),
        child: Icon(permission.icon, size: 48, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _dots(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var dot = 0; dot < count; dot++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dot == position
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.2),
            ),
          ),
      ],
    );
  }
}
