import 'package:flutter/material.dart';

import 'locales.dart';

class LocaleText extends Text {
  const LocaleText(
    this.localeKey, {
    super.style,
    this.upperCase = false,
    super.key,
    super.overflow,
    this.localize = true,
    this.params,
    super.textAlign,
    super.textDirection,
    this.localeParams,
    super.maxLines,
  }) : super(localeKey);

  final String localeKey;
  final bool upperCase, localize;
  final List<String>? params, localeParams;

  @override
  Widget build(BuildContext context) {
    String text = !localize
        ? localeKey
        : Locales.string(
            context,
            localeKey,
            params: params,
            localeParams: localeParams,
          );
    if (upperCase) {
      text = text.toUpperCase();
    }
    return Text(
      text,
      style: style,
      overflow: overflow,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}
