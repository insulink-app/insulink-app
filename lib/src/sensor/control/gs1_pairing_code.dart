/// Extracts the G7 pairing code from a scanned sensor-box code.
///
/// The Dexcom box carries a GS1 DataMatrix whose payload is **either**:
///   * a GS1 Digital Link URL —
///     `https://go.gs1.org/01/00386270004871/21/515929398457?…&240=2344`, or
///   * a raw GS1 element string —
///     `010038627000487121515929398457<GS>11251201 17270531 2402344`
/// The pairing code is GS1 Application Identifier **240** ("additional item
/// id"). Both encodings are handled here.
class Gs1PairingCode {
  Gs1PairingCode.parse(this.raw);

  final String raw;

  /// FNC1 group separator (ASCII 29) between variable-length GS1 elements.
  static const int _gs = 0x1d;

  /// AIs Dexcom uses, with the data length (chars after the AI) for the
  /// fixed-length ones. Anything not listed is read up to the next separator.
  /// ponytail: minimal table for the Dexcom payload; add AIs if a box differs.
  static const Map<String, int> _fixedLen = {
    '01': 14,
    '11': 6,
    '12': 6,
    '13': 6,
    '15': 6,
    '16': 6,
    '17': 6,
    '20': 2,
  };
  static const Set<String> _variableAi = {'10', '21', '22', '240', '241'};

  /// The pairing code, or null if the payload carries no AI-240 element.
  String? get value {
    final text = raw.trim();
    return _fromUrl(text) ?? _fromElementString(text);
  }

  String? _fromUrl(String text) {
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return uri.queryParameters['240'] ?? _fromPath(uri.pathSegments);
  }

  String? _fromPath(List<String> segments) {
    final index = segments.indexOf('240');
    if (index < 0 || index + 1 >= segments.length) {
      return null;
    }
    return segments[index + 1];
  }

  String? _fromElementString(String text) {
    var index = _skipLeadingSeparator(text);
    while (index < text.length) {
      final ai = _readAi(text, index);
      if (ai == null) {
        return null;
      }
      index += ai.length;
      if (ai == '240') {
        return _readUntilSeparator(text, index);
      }
      index = _skipValue(text, index, ai);
    }
    return null;
  }

  int _skipLeadingSeparator(String text) {
    return text.isNotEmpty && text.codeUnitAt(0) == _gs ? 1 : 0;
  }

  /// Matches a known AI at [index], trying the longest first (4→3→2 digits).
  String? _readAi(String text, int index) {
    for (final length in const [4, 3, 2]) {
      if (index + length > text.length) {
        continue;
      }
      final candidate = text.substring(index, index + length);
      if (_fixedLen.containsKey(candidate) || _variableAi.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  int _skipValue(String text, int index, String ai) {
    final fixed = _fixedLen[ai];
    if (fixed != null) {
      return index + fixed;
    }
    final next = index + _readUntilSeparator(text, index).length;
    return next < text.length ? next + 1 : next;
  }

  String _readUntilSeparator(String text, int start) {
    var end = start;
    while (end < text.length && text.codeUnitAt(end) != _gs) {
      end++;
    }
    return text.substring(start, end);
  }
}
