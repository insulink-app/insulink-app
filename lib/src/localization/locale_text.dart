import 'package:flutter/material.dart';

import 'locales.dart';

class LocaleText extends Text {
  const LocaleText(
    this.k, {
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
  }) : super(k);

  final String k;
  final bool upperCase, localize;
  final List<String>? params, localeParams;

  @override
  Widget build(BuildContext context) {
    String s = !localize
        ? k
        : Locales.string(
            context,
            k,
            params: params,
            localeParams: localeParams,
          );
    if (upperCase) {
      s = s.toUpperCase();
    }
    return Text(
      s,
      style: style,
      overflow: overflow,
      textAlign: textAlign,
      maxLines: maxLines,
    );
  }
}
