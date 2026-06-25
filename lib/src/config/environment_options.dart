class EnvironmentOptions {
  static const String _environmentParameter = String.fromEnvironment(
    "ENVIRONMENT",
  );
  static const InsulinkEnvironment environment =
      _environmentParameter == "STAGING"
      ? InsulinkEnvironment.staging
      : InsulinkEnvironment.production;
}

enum InsulinkEnvironment {
  production("insulink.de", "insulink.lukasbreuer.de"),
  staging("insulink.de", "insulink.lukasbreuer.de");

  const InsulinkEnvironment(this._domain, this._endpoint);

  final String _domain;
  final String _endpoint;

  String get domain => _domain;

  String get endpoint => _endpoint;
}
