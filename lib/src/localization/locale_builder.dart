part of 'locale_notifier.dart';

class LocaleBuilder extends StatefulWidget {
  const LocaleBuilder({required this.builder, super.key});

  final Widget Function(Locale?) builder;

  @override
  LocaleBuilderState createState() => LocaleBuilderState();
}

class LocaleBuilderState extends State<LocaleBuilder> {
  Locale? locale;

  @override
  void initState() {
    super.initState();
    locale = LocalePreference.instance.locale;
  }

  @override
  Widget build(BuildContext context) {
    return LocaleNotifier(
      state: this,
      child: Builder(
        builder: (context) =>
            widget.builder(LocaleNotifier.of(context)!.locale),
      ),
    );
  }

  void changeLocale(String lng) {
    setState(() {
      LocalePreference.instance.setLocale(lng);
      locale = LocalePreference.instance.locale;
    });
  }
}
