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
  production("insulink.de", "api.insulink.de"),
  staging("insulink.de", "api.insulink.de");

  const InsulinkEnvironment(this._domain, this._endpoint);

  final String _domain;
  final String _endpoint;

  String get domain => _domain;

  String get endpoint => _endpoint;
}
