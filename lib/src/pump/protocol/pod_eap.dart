import 'dart:typed_data';

/// Raised when an EAP message off the wire cannot be read.
class PodEapException implements Exception {
  PodEapException(this.message);

  final String message;

  @override
  String toString() => 'PodEapException: $message';
}

/// The EAP roles, as in RFC 3748.
enum PodEapCode {
  request(1),
  response(2),
  success(3),
  failure(4);

  const PodEapCode(this.value);

  final int value;

  static PodEapCode byValue(int value) => PodEapCode.values.firstWhere(
    (entry) => entry.value == value,
    orElse: () => throw PodEapException('Unknown EAP code: $value'),
  );
}

/// The EAP-AKA attribute types the pod exchanges.
enum PodEapAttributeType {
  rand(1, 20),
  autn(2, 20),
  res(3, 12),
  auts(4, 16),
  clientErrorCode(22, 4),
  customIv(126, 8);

  const PodEapAttributeType(this.value, this.declaredSize);

  final int value;

  /// The size the attribute declares on the wire, in bytes.
  final int declaredSize;

  static PodEapAttributeType byValue(int value) =>
      PodEapAttributeType.values.firstWhere(
        (entry) => entry.value == value,
        orElse: () =>
            throw PodEapException('Unknown EAP-AKA attribute: $value'),
      );
}

/// One EAP-AKA attribute: a type, a length in 4-byte units, two bytes that are
/// reserved for most types, and the payload.
class PodEapAttribute {
  const PodEapAttribute(this.type, this.payload);

  final PodEapAttributeType type;
  final Uint8List payload;

  /// `AT_RES` puts its payload length in bits where the others keep a reserved
  /// zero, so the fourth header byte is not always zero.
  int get _fourthByte =>
      type == PodEapAttributeType.res ? payload.length * 8 : 0;

  Uint8List get encoded => Uint8List.fromList([
    type.value,
    type.declaredSize ~/ 4,
    0,
    _fourthByte,
    ...payload,
  ]);
}

/// An EAP message carrying the AKA challenge, its response, or a bare
/// success/failure.
///
/// The pod's session handshake is EAP-AKA with the pairing key standing in for a
/// SIM key: we send a challenge built from [Milenage], the pod answers with the
/// expected response and its half of the message nonce.
class PodEapMessage {
  const PodEapMessage({
    required this.code,
    required this.identifier,
    this.subType = 0,
    this.attributes = const <PodEapAttribute>[],
  });

  static const int _headerSize = 8;
  static const int _akaPacketType = 0x17;
  static const int subTypeChallenge = 1;
  static const int subTypeSynchronizationFailure = 4;

  final PodEapCode code;
  final int identifier;
  final int subType;
  final List<PodEapAttribute> attributes;

  Uint8List toBytes() {
    if (attributes.isEmpty) {
      return Uint8List.fromList([code.value, identifier & 0xFF, 0, 4]);
    }
    final body = <int>[];
    for (final attribute in attributes) {
      body.addAll(attribute.encoded);
    }
    final total = _headerSize + body.length;
    return Uint8List.fromList([
      code.value,
      identifier & 0xFF,
      (total >> 8) & 0xFF,
      total & 0xFF,
      _akaPacketType,
      subType == 0 ? subTypeChallenge : subType,
      0,
      0,
      ...body,
    ]);
  }

  static PodEapMessage parse(Uint8List payload) {
    if (payload.length < 4) {
      throw PodEapException('EAP message shorter than its header');
    }
    final total = (payload[2] << 8) | payload[3];
    if (payload.length < total) {
      throw PodEapException('EAP message truncated: declares $total');
    }
    if (payload.length == 4) {
      return PodEapMessage(
        code: PodEapCode.byValue(payload[0]),
        identifier: payload[1],
      );
    }
    if (total > 0 && payload[4] != _akaPacketType) {
      throw PodEapException('Not an EAP-AKA packet: type ${payload[4]}');
    }
    return PodEapMessage(
      code: PodEapCode.byValue(payload[0]),
      identifier: payload[1],
      subType: payload[5],
      attributes: _parseAttributes(payload.sublist(_headerSize, total)),
    );
  }

  static List<PodEapAttribute> _parseAttributes(Uint8List body) {
    final out = <PodEapAttribute>[];
    var offset = 0;
    while (offset < body.length) {
      if (body.length - offset < 2) {
        throw PodEapException('Trailing bytes are not an attribute');
      }
      final type = PodEapAttributeType.byValue(body[offset]);
      final step = 4 * body[offset + 1];
      if (step <= 0 || body.length - offset < step) {
        throw PodEapException(
          'Attribute ${type.name} declares $step bytes it lacks',
        );
      }
      out.add(PodEapAttribute(type, _payloadOf(type, body, offset)));
      offset += step;
    }
    return out;
  }

  /// AUTS carries its payload straight after the two-byte header; every other
  /// type skips the two reserved bytes as well.
  static Uint8List _payloadOf(
    PodEapAttributeType type,
    Uint8List body,
    int offset,
  ) {
    if (type == PodEapAttributeType.auts) {
      return body.sublist(offset + 2, offset + type.declaredSize);
    }
    return body.sublist(offset + 4, offset + type.declaredSize);
  }
}
