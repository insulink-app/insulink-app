import 'package:flutter/cupertino.dart';
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
        borderRadius: BorderRadius.all(Radius.circular(15.0)),
      ),
      contentPadding: const EdgeInsets.only(top: 10),
      title: Center(
        child: CircleAvatar(
          radius: 30,
          backgroundColor: theme.appBarTheme.backgroundColor,
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

  /// The (optional) cancel button next to the confirm button.
  Widget _actions(ThemeData theme) {
    final disabled =
        widget.confirmButtonEnabled != null && !widget.confirmButtonEnabled!();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.cancelButton == true)
          Container(
            margin: const EdgeInsets.only(top: 15, bottom: 15, right: 10),
            child: _button(
              color: widget.cancelButtonColor ?? Colors.grey,
              textKey: widget.cancelButtonText ?? "alert.cancel",
              onPressed: () => Navigator.pop(context),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 15),
          child: _button(
            color: _confirmColor(theme, disabled),
            textKey: widget.confirmButtonText ?? "alert.ok",
            onPressed: () => _onConfirm(disabled),
          ),
        ),
      ],
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

  /// The shared compact, rounded action button used for both cancel and confirm.
  Widget _button({
    required Color color,
    required String textKey,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(color),
        shape: WidgetStateProperty.all(
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(5.0)),
          ),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        ),
        minimumSize: WidgetStateProperty.all(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: LocaleText(
        textKey,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      ),
    );
  }

  Widget createAlertIcon() {
    IconData? iconData = CupertinoIcons.circle;
    if (widget.icon != null) {
      iconData = widget.icon;
    } else if (widget.type != null) {
      if (widget.type == AlertType.success) {
        iconData = CupertinoIcons.check_mark_circled;
      } else if (widget.type == AlertType.error) {
        iconData = CupertinoIcons.exclamationmark_triangle;
      }
    }
    return Icon(iconData, size: 35, color: createAlertIconColor());
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
