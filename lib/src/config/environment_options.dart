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
  production("insulink.de", "api.insulink.de", "panel.insulink.de"),
  staging("insulink.de", "api.insulink.de", "panel.insulink.de");

  const InsulinkEnvironment(this._domain, this._endpoint, this.panel);

  final String _domain;
  final String _endpoint;

  /// The panel's host, where a glucose share link opens.
  final String panel;

  String get domain => _domain;

  String get endpoint => _endpoint;
}
