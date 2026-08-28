/// The locale key suffix for an enum value.
///
/// Locale keys are snake_case throughout, and Dart enum values are camelCase, so
/// a key built straight from `name` would be the one camelCase key in the files.
/// This converts at the call site instead of bending either convention: the enum
/// keeps the name Dart wants, the locale file keeps the shape every other key
/// has.
extension EnumLocaleKey on Enum {
  String get localeKey => name.replaceAllMapped(
        RegExp('[A-Z]'),
        (match) => '_${match[0]!.toLowerCase()}',
      );
}
