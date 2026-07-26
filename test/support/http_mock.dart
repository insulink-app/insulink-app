import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Answers the app's HTTP calls from a map of path → JSON body, so the sync
/// layer can be driven end to end without a server: what a device pulls, what it
/// decides to adopt, and what it pushes back.
///
/// [Request] builds its calls with `package:http`, whose default client is a
/// `dart:io` HttpClient — which is exactly what [HttpOverrides] replaces. Run a
/// test body inside [run] to install it.
class FakeHttp extends HttpOverrides {
  FakeHttp(this.bodies);

  /// Path (without the `/v1` prefix) → the JSON object to answer with.
  final Map<String, Map<String, Object?>> bodies;

  /// Every request made, in order, as (path, decoded body) — the body is empty
  /// for a GET.
  final List<({String path, Map<String, dynamic> body})> sent = [];

  Future<T> run<T>(Future<T> Function() body) =>
      HttpOverrides.runZoned(body, createHttpClient: (_) => _FakeClient(this));

  /// The last request sent to [path], or null when there was none.
  Map<String, dynamic>? lastTo(String path) {
    for (final request in sent.reversed) {
      if (request.path == path) {
        return request.body;
      }
    }
    return null;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeClient(this);
}

class _FakeClient implements HttpClient {
  _FakeClient(this._fake);

  final FakeHttp _fake;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(_fake, url.path.replaceFirst('/v1', ''));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._fake, this._path);

  final FakeHttp _fake;
  final String _path;
  final List<int> _body = [];

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  void add(List<int> data) => _body.addAll(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_body.addAll);

  @override
  Future<HttpClientResponse> close() async {
    _fake.sent.add((path: _path, body: _decodedBody()));
    return _FakeResponse(
      jsonEncode(_fake.bodies[_path] ?? const {'success': false}),
    );
  }

  @override
  Future<HttpClientResponse> get done => close();

  Map<String, dynamic> _decodedBody() {
    if (_body.isEmpty) {
      return const {};
    }
    return (jsonDecode(utf8.decode(_body)) as Map).cast<String, dynamic>();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeResponse implements HttpClientResponse {
  _FakeResponse(this._body);

  final String _body;

  @override
  int get statusCode => 200;

  @override
  int get contentLength => utf8.encode(_body).length;

  @override
  String get reasonPhrase => 'OK';

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(_body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHeaders implements HttpHeaders {
  @override
  void forEach(void Function(String name, List<String> values) action) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
