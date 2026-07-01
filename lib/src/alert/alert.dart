import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

enum AlertType { success, error, neutral }

/// Modaler Hinweis-/Bestätigungsdialog im iOS-Stil: getönter Icon-Kreis,
/// zentrierte Nachricht und groß gestapelte Aktions-Buttons, über einem
/// weichgezeichneten Hintergrund eingeblendet. API bewusst schlank gehalten,
/// damit alle Aufrufer (Löschen, Fehler, Eingabe …) unverändert bleiben.
class Alert extends StatefulWidget {
  final AlertType? type;
  final IconData? icon;
  final Color? iconColor;
  final String? description;
  final Widget? content;
  final bool? cancelButton;
  final String? cancelButtonText;
  final Color? cancelButtonColor;
  final String? confirmButtonText;
  final Color? confirmButtonColor;
  final bool Function()? confirmButtonEnabled;
  final Function()? callback;

  const Alert({
    super.key,
    this.type,
    this.icon,
    this.iconColor,
    this.description,
    this.content,
    this.cancelButton,
    this.cancelButtonText,
    this.cancelButtonColor,
    this.confirmButtonText,
    this.confirmButtonColor,
    this.confirmButtonEnabled,
    this.callback,
  });

  @override
  State<Alert> createState() => AlertState();

  /// Blendet den Dialog mit weichgezeichnetem Hintergrund und sanftem
  /// Aufskalieren ein.
  void show(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => this,
      transitionBuilder: (context, animation, _, child) {
        final scale = Tween(begin: 0.92, end: 1.0)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack));
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 7 * animation.value,
            sigmaY: 7 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: scale, child: child),
          ),
        );
      },
    );
  }
}

class AlertState extends State<Alert> {
  void reload() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: _card(theme),
          ),
        ),
      ),
    );
  }

  Widget _card(ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(32),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconCircle(),
            const SizedBox(height: 18),
            _body(),
            const SizedBox(height: 24),
            _actions(theme),
          ],
        ),
      ),
    );
  }

  Widget _iconCircle() {
    final color = _iconColor();
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color?.withValues(alpha: 0.12),
      ),
      child: Icon(_iconData(), size: 36, color: color),
    );
  }

  /// Die Nachricht: entweder ein lokalisierter Text oder ein eigener [content].
  Widget _body() {
    if (widget.description == null) {
      return widget.content ?? const SizedBox.shrink();
    }
    return LocaleText(
      widget.description ?? "",
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.35),
    );
  }

  /// Große Buttons nebeneinander: dezentes Abbrechen links, gefüllte
  /// Bestätigung rechts.
  Widget _actions(ThemeData theme) {
    final disabled =
        widget.confirmButtonEnabled != null && !widget.confirmButtonEnabled!();
    final confirm = _confirmButton(
      _confirmColor(theme, disabled),
      widget.confirmButtonText ?? "alert.ok",
      () => _onConfirm(disabled),
    );
    if (widget.cancelButton != true) {
      return confirm;
    }
    return Row(
      children: [
        Expanded(
          child: _cancelButton(theme, widget.cancelButtonText ?? "alert.cancel"),
        ),
        const SizedBox(width: 12),
        Expanded(child: confirm),
      ],
    );
  }

  Color _confirmColor(ThemeData theme, bool disabled) {
    final base = widget.confirmButtonColor ?? theme.colorScheme.primary;
    return disabled ? base.withValues(alpha: 0.5) : base;
  }

  void _onConfirm(bool disabled) {
    if (disabled) {
      return;
    }
    Navigator.pop(context);
    widget.callback?.call();
  }

  Widget _confirmButton(Color color, String textKey, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: LocaleText(
          textKey,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _cancelButton(ThemeData theme, String textKey) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => Navigator.pop(context),
        style: FilledButton.styleFrom(
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          foregroundColor:
              widget.cancelButtonColor ?? theme.colorScheme.onSurface,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: LocaleText(
          textKey,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  IconData _iconData() {
    if (widget.icon != null) {
      return widget.icon!;
    }
    return switch (widget.type) {
      AlertType.success => Icons.check_circle_rounded,
      AlertType.error => Icons.error_rounded,
      _ => Icons.info_rounded,
    };
  }

  Color? _iconColor() {
    if (widget.iconColor != null) {
      return widget.iconColor;
    }
    return switch (widget.type) {
      AlertType.success => Colors.green,
      AlertType.error => Colors.red,
      _ => Theme.of(context).colorScheme.onSurface,
    };
  }
}
