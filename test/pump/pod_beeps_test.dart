import 'package:flutter_test/flutter_test.dart';
import 'package:insulink/src/pump/protocol/pod_control_commands.dart';
import 'package:insulink/src/pump/protocol/pod_definitions.dart';

/// The beep vector from the reference driver's own test suite
/// (`ProgramBeepsCommandTest.kt`), byte for byte. It is the only published
/// vector for this command, so it is the contract.
void main() {
  test('the test-beep command matches the reference byte for byte', () {
    final command = PodProgramBeepsCommand(
      uniqueId: 37879810,
      sequenceNumber: 11,
      immediateBeep: PodBeep.fourTimesBipBeep,
    );

    final hex = command.encoded
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(hex, '024200022c061e0402000000800f');
  });
}
