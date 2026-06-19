import 'package:flutter/cupertino.dart';
import 'package:insulink/src/localization/locale_preference.dart';

part 'locale_builder.dart';

class LocaleNotifier extends InheritedWidget {
  final LocaleBuilderState? state;

  const LocaleNotifier({
    super.key,
    this.state,
    required super.child,
  });

  static LocaleNotifier? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LocaleNotifier>();
  }

  change(String lng) => state!.changeLocale(lng);

  Locale? get locale => state!.locale;

  @override
  bool updateShouldNotify(LocaleNotifier oldWidget) => true;
}
