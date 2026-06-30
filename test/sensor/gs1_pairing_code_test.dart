import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/sensor/control/gs1_pairing_code.dart';

void main() {
  final gs = String.fromCharCode(0x1d);

  group('Gs1PairingCode.value', () {
    test('reads AI 240 from a Digital Link query string', () {
      const url =
          'https://go.gs1.org/01/00386270004871/21/515929398457?11=251201&17=270531&240=2344';
      expect(Gs1PairingCode.parse(url).value, '2344');
    });

    test('reads a second Digital Link example', () {
      const url =
          'https://go.gs1.org/01/00386270004871/21/698926479289?11=251201&17=270531&240=2585';
      expect(Gs1PairingCode.parse(url).value, '2585');
    });

    test('reads AI 240 encoded as a path pair', () {
      const url = 'https://go.gs1.org/01/00386270004871/240/2344';
      expect(Gs1PairingCode.parse(url).value, '2344');
    });

    test('reads AI 240 from a raw GS1 element string (GS after the serial)', () {
      final raw = '010038627000487121515929398457${gs}11251201172705312402344';
      expect(Gs1PairingCode.parse(raw).value, '2344');
    });

    test('reads AI 240 as the trailing element with no serial', () {
      const raw = '010038627000487111251201172705312402585';
      expect(Gs1PairingCode.parse(raw).value, '2585');
    });

    test('returns null when no AI 240 is present', () {
      expect(Gs1PairingCode.parse('https://example.com/foo').value, isNull);
    });

    test('returns null for non-URL junk', () {
      expect(Gs1PairingCode.parse('not a uri at all ::::').value, isNull);
    });
  });
}
