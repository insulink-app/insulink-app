import 'package:flutter/material.dart';
import 'package:insulink/src/localization/locale_text.dart';

enum AlertType { success, error, neutral }

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

  void show(BuildContext context) {
    showDialog(context: context, builder: (BuildContext context) => this);
  }
}

class AlertState extends State<Alert> {
  void reload() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(26.0)),
      ),
      contentPadding: const EdgeInsets.only(top: 24),
      title: Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: createAlertIconColor()?.withValues(alpha: 0.12),
          ),
          child: createAlertIcon(),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [_message(), _actions(theme)],
      ),
    );
  }

  /// The dialog body: a localized description, or a custom [content] widget.
  Widget _message() {
    if (widget.description == null) {
      return widget.content ?? const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.only(left: 30, right: 30, top: 10),
      child: LocaleText(widget.description ?? "", textAlign: TextAlign.center),
    );
  }

  /// The large, full-width action buttons: an optional outlined cancel next to
  /// the filled confirm.
  Widget _actions(ThemeData theme) {
    final disabled =
        widget.confirmButtonEnabled != null && !widget.confirmButtonEnabled!();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Row(
        children: [
          if (widget.cancelButton == true) ...[
            Expanded(
              child: _cancelButton(
                widget.cancelButtonColor,
                widget.cancelButtonText ?? "alert.cancel",
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _confirmButton(
              _confirmColor(theme, disabled),
              widget.confirmButtonText ?? "alert.ok",
              () => _onConfirm(disabled),
            ),
          ),
        ],
      ),
    );
  }

  Color _confirmColor(ThemeData theme, bool disabled) {
    if (widget.confirmButtonColor != null) {
      return widget.confirmButtonColor!;
    }
    final primary = theme.colorScheme.primary;
    return disabled ? primary.withValues(alpha: 0.5) : primary;
  }

  void _onConfirm(bool disabled) {
    if (disabled) {
      return;
    }
    Navigator.pop(context);
    widget.callback?.call();
  }

  Widget _confirmButton(Color color, String textKey, VoidCallback onPressed) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size.fromHeight(50),
      ),
      child: LocaleText(
        textKey,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _cancelButton(Color? color, String textKey) {
    return OutlinedButton(
      onPressed: () => Navigator.pop(context),
      style: OutlinedButton.styleFrom(
        foregroundColor: color ?? Theme.of(context).colorScheme.onSurface,
        minimumSize: const Size.fromHeight(50),
      ),
      child: LocaleText(
        textKey,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget createAlertIcon() {
    IconData? iconData = Icons.info_rounded;
    if (widget.icon != null) {
      iconData = widget.icon;
    } else if (widget.type != null) {
      if (widget.type == AlertType.success) {
        iconData = Icons.check_circle_rounded;
      } else if (widget.type == AlertType.error) {
        iconData = Icons.error_rounded;
      }
    }
    return Icon(iconData, size: 38, color: createAlertIconColor());
  }

  Color? createAlertIconColor() {
    Color? iconColor = Theme.of(context).colorScheme.onSurface;
    if (widget.iconColor != null) {
      iconColor = widget.iconColor;
    } else if (widget.type != null) {
      if (widget.type == AlertType.success) {
        iconColor = Colors.green;
      } else if (widget.type == AlertType.error) {
        iconColor = Colors.red;
      }
    }
    return iconColor;
  }
}
