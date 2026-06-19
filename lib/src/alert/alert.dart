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
    var confirmationDisabled =
        widget.confirmButtonEnabled != null && !widget.confirmButtonEnabled!();
    var theme = Theme.of(context);
    return AlertDialog(
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(15.0))),
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
        children: <Widget>[
          widget.description != null
              ? Container(
                  padding: const EdgeInsets.only(left: 30, right: 30, top: 10),
                  child: LocaleText(
                    widget.description ?? "",
                    textAlign: TextAlign.center,
                  ),
                )
              : widget.content ?? SizedBox.shrink(),
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              widget.cancelButton == true
                  ? Container(
                      margin: EdgeInsets.only(top: 15, bottom: 15, right: 10),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.all(
                              widget.cancelButtonColor ?? Colors.grey),
                          shape: WidgetStateProperty.all(
                              const RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(5.0)))),
                          padding: WidgetStateProperty.all(EdgeInsets.symmetric(
                              horizontal: 15, vertical: 10)),
                          minimumSize: WidgetStateProperty.all(Size(0, 0)),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: LocaleText(
                            widget.cancelButtonText ?? "alert.cancel",
                            style:
                                TextStyle(color: Colors.white, fontSize: 15)),
                      ),
                    )
                  : SizedBox.shrink(),
              Container(
                margin: EdgeInsets.symmetric(vertical: 15),
                child: ElevatedButton(
                  onPressed: () {
                    if (confirmationDisabled) {
                      return;
                    }
                    Navigator.pop(context);
                    widget.callback?.call();
                  },
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(
                        confirmationDisabled
                            ? widget.confirmButtonColor ??
                                theme.colorScheme.primary.withValues(alpha: 0.5)
                            : widget.confirmButtonColor ??
                                theme.colorScheme.primary),
                    shape: WidgetStateProperty.all(const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(5.0)))),
                    padding: WidgetStateProperty.all(
                        EdgeInsets.symmetric(horizontal: 15, vertical: 10)),
                    minimumSize: WidgetStateProperty.all(Size(0, 0)),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: LocaleText(widget.confirmButtonText ?? "alert.ok",
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ],
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
