import 'dart:typed_data';
import 'package:insulink/src/pump/protocol/pod_responses.dart';

/// Dispatches a decrypted response body to the parser for its type.
///
/// An unrecognised type is an error rather than a default: silently treating an
/// unknown reply as a status would hand the caller invented delivery numbers.
class PodResponseReader {
  PodResponseReader(this.body);

  static const int _activation = 0x01;
  static const int _additionalStatus = 0x02;
  static const int _nak = 0x06;
  static const int _defaultStatus = 0x1d;
  static const int _versionActivation = 0x15;
  static const int _setUniqueIdActivation = 0x1b;
  static const int _alarmStatusPage = 0x02;

  final Uint8List body;

  PodResponse get response {
    if (body.isEmpty) {
      throw PodResponseException('Empty response body');
    }
    switch (body[0]) {
      case _defaultStatus:
        return PodStatusResponse(body);
      case _nak:
        return PodNakResponse(body);
      case _activation:
        return _activationResponse;
      case _additionalStatus:
        return _additionalStatusResponse;
      default:
        throw PodResponseException(
          'Unrecognised response type 0x${body[0].toRadixString(16)}',
        );
    }
  }

  PodResponse get _activationResponse {
    if (body.length < 2) {
      throw PodResponseException('Activation response has no subtype');
    }
    switch (body[1]) {
      case _versionActivation:
        return PodVersionResponse(body);
      case _setUniqueIdActivation:
        return PodSetUniqueIdResponse(body);
      default:
        throw PodResponseException(
          'Unrecognised activation subtype 0x${body[1].toRadixString(16)}',
        );
    }
  }

  PodResponse get _additionalStatusResponse {
    if (body.length < 3) {
      throw PodResponseException('Additional status response has no page');
    }
    if (body[2] == _alarmStatusPage) {
      return PodAlarmStatusResponse(body);
    }
    throw PodResponseException(
      'Status page 0x${body[2].toRadixString(16)} is not decoded',
    );
  }
}
